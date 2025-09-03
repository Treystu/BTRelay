#!/usr/bin/env bash
set -euo pipefail
test -f app/build.gradle || { echo "Run from mobile-relay/android"; exit 1; }

# --- Manifest: ensure central+peripheral+network perms and FGS type ---
cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <uses-sdk android:minSdkVersion="26" android:targetSdkVersion="34"/>
  <uses-feature android:name="android.hardware.bluetooth_le" android:required="false"/>

  <!-- Network -->
  <uses-permission android:name="android.permission.INTERNET"/>
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>

  <!-- Bluetooth pre-31 -->
  <uses-permission android:name="android.permission.BLUETOOTH"/>
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>

  <!-- Bluetooth 31+ -->
  <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
      android:usesPermissionFlags="neverForLocation"/>

  <!-- Location needed for scan on API 26–30 -->
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>

  <!-- Foreground services -->
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE"/>

  <!-- Notifications (33+) -->
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

  <application android:allowBackup="false" android:usesCleartextTraffic="false">
    <service
      android:name=".RelayBleService"
      android:foregroundServiceType="connectedDevice"
      android:exported="false"/>
    <service
      android:name=".CentralBackhaulService"
      android:foregroundServiceType="connectedDevice"
      android:exported="false"/>
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

# --- Central backhaul foreground service ---
cat > app/src/main/java/com/example/relay/CentralBackhaulService.kt <<'EOF'
package com.example.relay

import android.app.*
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.Intent
import android.os.*
import android.util.Base64
import android.util.Log
import java.util.UUID

class CentralBackhaulService : Service() {
  private val TAG = "CentralBackhaul"
  private val svc = UUID.fromString("5f1dd9f0-5c4a-4a0f-9b6d-27f1a5f6a9b1")
  private val msgIn = UUID.fromString("8b21f1b8-9b7f-4b17-9f3e-7a0e9b6e2a10")
  private val ack   = UUID.fromString("3e9c2d6a-1b1e-4f1c-8a62-0c4f7a9b12aa")
  private val cccd  = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

  private val h = Handler(Looper.getMainLooper())
  private val bm by lazy { getSystemService(BluetoothManager::class.java) }
  private val scanner get() = bm?.adapter?.bluetoothLeScanner
  private var gatt: BluetoothGatt? = null
  private var sending = false
  private var sentCount = 0

  override fun onBind(intent: Intent?) = null

  override fun onCreate() {
    super.onCreate()
    startForeground(2, note("Central starting"))
    startScanLoop()
  }

  override fun onDestroy() {
    stopScan()
    try { gatt?.close() } catch (_: Throwable) {}
    super.onDestroy()
  }

  // ---- scanning/connect/write ----
  private fun startScanLoop() {
    if (scanner == null) { update("No scanner"); stopSelf(); return }
    update("Scanning")
    try {
      val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(svc)).build()
      val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
      scanner!!.startScan(listOf(filter), settings, scanCb)
      h.postDelayed({ restartScan("not found") }, 10000)
    } catch (t: Throwable) { Log.e(TAG,"scan start failed",t); restartScan("scan failed") }
  }

  private fun stopScan() { try { scanner?.stopScan(scanCb) } catch (_: Throwable) {} }

  private fun restartScan(reason: String) {
    stopScan()
    update("Scan retry: $reason")
    h.postDelayed({ startScanLoop() }, 2000)
  }

  private val scanCb = object: ScanCallback() {
    override fun onScanResult(cbType: Int, res: ScanResult) {
      stopScan()
      update("Connecting ${res.device.address}")
      gatt = res.device.connectGatt(this@CentralBackhaulService, false, gattCb)
    }
    override fun onScanFailed(errorCode: Int) { restartScan("code $errorCode") }
  }

  private val gattCb = object: BluetoothGattCallback() {
    override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
      if (newState == BluetoothProfile.STATE_CONNECTED) { g.discoverServices() }
      else if (newState == BluetoothProfile.STATE_DISCONNECTED) { update("Disconnected"); g.close(); restartScan("disconnect") }
    }
    override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
      val service = g.getService(svc) ?: return fail("no service")
      val ackCh = service.getCharacteristic(ack) ?: return fail("no ack char")
      val msgCh = service.getCharacteristic(msgIn) ?: return fail("no msg char")
      g.setCharacteristicNotification(ackCh, true)
      val d = ackCh.getDescriptor(cccd)
      if (d != null) {
        d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        g.writeDescriptor(d)
      } else sendOnce(g, msgCh)
    }
    override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
      val msgCh = g.getService(svc)?.getCharacteristic(msgIn) ?: return fail("no msg after desc")
      sendOnce(g, msgCh)
    }
    override fun onCharacteristicChanged(g: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray) {
      if (ch.uuid == ack) {
        update("ACK: ${String(value)} • sent=$sentCount")
        h.postDelayed({ g.disconnect() }, 200) // drop link and resume scan
      }
    }
  }

  private fun fail(msg: String) { update("Fail: $msg"); gatt?.disconnect() }

  private fun buildPayload(destUrl: String, secret: ByteArray): ByteArray {
    val id = java.util.UUID.randomUUID().toString()
    val ts = (System.currentTimeMillis()/1000L)
    val body = Base64.encodeToString("a".toByteArray(), Base64.NO_WRAP)
    val hmac = HmacUtil.hmacSha256Hex(secret, 1, id, ts, destUrl, body)
    val json = """{"v":1,"id":"$id","ts":$ts,"dest":"$destUrl","body":"$body","hmac":"$hmac"}"""
    return json.toByteArray(Charsets.UTF_8) + byteArrayOf(0x01)
  }

  @Suppress("DEPRECATION")
  private fun sendOnce(g: BluetoothGatt, msgCh: BluetoothGattCharacteristic) {
    if (sending) return
    val p = getSharedPreferences("central", MODE_PRIVATE)
    val dest = p.getString("dest","") ?: ""
    val intervalMs = p.getLong("intervalMs", 5000L)
    if (!dest.startsWith("https://")) { update("Set HTTPS dest in app"); g.disconnect(); return }
    val payload = buildPayload(dest, Settings.load(this).secret)
    try {
      sending = true
      if (Build.VERSION.SDK_INT >= 33) {
        g.writeCharacteristic(msgCh, payload, BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)
      } else {
        msgCh.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        msgCh.value = payload
        g.writeCharacteristic(msgCh)
      }
      sentCount++
      update("Sent • waiting ACK")
    } catch (t: Throwable) {
      update("Write failed"); g.disconnect(); return
    } finally {
      sending = false
    }
    // If no ACK within timeout, disconnect and rescan
    h.postDelayed({
      try { g.disconnect() } catch (_: Throwable) {}
      h.postDelayed({ startScanLoop() }, intervalMs)
    }, 2000)
  }

  // ---- notifications ----
  private fun note(text: String): Notification {
    val id = "central"
    val nm = getSystemService(NotificationManager::class.java)
    if (nm.getNotificationChannel(id) == null) {
      nm.createNotificationChannel(NotificationChannel(id, "Central", NotificationManager.IMPORTANCE_LOW))
    }
    return Notification.Builder(this, id)
      .setContentTitle(text)
      .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
      .build()
  }
  private fun update(text: String) {
    getSystemService(NotificationManager::class.java).notify(2, note(text))
    Log.i(TAG, text)
  }
}
EOF

# --- UI: add fields + buttons for central auto mode (escape & properly) ---
cat > app/src/main/res/layout/activity_main.xml <<'EOF'
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">
  <LinearLayout
      android:orientation="vertical"
      android:padding="16dp"
      android:layout_width="match_parent"
      android:layout_height="wrap_content">

    <TextView android:text="Secret (hex, 32 bytes)"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <EditText android:id="@+id/secret" android:inputType="textVisiblePassword"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <TextView android:text="Rate bytes/sec"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <EditText android:id="@+id/rate" android:inputType="number"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <TextView android:text="Burst bytes"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <EditText android:id="@+id/burst" android:inputType="number"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <TextView android:text="Monthly cap bytes"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <EditText android:id="@+id/cap" android:inputType="number"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <Button android:id="@+id/btnSave" android:text="Save"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <Button android:id="@+id/btnStart" android:text="Start Service"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <Button android:id="@+id/btnStop" android:text="Stop Service"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <View android:layout_width="match_parent" android:layout_height="12dp"/>

    <TextView android:text="Auto Central (phone → relay)"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <TextView android:text="HTTPS dest"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <EditText android:id="@+id/dest" android:hint="https://webhook.site/your-id"
        android:inputType="textUri" android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <TextView android:text="Interval ms"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <EditText android:id="@+id/interval" android:text="5000" android:inputType="number"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

    <Button android:id="@+id/btnCentralStart" android:text="Start Central Auto"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>
    <Button android:id="@+id/btnCentralStop" android:text="Stop Central Auto"
        android:layout_width="match_parent" android:layout_height="wrap_content"/>

  </LinearLayout>
</ScrollView>
EOF

# --- Activity: wire central buttons and persist settings ---
cat > app/src/main/java/com/example/relay/MainActivity.kt <<'EOF'
package com.example.relay
import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat

class MainActivity: ComponentActivity() {
  private val reqPerms = registerForActivityResult(
    ActivityResultContracts.RequestMultiplePermissions()
  ) { }
  private val reqNotif = registerForActivityResult(
    ActivityResultContracts.RequestPermission()
  ) { }
  private val reqEnableBt = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
  ) { }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_main)

    val perms = mutableListOf(
      Manifest.permission.BLUETOOTH_ADVERTISE,
      Manifest.permission.BLUETOOTH_CONNECT
    )
    if (Build.VERSION.SDK_INT >= 31) perms += Manifest.permission.BLUETOOTH_SCAN
    if (Build.VERSION.SDK_INT <= 30) perms += Manifest.permission.ACCESS_FINE_LOCATION
    if (Build.VERSION.SDK_INT >= 33) reqNotif.launch(Manifest.permission.POST_NOTIFICATIONS)
    reqPerms.launch(perms.toTypedArray())

    val cfg = Settings.load(this)
    val secret = findViewById<EditText>(R.id.secret); secret.setText(Settings.bytesToHex(cfg.secret))
    val rate = findViewById<EditText>(R.id.rate); rate.setText(cfg.rate.toString())
    val burst = findViewById<EditText>(R.id.burst); burst.setText(cfg.burst.toString())
    val cap = findViewById<EditText>(R.id.cap); cap.setText(cfg.cap.toString())

    val p = getSharedPreferences("central", MODE_PRIVATE)
    val dest = findViewById<EditText>(R.id.dest); dest.setText(p.getString("dest","") ?: "")
    val interval = findViewById<EditText>(R.id.interval); interval.setText(p.getLong("intervalMs",5000).toString())

    findViewById<Button>(R.id.btnSave).setOnClickListener {
      Settings.save(this,
        secret.text.toString(),
        rate.text.toString().toLongOrNull() ?: cfg.rate,
        burst.text.toString().toLongOrNull() ?: cfg.burst,
        cap.text.toString().toLongOrNull() ?: cfg.cap)
      Toast.makeText(this, "Saved", Toast.LENGTH_SHORT).show()
    }

    findViewById<Button>(R.id.btnStart).setOnClickListener {
      val bt = BluetoothAdapter.getDefaultAdapter()
      if (bt == null) { toast("No Bluetooth adapter"); return@setOnClickListener }
      if (!bt.isEnabled) { reqEnableBt.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)); return@setOnClickListener }
      if (!bt.isMultipleAdvertisementSupported) { toast("BLE peripheral unsupported"); return@setOnClickListener }
      ContextCompat.startForegroundService(this, Intent(this, RelayBleService::class.java))
      toast("Relay starting")
    }

    findViewById<Button>(R.id.btnStop).setOnClickListener {
      stopService(Intent(this, RelayBleService::class.java)); toast("Relay stopped")
    }

    findViewById<Button>(R.id.btnCentralStart).setOnClickListener {
      val d = dest.text.toString().trim()
      val iv = interval.text.toString().toLongOrNull() ?: 5000L
      p.edit().putString("dest", d).putLong("intervalMs", iv).apply()
      ContextCompat.startForegroundService(this, Intent(this, CentralBackhaulService::class.java))
      toast("Central auto starting")
    }
    findViewById<Button>(R.id.btnCentralStop).setOnClickListener {
      stopService(Intent(this, CentralBackhaulService::class.java)); toast("Central auto stopped")
    }
  }
  private fun toast(s: String) = Toast.makeText(this, s, Toast.LENGTH_SHORT).show()
}
EOF

# --- Build & install ---
./gradlew clean assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk || true

echo "Done."
echo "- Phone A: Start Service (Relay). Notification should read 'Relay active'."
echo "- Phone B: set HTTPS dest + interval, tap 'Start Central Auto'. Keep both secrets identical."
echo "- Expect ACK toasts in B's notification text and HTTPS POSTs from A."


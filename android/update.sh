#!/usr/bin/env bash
set -euo pipefail
test -f app/build.gradle || { echo "Run from mobile-relay/android"; exit 1; }

# Replace RelayBleService with Moshi KotlinJsonAdapterFactory and keep prior hardening
cat > app/src/main/java/com/example/relay/RelayBleService.kt <<'EOF'
package com.example.relay
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Intent
import android.os.IBinder
import android.os.ParcelUuid
import android.util.Log
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import java.util.UUID

class RelayBleService: Service() {
  private val TAG = "RelayBleService"

  private lateinit var gatt: BluetoothGattServer
  private var advertiser: BluetoothLeAdvertiser? = null
  private val queue by lazy { MessageQueue(this) }
  private val cfg by lazy { Settings.load(this) }
  private val sender by lazy {
    NetSender(this, Throttle(
      rateBytesPerSec = cfg.rate,
      burstBytes = cfg.burst,
      monthlyCapBytes = cfg.cap,
      persist = { t,m -> getSharedPreferences("th", MODE_PRIVATE).edit().putLong("tok",t).putLong("mon",m).apply() },
      load = { val p=getSharedPreferences("th", MODE_PRIVATE); p.getLong("tok",cfg.burst) to p.getLong("mon",0) }
    ))
  }
  private val serviceUUID = UUID.fromString("5f1dd9f0-5c4a-4a0f-9b6d-27f1a5f6a9b1")
  private val msgInUUID   = UUID.fromString("8b21f1b8-9b7f-4b17-9f3e-7a0e9b6e2a10")
  private val ackUUID     = UUID.fromString("3e9c2d6a-1b1e-4f1c-8a62-0c4f7a9b12aa")
  private val assembler = FrameAssembler()
  private val adapter by lazy {
    Moshi.Builder().add(KotlinJsonAdapterFactory()).build().adapter(Frame::class.java)
  }

  override fun onCreate() {
    super.onCreate()
    try {
      startForeground(1, notification("Relay starting"))

      val bm = getSystemService(BluetoothManager::class.java)
      val btAdapter = bm?.adapter
      if (btAdapter == null || !btAdapter.isEnabled) { notifyAndStop("Bluetooth off or unavailable"); return }
      if (!btAdapter.isMultipleAdvertisementSupported) { notifyAndStop("BLE peripheral unsupported"); return }

      gatt = bm.openGattServer(this, cb)
      gatt.addService(BluetoothGattService(serviceUUID, BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
        addCharacteristic(BluetoothGattCharacteristic(
          msgInUUID,
          BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
          BluetoothGattCharacteristic.PERMISSION_WRITE
        ))
        addCharacteristic(BluetoothGattCharacteristic(
          ackUUID,
          BluetoothGattCharacteristic.PROPERTY_NOTIFY,
          BluetoothGattCharacteristic.PERMISSION_READ
        ))
      })

      advertiser = btAdapter.bluetoothLeAdvertiser
      if (advertiser == null) { notifyAndStop("No advertiser"); return }
      advertiser!!.startAdvertising(
        AdvertiseSettings.Builder()
          .setConnectable(true)
          .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
          .build(),
        AdvertiseData.Builder()
          .addServiceUuid(ParcelUuid(serviceUUID))
          .setIncludeDeviceName(true)
          .build(),
        advCb
      )

      sender.start()
      updateNotification("Relay active")
    } catch (t: Throwable) {
      Log.e(TAG, "Startup failed", t)
      notifyAndStop("Startup failed")
    }
  }

  private fun notification(text: String): Notification {
    val chanId = "relay"
    val mgr = getSystemService(NotificationManager::class.java)
    if (mgr.getNotificationChannel(chanId) == null) {
      mgr.createNotificationChannel(
        NotificationChannel(chanId, "Relay", NotificationManager.IMPORTANCE_LOW)
      )
    }
    return Notification.Builder(this, chanId)
      .setContentTitle(text)
      .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
      .build()
  }
  private fun updateNotification(text: String) {
    getSystemService(NotificationManager::class.java).notify(1, notification(text))
  }
  private fun notifyAndStop(msg: String){
    try { updateNotification(msg) } catch (_: Throwable) {}
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  private val cb = object: BluetoothGattServerCallback(){
    override fun onCharacteristicWriteRequest(
      device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
      preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray
    ) {
      if(characteristic.uuid == msgInUUID){
        val frameBytes = assembler.append(device.address, value)
        if(frameBytes != null){
          val frame = runCatching { adapter.fromJson(String(frameBytes)) }.getOrNull()
          if(frame != null){
            val ok = HmacUtil.hmacSha256Hex(
              Settings.load(this@RelayBleService).secret,
              frame.v, frame.id, frame.ts, frame.dest, frame.body
            ).equals(frame.hmac, ignoreCase = true)
            if(ok){ queue.enqueue(frameBytes); notifyAck(device, "ok".toByteArray()) }
            else { notifyAck(device, "bad_hmac".toByteArray()) }
          } else notifyAck(device, "bad_json".toByteArray())
        }
        if(responseNeeded) gatt.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
      }
    }
  }

  private fun notifyAck(device: BluetoothDevice, bytes: ByteArray){
    val ch = gatt.getService(serviceUUID).getCharacteristic(ackUUID)
    ch.value = bytes
    gatt.notifyCharacteristicChanged(device, ch, false)
  }

  private val advCb = object: AdvertiseCallback(){
    override fun onStartFailure(errorCode: Int) {
      Log.e(TAG, "Advertising failed: $errorCode")
      notifyAndStop("Advertising failed: $errorCode")
    }
  }

  override fun onBind(intent: Intent?): IBinder? = null
  override fun onDestroy() { advertiser?.stopAdvertising(advCb); if(::gatt.isInitialized) gatt.close() }
}
EOF

echo "Rebuilding…"
./gradlew clean assembleDebug

echo "Install and launch:"
echo "adb install -r app/build/outputs/apk/debug/app-debug.apk"
echo "adb shell am start -n com.example.relay/.MainActivity"


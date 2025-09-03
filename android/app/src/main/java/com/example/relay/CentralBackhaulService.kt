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

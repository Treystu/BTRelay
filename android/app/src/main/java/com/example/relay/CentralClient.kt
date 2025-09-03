package com.example.relay

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.util.Base64
import android.widget.Toast
import java.util.UUID

class CentralClient(private val ctx: Context) {
  private val svc = UUID.fromString("5f1dd9f0-5c4a-4a0f-9b6d-27f1a5f6a9b1")
  private val msgIn = UUID.fromString("8b21f1b8-9b7f-4b17-9f3e-7a0e9b6e2a10")
  private val ack   = UUID.fromString("3e9c2d6a-1b1e-4f1c-8a62-0c4f7a9b12aa")
  private val cccd  = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

  private val bm = ctx.getSystemService(BluetoothManager::class.java)
  private val scanner: BluetoothLeScanner? = bm?.adapter?.bluetoothLeScanner
  private var gatt: BluetoothGatt? = null
  private val h = Handler(Looper.getMainLooper())

  private lateinit var payload: ByteArray

  @SuppressLint("MissingPermission")
  fun scanAndSend(destUrl: String) {
    if (scanner == null) { toast("No scanner"); return }
    if (!destUrl.startsWith("https://")) { toast("Dest must be https://"); return }

    // Build signed frame using app secret
    val cfg = Settings.load(ctx)
    val id = java.util.UUID.randomUUID().toString()
    val ts = (System.currentTimeMillis()/1000L).toString()
    val body = Base64.encodeToString("a".toByteArray(), Base64.NO_WRAP)
    val hmac = HmacUtil.hmacSha256Hex(cfg.secret, 1, id, ts.toLong(), destUrl, body)
    val json = """{"v":1,"id":"$id","ts":$ts,"dest":"$destUrl","body":"$body","hmac":"$hmac"}"""
    payload = json.toByteArray(Charsets.UTF_8) + byteArrayOf(0x01)

    val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(svc)).build()
    val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
    toast("Scanning…")
    scanner.startScan(listOf(filter), settings, scanCb)
    h.postDelayed({ stopScan("not found") }, 10000)
  }

  @SuppressLint("MissingPermission")
  private fun stopScan(reason: String) {
    try { scanner?.stopScan(scanCb) } catch (_: Throwable) {}
    if (reason.isNotEmpty()) toast(reason)
  }

  @SuppressLint("MissingPermission")
  private val scanCb = object: ScanCallback() {
    override fun onScanResult(callbackType: Int, result: ScanResult) {
      if (result.device != null) {
        stopScan("")
        toast("Connecting ${result.device.address}")
        gatt = result.device.connectGatt(ctx, false, gattCb)
      }
    }
  }

  @SuppressLint("MissingPermission")
  private val gattCb = object: BluetoothGattCallback() {
    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
      if (newState == BluetoothProfile.STATE_CONNECTED) {
        gatt.discoverServices()
      } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
        toast("Disconnected"); close()
      }
    }

    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
      val service = gatt.getService(svc) ?: return toast("No service").also { close() }
      val ackCh = service.getCharacteristic(ack) ?: return toast("No ACK char").also { close() }
      val msgCh = service.getCharacteristic(msgIn) ?: return toast("No MSG_IN char").also { close() }

      // Enable notifications on ACK then write payload
      gatt.setCharacteristicNotification(ackCh, true)
      val desc = ackCh.getDescriptor(cccd)
      if (desc != null) {
        desc.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        gatt.writeDescriptor(desc)
      } else {
        writeNoRsp(gatt, msgCh, payload)
      }
    }

    override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
      val service = gatt.getService(svc) ?: return
      val msgCh = service.getCharacteristic(msgIn) ?: return
      writeNoRsp(gatt, msgCh, payload)
    }

    override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
      if (characteristic.uuid == ack) {
        toast("ACK: " + String(value))
        close()
      }
    }
  }

  @Suppress("DEPRECATION")
  @SuppressLint("MissingPermission")
  private fun writeNoRsp(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray) {
    try {
      if (Build.VERSION.SDK_INT >= 33) {
        gatt.writeCharacteristic(ch, value, BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)
      } else {
        ch.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        ch.value = value
        gatt.writeCharacteristic(ch)
      }
      toast("Sent")
    } catch (t: Throwable) {
      toast("Write failed"); close()
    }
  }

  private fun toast(s: String) = android.widget.Toast.makeText(ctx, s, Toast.LENGTH_SHORT).show()
  @SuppressLint("MissingPermission") private fun close() { try { gatt?.close() } catch (_: Throwable) {} }
}

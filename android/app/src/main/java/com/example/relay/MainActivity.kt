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
  ) { /* no-op */ }

  private val reqNotif = registerForActivityResult(
    ActivityResultContracts.RequestPermission()
  ) { /* optional */ }

  private val reqEnableBt = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
  ) { /* user may or may not enable */ }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContentView(R.layout.activity_main)

    val perms = mutableListOf(Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
    if (Build.VERSION.SDK_INT >= 33) reqNotif.launch(Manifest.permission.POST_NOTIFICATIONS)
    reqPerms.launch(perms.toTypedArray())

    val cfg = Settings.load(this)
    val secret = findViewById<EditText>(R.id.secret); secret.setText(Settings.bytesToHex(cfg.secret))
    val rate = findViewById<EditText>(R.id.rate); rate.setText(cfg.rate.toString())
    val burst = findViewById<EditText>(R.id.burst); burst.setText(cfg.burst.toString())
    val cap = findViewById<EditText>(R.id.cap); cap.setText(cfg.cap.toString())

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
      if (bt == null) { Toast.makeText(this, "No Bluetooth adapter", Toast.LENGTH_LONG).show(); return@setOnClickListener }
      if (!bt.isEnabled) { reqEnableBt.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)); return@setOnClickListener }
      if (!bt.isMultipleAdvertisementSupported) { Toast.makeText(this, "BLE peripheral unsupported", Toast.LENGTH_LONG).show(); return@setOnClickListener }
      ContextCompat.startForegroundService(this, Intent(this, RelayBleService::class.java))
      Toast.makeText(this, "Service starting", Toast.LENGTH_SHORT).show()
    }

    findViewById<Button>(R.id.btnStop).setOnClickListener {
      stopService(Intent(this, RelayBleService::class.java))
      Toast.makeText(this, "Service stopped", Toast.LENGTH_SHORT).show()
    }
  }
}

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

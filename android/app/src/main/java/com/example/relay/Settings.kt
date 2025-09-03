package com.example.relay
import android.content.Context

data class Settings(val secret: ByteArray, val rate: Long, val burst: Long, val cap: Long){
  companion object {
    fun load(ctx: Context): Settings {
      val p = ctx.getSharedPreferences("cfg", Context.MODE_PRIVATE)
      val hex = p.getString("secret", "0000000000000000000000000000000000000000000000000000000000000000")!!
      return Settings(
        secret = hexToBytes(hex),
        rate = p.getLong("rate", 10_000),
        burst = p.getLong("burst", 200_000),
        cap = p.getLong("cap", 500L*1024*1024)
      )
    }
    fun save(ctx: Context, hex: String, rate: Long, burst: Long, cap: Long){
      ctx.getSharedPreferences("cfg", Context.MODE_PRIVATE).edit()
        .putString("secret", hex).putLong("rate", rate).putLong("burst", burst).putLong("cap", cap).apply()
    }
    fun hexToBytes(s: String): ByteArray {
      val clean = s.trim().lowercase()
      require(clean.length % 2 == 0) { "hex length must be even" }
      val out = ByteArray(clean.length/2)
      var i = 0
      while (i < clean.length) {
        out[i/2] = clean.substring(i, i+2).toInt(16).toByte()
        i += 2
      }
      return out
    }
    fun bytesToHex(b: ByteArray) = b.joinToString(""){ "%02x".format(it) }
  }
}

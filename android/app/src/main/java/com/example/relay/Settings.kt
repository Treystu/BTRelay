package com.example.relay
import android.content.Context

data class Settings(val secret: ByteArray, val rate: Long, val burst: Long, val cap: Long){
  companion object {
    private const val DEFAULT_SECRET_HEX =
      "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f" // 32 bytes
    private val HEX_RE = Regex("^[0-9a-f]+$")

    fun load(ctx: Context): Settings {
      val p = ctx.getSharedPreferences("cfg", Context.MODE_PRIVATE)
      var hex = (p.getString("secret", DEFAULT_SECRET_HEX) ?: DEFAULT_SECRET_HEX)
        .trim().lowercase().replace("\\s+".toRegex(), "")
      if (!HEX_RE.matches(hex) || hex.length != 64 || hex.length % 2 != 0) {
        hex = DEFAULT_SECRET_HEX
        p.edit().putString("secret", hex).apply()
      }
      return Settings(
        secret = hexToBytes(hex),
        rate = p.getLong("rate", 10_000),
        burst = p.getLong("burst", 200_000),
        cap = p.getLong("cap", 500L * 1024 * 1024)
      )
    }

    fun save(ctx: Context, hex: String, rate: Long, burst: Long, cap: Long){
      val clean = hex.trim().lowercase().replace("\\s+".toRegex(), "")
      require(HEX_RE.matches(clean)) { "secret must be hex" }
      require(clean.length == 64) { "secret must be 32 bytes (64 hex chars)" }
      ctx.getSharedPreferences("cfg", Context.MODE_PRIVATE).edit()
        .putString("secret", clean).putLong("rate", rate)
        .putLong("burst", burst).putLong("cap", cap).apply()
    }

    fun hexToBytes(s: String): ByteArray {
      val out = ByteArray(s.length / 2)
      var i = 0
      while (i < s.length) {
        out[i/2] = s.substring(i, i+2).toInt(16).toByte()
        i += 2
      }
      return out
    }
    fun bytesToHex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }
  }
}

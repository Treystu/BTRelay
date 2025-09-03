package com.example.relay
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
object HmacUtil {
  fun hex(bytes: ByteArray) = bytes.joinToString(""){ "%02x".format(it) }
  fun hmacSha256Hex(secret: ByteArray, v: Int, id: String, ts: Long, dest: String, body: String): String {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(secret, "HmacSHA256"))
    val msg = "$v|$id|$ts|$dest|$body"
    return hex(mac.doFinal(msg.toByteArray()))
  }
}

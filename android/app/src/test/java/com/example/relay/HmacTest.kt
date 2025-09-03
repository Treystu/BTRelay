package com.example.relay
import org.junit.Assert.*
import org.junit.Test

class HmacTest {
  @Test fun vector() {
    val secret = Settings.hexToBytes("0f".repeat(32))
    val h = HmacUtil.hmacSha256Hex(secret, 1, "id", 1234L, "https://x", "YQ==")
    assertEquals("0e23688cf8ffc0af1148abaeea13a502199b2355955f0eb05d98ae2fe70150c8", h)
  }
}

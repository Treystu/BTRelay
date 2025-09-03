package com.example.relay
import org.junit.Assert.*
import org.junit.Test

class FrameAssemblerTest {
  @Test fun reassemble() {
    val a = FrameAssembler()
    val payload = "hello".toByteArray()
    val c1 = payload.copyOfRange(0,3) + byteArrayOf(0)
    val c2 = payload.copyOfRange(3,5) + byteArrayOf(1)
    assertNull(a.append("aa", c1))
    val out = a.append("aa", c2)
    assertNotNull(out)
    assertEquals("hello", out!!.toString(Charsets.UTF_8))
  }
  private operator fun ByteArray.plus(other: ByteArray) = this + other
}

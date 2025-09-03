package com.example.relay
class FrameAssembler {
  private val buf = mutableMapOf<String, MutableList<Byte>>()
  fun append(addr: String, chunk: ByteArray): ByteArray? {
    val finalFlag = chunk.last()
    val data = chunk.copyOfRange(0, chunk.size-1)
    val list = buf.getOrPut(addr){ mutableListOf() }
    list.addAll(data.toList())
    return if(finalFlag.toInt() == 1) {
      val out = list.toByteArray()
      buf.remove(addr)
      out
    } else null
  }
}

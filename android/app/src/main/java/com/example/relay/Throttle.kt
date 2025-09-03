package com.example.relay
import kotlin.math.min
import java.util.concurrent.atomic.AtomicLong
class Throttle(
  private val rateBytesPerSec: Long,
  private val burstBytes: Long,
  private val monthlyCapBytes: Long,
  private val persist: (Long, Long)->Unit,
  private val load: ()->Pair<Long,Long>
){
  private val lastRef = AtomicLong(System.currentTimeMillis())
  private var tokens = burstBytes
  private var monthUsed = 0L
  init { val (t,m)=load(); tokens=t; monthUsed=m }
  @Synchronized fun allow(size: Long): Boolean {
    val now = System.currentTimeMillis()
    val dt = (now - lastRef.get()).coerceAtLeast(0)
    val refill = (rateBytesPerSec * dt) / 1000
    tokens = min(burstBytes, tokens + refill)
    lastRef.set(now)
    if (monthUsed + size > monthlyCapBytes) return false
    if (tokens < size) return false
    tokens -= size
    monthUsed += size
    persist(tokens, monthUsed)
    return true
  }
  @Synchronized fun resetMonth() { monthUsed = 0; persist(tokens, monthUsed) }
}

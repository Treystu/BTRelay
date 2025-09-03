package com.example.relay
import org.junit.Assert.*
import org.junit.Test

class ThrottleTest {
  @Test fun basic() {
    val t = Throttle(1000, 2000, 10_000, {_,_->}, {2000L to 0L})
    assertTrue(t.allow(1000))
    assertFalse(t.allow(20000))
  }
}

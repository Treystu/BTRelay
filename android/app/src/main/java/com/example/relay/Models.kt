package com.example.relay
data class Frame(val v: Int, val id: String, val ts: Long, val dest: String, val body: String, val hmac: String)

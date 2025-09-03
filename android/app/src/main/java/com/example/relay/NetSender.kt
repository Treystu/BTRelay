package com.example.relay
import android.net.*
import android.content.Context
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import kotlinx.coroutines.*
import java.net.HttpURLConnection
import java.net.URL

class NetSender(
  ctx: Context,
  private val throttle: Throttle
){
  private val appCtx = ctx.applicationContext
  private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
  private val q = MessageQueue(appCtx)
  private val cm = appCtx.getSystemService(ConnectivityManager::class.java)
  private val adapter = Moshi.Builder().add(KotlinJsonAdapterFactory()).build().adapter(Frame::class.java)

  fun start() {
    cm.registerDefaultNetworkCallback(object: ConnectivityManager.NetworkCallback(){
      override fun onAvailable(network: Network) { scope.launch { drain() } }
    })
    scope.launch { drain() }
  }

  suspend fun drain(){
    while(true){
      val f = q.next() ?: return
      val data = f.readBytes()
      val frame = runCatching { adapter.fromJson(String(data)) }.getOrNull()
      if(frame == null){ q.remove(f); continue }
      if(!throttle.allow(data.size.toLong())) return
      if(!verify(frame, Settings.load(appCtx).secret)){ q.remove(f); continue }
      if(post(frame.dest, data)){ q.remove(f) } else return
    }
  }

  private fun verify(fr: Frame, secret: ByteArray): Boolean {
    val calc = HmacUtil.hmacSha256Hex(secret, fr.v, fr.id, fr.ts, fr.dest, fr.body)
    return calc.equals(fr.hmac, ignoreCase = true)
  }

  private fun post(dest: String, body: ByteArray): Boolean {
    return try {
      val u = URL(dest)
      (u.openConnection() as HttpURLConnection).run {
        requestMethod = "POST"
        setRequestProperty("Content-Type","application/json")
        doOutput = true
        outputStream.use{ it.write(body) }
        val ok = responseCode in 200..299
        disconnect()
        ok
      }
    } catch(_: Exception){ false }
  }
}

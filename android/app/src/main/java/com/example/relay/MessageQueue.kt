package com.example.relay
import android.content.Context
import java.io.File
import java.util.UUID
class MessageQueue(ctx: Context){
  private val dir = File(ctx.filesDir, "queue").apply{ mkdirs() }
  fun enqueue(bytes: ByteArray){ File(dir, UUID.randomUUID().toString()+".msg").writeBytes(bytes) }
  fun next(): File? = dir.listFiles()?.minByOrNull { it.lastModified() }
  fun remove(f: File) { f.delete() }
  fun size(): Int = dir.listFiles()?.size ?: 0
}

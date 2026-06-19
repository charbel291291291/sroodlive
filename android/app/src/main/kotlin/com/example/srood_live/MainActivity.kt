package com.example.srood_live

import android.content.Intent
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.example.srood_live/voice_room"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(this, VoiceRoomService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        // Non-fatal: foreground service start failed (e.g. SecurityException
                        // on targetSDK 36 when not in eligible state). Room entry continues
                        // normally; only background audio keep-alive is unavailable.
                        Log.w("MainActivity", "[VoiceRoomFG] service unavailable reason=${e.javaClass.simpleName}: ${e.message}")
                        Log.w("MainActivity", "[VoiceRoomFG] continuing without foreground service")
                        result.success(null)
                    }
                }
                "stop" -> {
                    try {
                        stopService(Intent(this, VoiceRoomService::class.java))
                    } catch (e: Exception) {
                        Log.w("MainActivity", "[VoiceRoomFG] stop failed: ${e.message}")
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}

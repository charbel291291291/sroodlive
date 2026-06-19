package com.example.srood_live

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class VoiceRoomService : Service() {

    companion object {
        private const val TAG = "VoiceRoomService"
        const val CHANNEL_ID = "srood_voice_room"
        const val NOTIFICATION_ID = 7001
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Srood Live")
            .setContentText("Voice room active")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setSilent(true)
            .setOngoing(true)
            .build()

        Log.d(TAG, "[VoiceRoomFG] starting foreground service (API ${Build.VERSION.SDK_INT})")

        try {
            when {
                // Android 14+ (API 34): microphone type required for background mic access.
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                    )
                }
                // Android 11-13 (API 30-33): microphone type available.
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK or
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
                    )
                }
                // Android 10 (API 29): only media playback type available.
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q -> {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                    )
                }
                else -> {
                    startForeground(NOTIFICATION_ID, notification)
                }
            }
            Log.d(TAG, "[VoiceRoomFG] service started")
        } catch (e: SecurityException) {
            // On Android 14+ targetSDK 36, starting a foreground service with
            // microphone type requires RECORD_AUDIO to be granted at runtime
            // AND the app to be in an eligible foreground state. If either
            // condition is not met the OS throws SecurityException. Treat this
            // as non-fatal: the user can still hear and speak while the app is
            // in the foreground; only background audio is unavailable.
            Log.w(TAG, "[VoiceRoomFG] foreground microphone service not allowed on this device/state — continuing without it", e)
            stopSelf()
            return START_NOT_STICKY
        } catch (e: Exception) {
            Log.w(TAG, "[VoiceRoomFG] startForeground failed unexpectedly — continuing without it", e)
            stopSelf()
            return START_NOT_STICKY
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    @Suppress("DEPRECATION")
    override fun onDestroy() {
        Log.d(TAG, "[VoiceRoomFG] service stopped")
        stopForeground(true)
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Voice Room",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps voice room audio alive in the background"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}

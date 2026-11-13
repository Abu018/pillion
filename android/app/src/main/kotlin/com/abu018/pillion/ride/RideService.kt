package com.abu018.pillion.ride

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.abu018.pillion.MainActivity

/**
 * Keeps the intercom running with the screen off or the app in the background
 * (Android requires a microphone foreground service for that).
 */
class RideService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            RideController.stop(this)
            return START_NOT_STICKY
        }
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        RideController.engine(this).start()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        RideController.engine(this).stop()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Ride intercom", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while the ride intercom is listening to the microphone"
            }
        )
        val openApp = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, RideService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Ride intercom is on")
            .setContentText("Listening for speech. Audio is not recorded.")
            .setContentIntent(openApp)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "ride_intercom"
        private const val NOTIFICATION_ID = 42
        private const val ACTION_STOP = "com.abu018.pillion.ride.STOP"

        fun start(context: Context) {
            context.startForegroundService(Intent(context, RideService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RideService::class.java))
        }
    }
}

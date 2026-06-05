package com.sosLive.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val deviceChannelName = "sos_live/device_alerts"
    private val volumeEventChannelName = "sos_live/volume_events"
    private val notificationChannelId = "sos_live_sos_alerts"
    private val notificationPermissionRequestCode = 3101

    private var volumeEventSink: EventChannel.EventSink? = null
    private val volumePatternTimestamps = ArrayDeque<Long>()
    private var lastVolumeKeyCode: Int? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
        requestNotificationPermissionIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            deviceChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    ensureNotificationChannel()
                    requestNotificationPermissionIfNeeded()
                    result.success(null)
                }
                "showSosNotification" -> {
                    val title = call.argument<String>("title") ?: "Alerta SOS"
                    val body = call.argument<String>("body") ?: "Nueva emergencia activa"
                    showSosNotification(title, body)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            volumeEventChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                volumeEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                volumeEventSink = null
            }
        })
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_UP)
        ) {
            if (recordVolumeKey(event.keyCode)) {
                volumeEventSink?.success("sos_volume_pattern")
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun recordVolumeKey(keyCode: Int): Boolean {
        val now = System.currentTimeMillis()
        if (lastVolumeKeyCode != keyCode) {
            volumePatternTimestamps.clear()
            lastVolumeKeyCode = keyCode
        }

        volumePatternTimestamps.addLast(now)
        while (volumePatternTimestamps.isNotEmpty() &&
            now - volumePatternTimestamps.first() > 1800
        ) {
            volumePatternTimestamps.removeFirst()
        }

        val matched = volumePatternTimestamps.size >= 3
        if (matched) {
            volumePatternTimestamps.clear()
            lastVolumeKeyCode = null
        }
        return matched
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val channel = NotificationChannel(
            notificationChannelId,
            "Alertas SOS",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Notificaciones de emergencias SOS para agentes"
            enableVibration(true)
            setSound(soundUri, audioAttributes)
        }

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
    }

    private fun showSosNotification(title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            requestNotificationPermissionIfNeeded()
            return
        }

        val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val notification = NotificationCompat.Builder(this, notificationChannelId)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setSound(soundUri)
            .setVibrate(longArrayOf(0, 350, 180, 350, 180, 600))
            .build()

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(System.currentTimeMillis().toInt(), notification)
    }
}

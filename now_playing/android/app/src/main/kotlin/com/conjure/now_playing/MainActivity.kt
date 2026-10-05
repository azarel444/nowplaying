package com.conjure.now_playing

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    private var sink: EventChannel.EventSink? = null
    private var manager: MediaSessionManager? = null
    private var listenerComponent: ComponentName? = null
    private var controller: MediaController? = null
    private var lastTrackKey: String? = null

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { list -> pick(list) }

    private val callback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = push(true)
        override fun onPlaybackStateChanged(state: PlaybackState?) = push(false)
        override fun onSessionDestroyed() = refresh()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        EventChannel(messenger, "nowplaying/stream").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                    sink = events
                    refresh()
                }

                override fun onCancel(args: Any?) {
                    sink = null
                }
            })

        MethodChannel(messenger, "nowplaying/control").setMethodCallHandler { call, result ->
            when (call.method) {
                "playPause" -> {
                    val c = controller
                    if (c?.playbackState?.state == PlaybackState.STATE_PLAYING)
                        c.transportControls.pause() else c?.transportControls?.play()
                    result.success(null)
                }
                "next" -> { controller?.transportControls?.skipToNext(); result.success(null) }
                "previous" -> { controller?.transportControls?.skipToPrevious(); result.success(null) }
                "refresh" -> { refresh(); result.success(null) }
                "openAccessSettings" -> { openAccessSettings(); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }

    // ------------------------------------------------------------ sessions

    private fun hasAccess(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        return flat?.contains(packageName) == true
    }

    private fun refresh() {
        detach()
        if (!hasAccess()) {
            sink?.success(mapOf("access" to false, "active" to false))
            return
        }
        try {
            val m = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val cn = ComponentName(this, MediaListenerService::class.java)
            manager = m
            listenerComponent = cn
            m.addOnActiveSessionsChangedListener(sessionsListener, cn)
            pick(m.getActiveSessions(cn))
        } catch (e: SecurityException) {
            sink?.success(mapOf("access" to false, "active" to false))
        }
    }

    private fun detach() {
        try { manager?.removeOnActiveSessionsChangedListener(sessionsListener) } catch (_: Exception) {}
        try { controller?.unregisterCallback(callback) } catch (_: Exception) {}
        controller = null
        lastTrackKey = null
    }

    private fun pick(list: List<MediaController>?) {
        try { controller?.unregisterCallback(callback) } catch (_: Exception) {}
        val chosen = list?.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: list?.firstOrNull()
        controller = chosen
        lastTrackKey = null
        chosen?.registerCallback(callback)
        push(true)
    }

    private fun push(withMeta: Boolean) {
        val s = sink ?: return
        val c = controller
        if (c == null) {
            s.success(mapOf("access" to true, "active" to false))
            return
        }
        val md = c.metadata
        val st = c.playbackState
        val speed = st?.playbackSpeed ?: 1f
        var pos = st?.position ?: 0L
        if (pos < 0) pos = 0
        if (st != null && st.state == PlaybackState.STATE_PLAYING) {
            pos += ((SystemClock.elapsedRealtime() - st.lastPositionUpdateTime) * speed).toLong()
        }

        val title = md?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""
        val artist = md?.getString(MediaMetadata.METADATA_KEY_ARTIST)
            ?: md?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST) ?: ""
        val album = md?.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""
        val duration = md?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L

        val map = hashMapOf<String, Any>(
            "access" to true,
            "active" to true,
            "playing" to (st?.state == PlaybackState.STATE_PLAYING),
            "title" to title,
            "artist" to artist,
            "album" to album,
            "duration" to duration,
            "position" to pos,
            "speed" to speed.toDouble(),
        )

        val key = "$title|$artist|$album|$duration"
        if (md != null && (withMeta || key != lastTrackKey)) {
            extractArt(md)?.let { map["art"] = it }
        }
        lastTrackKey = key
        s.success(map)
    }

    // ----------------------------------------------------------------- art

    private fun extractArt(md: MediaMetadata): ByteArray? {
        var bmp: Bitmap? = md.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: md.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: md.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)

        if (bmp == null) {
            // Some players only provide a content:// or file:// URI.
            val uri = md.getString(MediaMetadata.METADATA_KEY_ALBUM_ART_URI)
                ?: md.getString(MediaMetadata.METADATA_KEY_ART_URI)
                ?: md.getString(MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI)
            if (uri != null && (uri.startsWith("content:") || uri.startsWith("file:"))) {
                try {
                    contentResolver.openInputStream(Uri.parse(uri))?.use {
                        bmp = BitmapFactory.decodeStream(it)
                    }
                } catch (_: Exception) {}
            }
        }

        val b = bmp ?: return null
        val max = 1024
        val scaled = if (b.width > max || b.height > max) {
            val r = max.toFloat() / maxOf(b.width, b.height)
            Bitmap.createScaledBitmap(b, (b.width * r).toInt(), (b.height * r).toInt(), true)
        } else b
        val out = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 92, out)
        return out.toByteArray()
    }

    private fun openAccessSettings() {
        try {
            startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    override fun onDestroy() {
        detach()
        super.onDestroy()
    }
}

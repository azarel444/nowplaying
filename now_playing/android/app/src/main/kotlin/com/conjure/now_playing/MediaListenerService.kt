package com.conjure.now_playing

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.service.notification.NotificationListenerService

/**
 * Android only lets an app read other apps' media sessions if it owns an
 * enabled notification listener, so this service gives MainActivity that
 * permission.
 *
 * It also lives as long as notification access is on, even when the app
 * screen is closed, which lets it open the app when music starts (if the
 * user turned that option on in settings).
 */
class MediaListenerService : NotificationListenerService() {

    private var manager: MediaSessionManager? = null
    private val watched = mutableListOf<MediaController>()
    private var lastLaunch = 0L

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { list -> attach(list) }

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) {
            if (state?.state == PlaybackState.STATE_PLAYING) maybeLaunch()
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        try {
            val m = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val cn = ComponentName(this, MediaListenerService::class.java)
            manager = m
            m.addOnActiveSessionsChangedListener(sessionsListener, cn)
            attach(m.getActiveSessions(cn))
        } catch (_: Exception) {
        }
    }

    override fun onListenerDisconnected() {
        detachAll()
        try {
            manager?.removeOnActiveSessionsChangedListener(sessionsListener)
        } catch (_: Exception) {
        }
        super.onListenerDisconnected()
    }

    private fun detachAll() {
        for (c in watched) {
            try {
                c.unregisterCallback(callback)
            } catch (_: Exception) {
            }
        }
        watched.clear()
    }

    private fun attach(list: List<MediaController>?) {
        detachAll()
        if (list == null) return
        for (c in list) {
            try {
                c.registerCallback(callback)
                watched.add(c)
            } catch (_: Exception) {
            }
        }
    }

    private fun maybeLaunch() {
        val prefs = getSharedPreferences("np_prefs", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("openOnMusic", false)) return
        if (MainActivity.visible) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastLaunch < 15000) return
        lastLaunch = now
        try {
            val i = Intent(this, MainActivity::class.java)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            startActivity(i)
        } catch (_: Exception) {
        }
    }
}

package com.conjure.now_playing

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
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
 * It also stays alive while notification access is on, even with the app
 * screen closed, so it can open VYBE when music starts. The rules:
 *
 *  - Only a real START opens VYBE: a player going from stopped or paused
 *    (for longer than the pause time in settings) to playing. Track changes,
 *    skips, buffering and short pauses never do.
 *  - Only music players, unless video or navigation audio is switched on.
 *  - Never while navigation is active, during a call, or when VYBE is
 *    already on screen.
 */
class MediaListenerService : NotificationListenerService() {

    private class Watch(val c: MediaController, val cb: MediaController.Callback)

    private var manager: MediaSessionManager? = null
    private var watches = ArrayList<Watch>()

    /** Packages that are playing right now, and when each last stopped. */
    private val playing = HashSet<String>()
    private val pausedAt = HashMap<String, Long>()
    private var lastLaunch = 0L

    private val sessionsListener =
        MediaSessionManager.OnActiveSessionsChangedListener { list -> attach(list) }

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
        for (w in watches) {
            try {
                w.c.unregisterCallback(w.cb)
            } catch (_: Exception) {
            }
        }
        watches = ArrayList()
        playing.clear()
        try {
            manager?.removeOnActiveSessionsChangedListener(sessionsListener)
        } catch (_: Exception) {
        }
        super.onListenerDisconnected()
    }

    /**
     * Called whenever the set of active sessions changes. A session that is
     * new to us is checked right away: a player that appears already playing
     * produces no state change, which used to make auto-open miss.
     */
    private fun attach(list: List<MediaController>?) {
        val now = SystemClock.elapsedRealtime()
        val keep = ArrayList<Watch>()
        val fresh = ArrayList<Watch>()
        for (c in list ?: emptyList()) {
            val existing = watches.firstOrNull { it.c.sessionToken == c.sessionToken }
            if (existing != null) {
                keep.add(existing)
                continue
            }
            val cb = object : MediaController.Callback() {
                override fun onPlaybackStateChanged(state: PlaybackState?) {
                    handleState(c, state, true)
                }
            }
            val w = Watch(c, cb)
            try {
                c.registerCallback(cb)
            } catch (_: Exception) {
                continue
            }
            keep.add(w)
            fresh.add(w)
        }
        for (old in watches) {
            if (keep.none { it.c.sessionToken == old.c.sessionToken }) {
                try {
                    old.c.unregisterCallback(old.cb)
                } catch (_: Exception) {
                }
                // The session went away: treat it as a stop.
                val pkg = old.c.packageName
                if (playing.remove(pkg)) pausedAt[pkg] = now
            }
        }
        watches = keep
        for (w in fresh) {
            remember(w.c)
            handleState(w.c, w.c.playbackState, false)
        }
    }

    private fun remember(c: MediaController) {
        try {
            val prefs = getSharedPreferences(PlayerFilter.PREFS, Context.MODE_PRIVATE)
            val kind = PlayerFilter.classify(this, c.packageName, c.metadata)
            PlayerFilter.remember(this, prefs, c.packageName, kind)
        } catch (_: Exception) {
        }
    }

    /**
     * [live] is true for a state change reported by the player, and false
     * for the first look at a session we just discovered.
     */
    private fun handleState(c: MediaController, st: PlaybackState?, live: Boolean) {
        val pkg = c.packageName
        val now = SystemClock.elapsedRealtime()
        when (st?.state ?: PlaybackState.STATE_NONE) {
            PlaybackState.STATE_PLAYING -> {
                if (playing.add(pkg)) {
                    // A just-found session only counts as a fresh start if
                    // its state was set a moment ago. Otherwise the music has
                    // been going for a while (service restarted, say).
                    val recent = live || (st != null &&
                        now - st.lastPositionUpdateTime in 0L..5000L)
                    onStart(c, recent)
                }
            }
            PlaybackState.STATE_PAUSED,
            PlaybackState.STATE_STOPPED,
            PlaybackState.STATE_NONE,
            PlaybackState.STATE_ERROR -> {
                if (playing.remove(pkg)) pausedAt[pkg] = now
            }
            else -> {
                // Buffering, connecting, skipping and so on: not a change.
            }
        }
    }

    private fun onStart(c: MediaController, recent: Boolean) {
        if (!recent) return
        val prefs = getSharedPreferences(PlayerFilter.PREFS, Context.MODE_PRIVATE)
        val pkg = c.packageName
        val now = SystemClock.elapsedRealtime()

        // A short pause followed by play is the same listening session.
        val graceMs = prefs.getInt("graceSec", 60) * 1000L
        val last = pausedAt[pkg]
        if (last != null && now - last < graceMs) return

        if (!prefs.getBoolean("openOnMusic", false)) return
        val kind = PlayerFilter.classify(this, pkg, c.metadata)
        if (!PlayerFilter.allowed(prefs, pkg, kind)) return
        if (MainActivity.visible) return
        // After the person leaves VYBE for another app, stay out of the way
        // for a while, even if a new song or album starts playing.
        val quietMs = prefs.getInt("quietMin", 10) * 60000L
        val left = MainActivity.leftAt
        if (quietMs > 0 && left > 0 && now - left < quietMs) return
        if (prefs.getBoolean("avoidNav", true) && navigationActive(prefs)) return
        if (inCall()) return
        if (now - lastLaunch < 3000) return
        lastLaunch = now
        try {
            val i = Intent(this, MainActivity::class.java)
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            startActivity(i)
        } catch (_: Exception) {
        }
    }

    /**
     * Navigation apps show an ongoing notification while guiding. This looks
     * for one in the "navigation" category, or an ongoing one from the
     * navigation app the user picked in settings.
     */
    private fun navigationActive(prefs: android.content.SharedPreferences): Boolean {
        return try {
            val navPkg = prefs.getString("navPkg", "") ?: ""
            val list = activeNotifications ?: return false
            list.any { sbn ->
                val n = sbn.notification
                val ongoing = (n.flags and Notification.FLAG_ONGOING_EVENT) != 0
                ongoing && (n.category == "navigation" ||
                    (navPkg.isNotEmpty() && sbn.packageName == navPkg))
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun inCall(): Boolean {
        return try {
            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            am.mode == AudioManager.MODE_IN_CALL ||
                am.mode == AudioManager.MODE_IN_COMMUNICATION ||
                am.mode == AudioManager.MODE_RINGTONE
        } catch (_: Exception) {
            false
        }
    }
}

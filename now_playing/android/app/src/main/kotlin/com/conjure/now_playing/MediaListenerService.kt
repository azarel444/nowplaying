package com.conjure.now_playing

import android.service.notification.NotificationListenerService

/**
 * Intentionally empty. Android only lets an app read other apps' media
 * sessions if it owns an enabled notification listener, so this service
 * exists to give MainActivity that permission.
 */
class MediaListenerService : NotificationListenerService()

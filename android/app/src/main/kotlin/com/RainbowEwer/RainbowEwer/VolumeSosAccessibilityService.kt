package com.RainbowEwer.RainbowEwer

import android.accessibilityservice.AccessibilityService
import android.os.SystemClock
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

/**
 * Volume Down ×3 with the phone locked, or with the app off screen.
 *
 * The app's own key handler (lib/core/sos/volume_sos.dart) only hears keys
 * while Plateau Eye is open and on screen. An accessibility service that asks
 * to filter key events is the one way an ordinary Android app hears them
 * otherwise. The person switches it on themselves in Android's Accessibility
 * settings, after the app has said what it does.
 *
 * WHAT IT SEES, AND WHAT IT DOES NOT. Key events only; and of those, it looks
 * at Volume Down and nothing else. It asks for no accessibility events and
 * cannot read the screen (res/xml/volume_sos_accessibility.xml: no event
 * types, canRetrieveWindowContent false). It never consumes a key: the volume
 * still goes down, as it would for anyone watching.
 *
 * It does nothing unless Volume Down ×3 is also switched on in the app's
 * Settings, and nothing while the app is on screen, where the app counts the
 * presses itself.
 */
class VolumeSosAccessibilityService : AccessibilityService() {
    private val counter = VolumePressCounter()

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_VOLUME_DOWN) return false
        // Down only, and not the repeats of a held key: a held key is not
        // three presses.
        if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return false
        if (VolumeSosBridge.appInForeground || !VolumeSosBridge.enabled(this)) {
            counter.reset()
            return false
        }
        if (counter.press(SystemClock.uptimeMillis())) {
            VolumeSosBridge.trigger(applicationContext)
        }
        return false
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}
}

package com.RainbowEwer.RainbowEwer

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/**
 * Three presses of Volume Down inside [windowMs]. The same rule as the app's
 * own detector (lib/core/sos/triple_tap.dart, sosTapWindow): three deliberate
 * presses within three seconds.
 */
class VolumePressCounter(private val windowMs: Long = 3000, private val needed: Int = 3) {
    private val presses = ArrayDeque<Long>()

    /** Records a press at [atMs]; true when it completes a set of [needed]. */
    fun press(atMs: Long): Boolean {
        while (presses.isNotEmpty() && (atMs - presses.first() > windowMs || presses.first() > atMs)) {
            presses.removeFirst()
        }
        presses.addLast(atMs)
        if (presses.size >= needed) {
            presses.clear()
            return true
        }
        return false
    }

    fun reset() = presses.clear()
}

/**
 * How a Volume Down ×3 caught by [VolumeSosAccessibilityService] reaches the
 * app's own SOS code, so there is one SOS path and not two: the same
 * EmergencyNotifier.startEmergency(silent: true), with its offline queue, SMS
 * fallback and tracking.
 *
 * - The app is running (its Flutter engine is up, on screen or not): the press
 *   is handed to Dart over [CHANNEL] at once. Nothing on screen changes.
 * - It is not: MainActivity is started with [EXTRA_VOLUME_SOS]. With the phone
 *   locked it starts behind the lock screen, where nobody sees it; unlocked,
 *   it puts itself straight back behind whatever was on screen. Dart takes the
 *   press with `takePending` once it is ready to send.
 */
object VolumeSosBridge {
    const val CHANNEL = "com.operationrainbow.app/volume_sos"
    const val EXTRA_VOLUME_SOS = "volume_sos"

    /** The Flutter shared_preferences file and the key volume_sos.dart writes. */
    private const val PREFS = "FlutterSharedPreferences"
    private const val ENABLED_KEY = "flutter.volume_sos_enabled"

    /** A press older than this when Dart asks for it is not sent. */
    const val PENDING_LIMIT_MS = 120_000L

    @Volatile var channel: MethodChannel? = null

    /**
     * True while MainActivity is resumed. Then the app's own key handler
     * (volume_sos.dart) counts the presses, and the service stays out of it,
     * so one set of presses is never counted twice.
     */
    @Volatile var appInForeground = false

    /** When a press arrived that Dart has not taken yet (elapsedRealtime), or 0. */
    @Volatile private var pendingAt = 0L

    private val main = Handler(Looper.getMainLooper())

    fun enabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(ENABLED_KEY, false)

    /** Called by the service when three presses complete. */
    fun trigger(context: Context) {
        pendingAt = SystemClock.elapsedRealtime()
        val live = channel
        if (live != null) {
            main.post {
                live.invokeMethod("trigger", null, object : MethodChannel.Result {
                    // Dart took it: nothing is pending any more.
                    override fun success(result: Any?) { pendingAt = 0L }
                    // Dart is not listening yet: it stays pending for takePending.
                    override fun error(code: String, message: String?, details: Any?) {}
                    override fun notImplemented() {}
                })
            }
            return
        }
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(EXTRA_VOLUME_SOS, true)
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            // Nothing else can carry the press. It stays pending, and is sent
            // if the app is opened within PENDING_LIMIT_MS.
        }
    }

    /**
     * Milliseconds since a press Dart has not taken, clearing it; -1 for none.
     * Dart decides from the age whether it is still worth sending.
     */
    fun takePending(): Long {
        val at = pendingAt
        pendingAt = 0L
        return if (at == 0L) -1L else SystemClock.elapsedRealtime() - at
    }

    /** Whether the person has switched the service on in Accessibility settings. */
    fun serviceEnabled(context: Context): Boolean {
        val ours = ComponentName(context, VolumeSosAccessibilityService::class.java)
        val list = Settings.Secure.getString(
            context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return list.split(':').any { ComponentName.unflattenFromString(it) == ours }
    }

    fun openSettings(context: Context) {
        context.startActivity(
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}

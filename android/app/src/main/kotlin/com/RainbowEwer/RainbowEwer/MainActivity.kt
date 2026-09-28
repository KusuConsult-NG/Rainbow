package com.RainbowEwer.RainbowEwer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PictureInPictureParams
import android.content.Context
import android.media.AudioManager
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import android.os.Build
import android.os.Bundle
import android.util.Rational
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val AUDIO_CHANNEL = "com.operationrainbow.app/audio_routing"
    private val PIP_CHANNEL = "com.operationrainbow.app/pip"
    private val SMS_CHANNEL = "com.operationrainbow.app/sms"
    private val SIM_CHANNEL = "com.operationrainbow.app/sim"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Enforce modern non-deprecated Edge-to-Edge window inset handling for Android 15+
        WindowCompat.setDecorFitsSystemWindows(window, false)
        createNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL).setMethodCallHandler { call, result ->
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            when (call.method) {
                "setSpeakerphone" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    try {
                        if (enabled) {
                            audioManager.mode = AudioManager.MODE_NORMAL
                            audioManager.isSpeakerphoneOn = true
                        } else {
                            // Stealth Earpiece (Receiver) Mode
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                            audioManager.isSpeakerphoneOn = false
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // THE ENCRYPTED SMS FALLBACK.
        //
        // One 75-character message to the HQ shortcode when the handset has
        // cell signal but no usable data. The body is already encrypted and
        // authenticated by the time it reaches here — this side does no
        // formatting and knows nothing about what it is sending, which is
        // deliberate: the plaintext must not exist on the platform side where
        // it could end up in a log.
        //
        // No delivery receipt is requested. A PendingIntent for one would have
        // to be registered against the message and the result routed back
        // across the channel, and a carrier's "delivered" tells you the SMSC
        // took it, not that HQ read it. HQ acknowledging the alert over the
        // data channel, when it returns, is the real confirmation.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSms" -> {
                    val destination = call.argument<String>("destination")
                    val body = call.argument<String>("body")
                    if (destination.isNullOrBlank() || body.isNullOrBlank()) {
                        result.error("SMS_BAD_ARGS", "destination and body are required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val manager =
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                getSystemService(SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                SmsManager.getDefault()
                            }
                        // divideMessage, not sendTextMessage, so a payload that
                        // ever outgrows one segment still arrives rather than
                        // being silently truncated. It should never outgrow it:
                        // the Dart side asserts 75 characters.
                        val parts = manager.divideMessage(body)
                        if (parts.size == 1) {
                            manager.sendTextMessage(destination, null, body, null, null)
                        } else {
                            manager.sendMultipartTextMessage(destination, null, parts, null, null)
                        }
                        result.success(parts.size)
                    } catch (e: SecurityException) {
                        // The permission was declined, or Play refused the
                        // declaration and it was never granted. The Dart side
                        // falls back to the compose sheet.
                        result.error("SMS_DENIED", e.message, null)
                    } catch (e: Exception) {
                        result.error("SMS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // IS THERE STILL A SIM IN THIS HANDSET, AND WHOSE NETWORK IS IT ON?
        //
        // The phone number is the identity in this app, and it is what the
        // encrypted SMS fallback rides on. When the SIM leaves, that channel
        // dies and nothing else notices — so HQ is told the channel is down.
        // The record is about the CHANNEL, not the person: no location is
        // attached, and the holder is told on the handset that it was sent.
        //
        // NO PERMISSION IS REQUESTED, AND NONE IS NEEDED. getSimState,
        // getSimOperator and getSimOperatorName are all open to any app. The
        // values that would identify a particular CARD rather than a network —
        // the ICCID and the IMSI — have required READ_PRIVILEGED_PHONE_STATE
        // since Android 10, which is signature-level and unavailable to us. So
        // one MTN SIM swapped for another MTN SIM cannot be seen from here.
        // That limit is stated in sim_fingerprint.dart and asserted in its
        // tests, because an operator who assumed otherwise would be wrong
        // about the commonest swap there is.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SIM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "readSim" -> {
                    try {
                        val telephony =
                            getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                        if (telephony == null) {
                            // A tablet with no telephony hardware. Not "the SIM
                            // was removed" — there was never a tray.
                            result.success(mapOf("presence" to "unavailable"))
                            return@setMethodCallHandler
                        }

                        val presence = when (telephony.simState) {
                            TelephonyManager.SIM_STATE_ABSENT -> "absent"
                            TelephonyManager.SIM_STATE_READY -> "present"
                            // PIN_REQUIRED, PUK_REQUIRED, NETWORK_LOCKED and
                            // CARD_IO_ERROR all mean a card IS in the tray, so
                            // reporting them as absent would raise a removal
                            // alert for a phone that has merely been rebooted
                            // and not yet unlocked.
                            TelephonyManager.SIM_STATE_PIN_REQUIRED,
                            TelephonyManager.SIM_STATE_PUK_REQUIRED,
                            TelephonyManager.SIM_STATE_NETWORK_LOCKED -> "present"
                            else -> "unavailable"
                        }

                        // Empty strings are what this returns with no service,
                        // and an empty operator must not read as a change of
                        // network. Normalised to null here so the Dart side
                        // sees one shape.
                        val code = telephony.simOperator?.takeIf { it.isNotBlank() }
                        val name = telephony.simOperatorName?.takeIf { it.isNotBlank() }

                        result.success(
                            mapOf(
                                "presence" to presence,
                                "operator_code" to code,
                                "operator_name" to name
                            )
                        )
                    } catch (e: SecurityException) {
                        result.success(mapOf("presence" to "unavailable"))
                    } catch (e: Exception) {
                        // Any failure is "cannot see", never "it has gone".
                        result.success(mapOf("presence" to "unavailable"))
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPictureInPicture" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                            enterPictureInPictureMode(params)
                            result.success(true)
                        } else {
                            result.error("PIP_NOT_SUPPORTED", "PiP requires Android 8.0+", null)
                        }
                    } catch (e: Exception) {
                        result.error("PIP_ERROR", e.message, null)
                    }
                }
                "isPictureInPictureSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    result.success(supported)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "rainbow_tracking",
                "Operation Rainbow Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Tactical Location & SOS Emergency Tracking"
                setShowBadge(false)
            }
            val notificationManager: NotificationManager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
}

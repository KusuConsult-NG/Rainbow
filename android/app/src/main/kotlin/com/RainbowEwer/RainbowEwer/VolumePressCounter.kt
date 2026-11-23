package com.RainbowEwer.RainbowEwer

/**
 * Three presses of Volume Down inside [windowMs]. The same rule as the app's
 * own detector (lib/core/sos/triple_tap.dart, sosTapWindow): three deliberate
 * presses within three seconds.
 *
 * IN ITS OWN FILE, AND IT IMPORTS NOTHING. It used to sit at the top of
 * VolumeSosBridge.kt, which imports android.* and io.flutter.*, so it could
 * only be compiled with the whole Android toolchain — and this repository has
 * no Android unit tests at all, no gradle wrapper and no SDK in CI. The rule
 * that decides whether a silent SOS goes out from a locked phone was therefore
 * asserted by nothing, in either language.
 *
 * Plain Kotlin with no imports compiles and runs with kotlinc alone. See
 * VolumePressCounterTest.kt and scripts/check_the_two_sos_tap_rules_agree.py,
 * which pins these defaults to the Dart ones.
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

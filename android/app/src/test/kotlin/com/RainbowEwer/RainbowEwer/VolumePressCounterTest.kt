package com.RainbowEwer.RainbowEwer

/**
 * The rule that decides whether a locked phone sends a silent SOS.
 *
 * WHY THIS EXISTS, AND WHY IT IS A main() AND NOT JUnit. This repository has
 * no Android unit tests, no gradle wrapper and no Android SDK in CI, so the
 * Kotlin half of Volume Down ×3 was asserted by nothing: it was read and
 * believed. The Dart half (lib/core/sos/triple_tap.dart) is well tested, and
 * the two are separate implementations of one rule.
 *
 * VolumePressCounter imports nothing, so this needs only kotlinc and a JVM —
 * no SDK, no Gradle, no emulator:
 *
 *   kotlinc VolumePressCounter.kt VolumePressCounterTest.kt -include-runtime \
 *     -d t.jar && java -jar t.jar
 *
 * scripts/check_the_two_sos_tap_rules_agree.py runs exactly that, and also
 * pins these defaults to the Dart ones so the two cannot drift apart.
 */

private var failures = 0

private fun check(name: String, pass: Boolean, detail: String = "") {
    if (pass) {
        println("PASS  $name")
    } else {
        failures++
        println("FAIL  $name${if (detail.isEmpty()) "" else "  — $detail"}")
    }
}

fun main() {
    // Three deliberate presses inside three seconds. One or two are somebody
    // turning the volume down, and must send nothing: a responder sent to a
    // pocket is a responder not sent to an emergency.
    run {
        val c = VolumePressCounter()
        check("one press sends nothing", !c.press(0L))
        check("two presses send nothing", !c.press(500L))
        check("the third press inside the window sends", c.press(1000L))
    }

    // Spread out, they are ordinary volume presses.
    run {
        val c = VolumePressCounter()
        c.press(0L)
        c.press(2000L)
        check("three presses spread over more than the window send nothing",
            !c.press(4500L), "0ms, 2000ms, 4500ms")
    }

    // The window is a sliding one: the first press ages out, and the later
    // three still count.
    run {
        val c = VolumePressCounter()
        c.press(0L)
        c.press(4000L)
        c.press(4500L)
        check("a stale press ages out and the next three still send",
            c.press(5000L), "4000/4500/5000 are within 3000ms")
    }

    // Exactly on the boundary is inside it: `> windowMs` drops, so 3000ms
    // apart still counts. Pinned because a later `>=` would silently make the
    // control harder to use for somebody with unsteady hands.
    run {
        val c = VolumePressCounter()
        c.press(0L)
        c.press(1500L)
        check("a press exactly windowMs after the first still counts",
            c.press(3000L))
    }

    // It must not fire twice off one set. The service hands every press over,
    // and a fourth press straight after a send would raise a second SOS.
    run {
        val c = VolumePressCounter()
        c.press(0L)
        c.press(100L)
        check("the set sends", c.press(200L))
        check("a fourth press does not send again", !c.press(300L))
        check("and the next set still needs three", !c.press(400L))
        check("...three", c.press(500L))
    }

    // SystemClock.elapsedRealtime() should not go backwards, but the counter
    // guards against it (`presses.first() > atMs`). If it did and nothing
    // cleared, the deque would hold timestamps that never age out and the
    // control would wedge — silently, on a locked phone.
    run {
        val c = VolumePressCounter()
        c.press(10_000L)
        c.press(10_100L)
        check("a clock that jumps backwards clears the stale presses",
            !c.press(5L), "two presses at 10s, then one at 5ms")
        check("and the control still works afterwards", !c.press(100L))
        check("...still works", c.press(200L))
    }

    run {
        val c = VolumePressCounter()
        c.press(0L)
        c.press(100L)
        c.reset()
        check("reset clears the count", !c.press(200L))
    }

    // Not the shipped rule, but the class takes both, and a caller passing
    // something else must get what it asked for.
    run {
        val c = VolumePressCounter(windowMs = 1000L, needed = 2)
        check("a different rule is honoured", c.press(0L).not() && c.press(500L))
    }

    println()
    if (failures > 0) {
        println("$failures check(s) failed.")
        kotlin.system.exitProcess(1)
    }
    println("OK: the locked-phone tap rule behaves as the Dart one does.")
}

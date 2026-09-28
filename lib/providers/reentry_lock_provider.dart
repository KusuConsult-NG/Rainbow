/// Holds whether the app is locked, and watches the lifecycle that locks it.
///
/// The decision itself is in `lib/core/auth/reentry_lock.dart` and is a pure
/// function, tested there. This is the part that cannot be: a clock, an
/// observer on the Flutter binding, and one bit of state the router reads.
///
/// Two details that are easy to get wrong and expensive to get wrong here:
///
/// **The clock is wall time, not a timer.** A timer does not run while the
/// process is suspended, and on iOS it may not run at all. The time away is
/// measured by writing a timestamp when the app leaves and subtracting it when
/// it comes back, so a phone that was in a pocket for an hour is treated as an
/// hour away even though nothing in this process was executing.
///
/// **`paused` is the signal, not `inactive`.** `inactive` fires for a
/// notification shade pull, a permission dialog, a phone call arriving — none
/// of which is leaving the app, all of which would otherwise start the clock.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/auth/reentry_lock.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';

/// Whether anyone is signed in.
///
/// A one-line view of `authProvider`, and the seam the lock is tested through:
/// `AuthNotifier`'s constructor calls `initAuth()`, which reaches Supabase, so
/// a test cannot simply substitute one. Deriving the question the lock actually
/// asks — rather than reading the whole auth state — keeps the production
/// wiring honest and the test small.
final hasSessionProvider = Provider<bool>(
  (ref) => ref.watch(authProvider).user != null,
);

/// Whether an SOS is running. A live emergency is never locked.
final emergencyActiveProvider = Provider<bool>(
  (ref) => ref.watch(emergencyProvider).isEmergencyActive,
);

/// Whether the app is currently locked behind a re-entry code.
final reentryLockProvider =
    NotifierProvider<ReentryLockNotifier, bool>(ReentryLockNotifier.new);

/// Owns the lock bit and the lifecycle observer that sets it.
class ReentryLockNotifier extends Notifier<bool> with WidgetsBindingObserver {
  /// When the app last left the foreground, or null if it has not.
  DateTime? _leftAt;

  /// Injected so tests do not have to wait two minutes.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  bool _observing = false;

  @override
  bool build() {
    // The observer is attached lazily and removed when the provider goes, so a
    // hot restart does not leave two of them counting the same transitions.
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      ref.onDispose(() {
        WidgetsBinding.instance.removeObserver(this);
        _observing = false;
      });
    }
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Only the FIRST departure counts. `paused` can arrive more than once
        // without an intervening `resumed` on some platforms, and taking the
        // last one would reset the clock and hold the app open indefinitely.
        _leftAt ??= clock();
      case AppLifecycleState.resumed:
        _evaluateOnResume();
      case AppLifecycleState.inactive:
        // A notification shade, a permission dialog, an incoming call. Not
        // leaving the app.
        break;
    }
  }

  void _evaluateOnResume() {
    final leftAt = _leftAt;
    _leftAt = null;
    if (leftAt == null) return;

    // Read the two conditions at the moment of the decision rather than
    // holding copies of them. Copies drift: an SOS that starts while the app
    // is in the background would otherwise be invisible to this, and locking
    // someone out of a running alarm is the one outcome this must never have.
    final away = clock().difference(leftAt);
    if (shouldLockOnResume(
      awayFor: away,
      hasSession: ref.read(hasSessionProvider),
      emergencyActive: ref.read(emergencyActiveProvider),
    )) {
      state = true;
    }
  }

  /// Lift the lock. Called only after a code has actually been verified.
  void unlock() {
    _leftAt = null;
    state = false;
  }

  /// Lock now, without waiting for a lifecycle transition.
  ///
  /// For the case where somebody hands the phone over deliberately.
  void lockNow() => state = true;

  /// Test seam: pretend the app left the foreground and came back.
  @visibleForTesting
  void simulateAway(Duration away) {
    _leftAt = clock().subtract(away);
    _evaluateOnResume();
  }
}

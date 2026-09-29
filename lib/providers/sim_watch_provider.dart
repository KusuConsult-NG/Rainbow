/// Runs the SIM check at the moments it can catch something, and holds the one
/// line the holder is owed when it does.
///
/// Separate from the re-entry lock even though both watch the lifecycle: they
/// answer different questions, fail differently, and one is allowed to be
/// unavailable while the other is not. Sharing an observer would couple the
/// lock — which decides whether a person can use their emergency app — to a
/// platform call that is best-effort by design.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/services/sim_watch_service.dart';

/// The notice waiting to be shown to the holder, or null when there is none.
///
/// Null is the overwhelmingly common state. It becomes a sentence exactly once
/// per change, and the screen that shows it calls [SimWatchNotifier.seen].
final simNoticeProvider =
    NotifierProvider<SimWatchNotifier, String?>(SimWatchNotifier.new);

/// Checks the SIM on resume and after sign-in.
class SimWatchNotifier extends Notifier<String?> with WidgetsBindingObserver {
  /// Swapped in tests.
  @visibleForTesting
  SimWatchService service = SimWatchService();

  bool _observing = false;

  @override
  String? build() {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      ref.onDispose(() {
        WidgetsBinding.instance.removeObserver(this);
        _observing = false;
      });
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Resume is the moment that catches the case a broadcast receiver
      // cannot: the SIM taken out while the app was closed.
      unawaitedCheck();
    }
  }

  /// Runs a check. Never throws, never blocks anything.
  void unawaitedCheck() {
    unawaited(
      service.check().then((outcome) {
        final notice = outcome.noticeForUser;
        if (notice.isEmpty) return;
        state = notice;
      }).catchError((Object e) {
        // The service already swallows its own failures; this is the belt for
        // anything that gets past it. A SIM check must never take down a
        // screen.
        debugPrint('[SIM] check failed: $e');
      }),
    );
  }

  /// The holder has been shown the notice.
  void seen() => state = null;

  /// Forget the baseline — on sign-out, so the next person to use this handset
  /// is not compared against somebody else's SIM.
  Future<void> forget() async {
    state = null;
    await service.forget();
  }
}

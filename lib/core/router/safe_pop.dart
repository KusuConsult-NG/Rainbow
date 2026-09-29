/// Going back from a screen that may have nothing behind it.
///
/// ## The defect
///
/// `context.pop()` THROWS in go_router when the navigation stack has only one
/// entry. Four screens called it bare — the Close buttons on the report screens,
/// and the returns after saving a mission debrief and an emergency PIN.
///
/// The browser sweep caught it as an uncaught error on /report-initial, and the
/// source map put it beyond argument:
///
///     go_router-14.8.1/lib/src/delegate.dart:101  GoRouterDelegate.pop
///     flutter/lib/src/material/ink_well.dart:1224 _InkResponseState.handleTap
///
/// It is not only a harness artifact. The sweep reaches a screen directly by
/// URL, and so does a real person: a push notification that opens an incident,
/// a deep link, or a cold start restored onto a route. In each of those the
/// stack is empty, and the back arrow throws instead of going back.
///
/// The two post-action calls are worse than the Close buttons. The debrief and
/// the PIN have already been SAVED by the time the pop runs, so the throw
/// leaves somebody looking at a form that appears to have failed, after work
/// the database has already accepted.
///
/// `RainbowAppBar` already guarded this correctly. Four screens did not, so the
/// rule lives here now rather than being remembered four more times.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// What going back should do.
enum BackAction {
  /// There is a screen behind this one.
  pop,

  /// There is not; go somewhere sensible instead of throwing.
  goFallback,
}

/// Which of the two applies.
///
/// Separated from the navigation so the decision can be tested without a
/// widget tree — the whole bug was that one branch of it did not exist.
BackAction backActionFor({required bool canPop}) =>
    canPop ? BackAction.pop : BackAction.goFallback;

/// Going back, safely.
extension SafePop on BuildContext {
  /// Pops if there is anything to pop, and otherwise goes to [fallback].
  ///
  /// [fallback] should be the screen the person would have come from, so that
  /// arriving by deep link behaves like arriving by navigation.
  void popOrGo(String fallback) {
    switch (backActionFor(canPop: canPop())) {
      case BackAction.pop:
        pop();
      case BackAction.goFallback:
        go(fallback);
    }
  }
}

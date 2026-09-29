// Going back from a screen that may have nothing behind it.
//
// `context.pop()` throws in go_router when the stack has one entry, and four
// screens called it bare. The browser sweep caught it as an uncaught error on
// /report-initial and the source map named the frame:
//
//   go_router-14.8.1/lib/src/delegate.dart:101  GoRouterDelegate.pop
//   flutter/lib/src/material/ink_well.dart:1224 _InkResponseState.handleTap
//
// The decision is tested here rather than the navigation, because the bug was
// that one branch of the decision did not exist at all.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/router/safe_pop.dart';

void main() {
  group('going back', () {
    test('pops when there is a screen behind this one', () {
      expect(backActionFor(canPop: true), BackAction.pop);
    });

    test('goes to the fallback when there is not, rather than throwing', () {
      // The case that did not exist. A person reaches a screen with an empty
      // stack by push notification, deep link, or a cold start restored onto a
      // route — and the back arrow threw instead of going back.
      expect(backActionFor(canPop: false), BackAction.goFallback);
    });

    test('has no third outcome', () {
      // Whatever the state, going back does SOMETHING. The defect was a branch
      // that fell through to an exception.
      for (final canPop in [true, false]) {
        expect(BackAction.values, contains(backActionFor(canPop: canPop)));
      }
    });
  });
}

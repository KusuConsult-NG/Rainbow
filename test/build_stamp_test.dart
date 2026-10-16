// The sign-in screen has to be able to say which build it is.
//
// Three times in one week a fix was reported as not working from a handset
// running the build from before the fix, and neither end could tell. The
// stamp is the cheapest possible answer to "which APK is this?", so the one
// thing it must never do is lie — including by rendering a stale or made-up
// version when the platform will not say.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/shared/widgets/build_stamp.dart';

void main() {
  Future<void> pump(WidgetTester tester, Future<String?> Function() resolve) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: BuildStamp(resolve: resolve))),
      ));

  testWidgets('shows the version and build number it was given',
      (tester) async {
    await pump(tester, () async => 'v1.0.8 (29)');
    await tester.pumpAndSettle();
    expect(find.text('v1.0.8 (29)'), findsOneWidget);
  });

  testWidgets('shows nothing at all when the platform throws', (tester) async {
    // This is the case every widget test in this repository hits:
    // `PackageInfo.fromPlatform()` needs a registered plugin and throws
    // MissingPluginException without one. The screen under test must be
    // unaffected — no exception, no placeholder, nothing.
    await pump(tester, () async => throw MissingPluginException('no plugin'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('shows nothing when the platform answers with nothing',
      (tester) async {
    await pump(tester, () async => null);
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('does not paint before the answer arrives', (tester) async {
    // A stamp that flashes a wrong value and corrects itself is worse than
    // no stamp: somebody reads it out in the half-second it is wrong.
    final gate = Completer<String?>();
    await pump(tester, () => gate.future);
    await tester.pump();
    expect(find.byType(Text), findsNothing);
    gate.complete('v1.0.8 (29)');
    await tester.pumpAndSettle();
    expect(find.text('v1.0.8 (29)'), findsOneWidget);
  });
}

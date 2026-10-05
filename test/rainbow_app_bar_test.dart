// The app bar's leading button must do something, and say what.
//
// The control sweep found the responder's live-tracking map with a menu button
// that did nothing: there was no drawer anywhere above it to open. And neither
// leading button had an accessible name.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

void main() {
  testWidgets('with a drawer above it, the button is a named menu that opens it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: const Drawer(child: Text('DRAWER CONTENT')),
          body: Scaffold(
            appBar: const RainbowAppBar(title: 'SCREEN'),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Open menu'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(find.text('DRAWER CONTENT'), findsOneWidget);
  });

  testWidgets('with no drawer anywhere, it is a named Back button, not a dead menu',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: RainbowAppBar(title: 'TACTICAL MAP'),
          body: SizedBox.shrink(),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.byIcon(Icons.menu_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
  });

  testWidgets('showBack still forces Back even when a drawer exists', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: const Drawer(),
          body: Scaffold(
            appBar: const RainbowAppBar(title: 'SUBTYPE', showBack: true),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    expect(find.bySemanticsLabel('Open menu'), findsNothing);
  });

  // The first version of the fix labelled both buttons with excludeSemantics
  // and no onTap, which threw away the detector's tap action: a screen reader
  // could name them and never press them, and the mobile control sweep found
  // "Open menu" and "Back" doing nothing on every screen. Pressed here through
  // semantics, the way assistive technology and the sweep press them.
  testWidgets('both buttons can be pressed through the accessibility tree',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: const Drawer(child: Text('DRAWER CONTENT')),
          body: Scaffold(
            appBar: const RainbowAppBar(title: 'SCREEN'),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('DRAWER CONTENT'), findsOneWidget);

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('FIRST'))),
        GoRoute(
          path: '/second',
          builder: (_, __) => const Scaffold(
            appBar: RainbowAppBar(title: 'SECOND'),
            body: SizedBox.shrink(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    unawaited(router.push('/second'));
    await tester.pumpAndSettle();
    tester.semantics.tap(find.semantics.byLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.text('FIRST'), findsOneWidget);
    handle.dispose();
  });
}

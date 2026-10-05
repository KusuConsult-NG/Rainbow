// The app bar's leading button must do something, and say what.
//
// The control sweep found the responder's live-tracking map with a menu button
// that did nothing: there was no drawer anywhere above it to open. And neither
// leading button had an accessible name.
import 'package:flutter/material.dart';
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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/app.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: RainbowApp()));
    expect(find.byType(MaterialApp), findsOneWidget);
  }, skip: true);
}

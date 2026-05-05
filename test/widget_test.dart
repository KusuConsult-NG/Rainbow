import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RainbowApp());
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

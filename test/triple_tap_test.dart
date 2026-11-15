import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/sos/triple_tap.dart';

void main() {
  final t0 = DateTime(2026, 11, 13, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('one or two taps never fire', () {
    final d = TripleTapDetector();
    expect(d.tap(at(0)), isFalse);
    expect(d.tap(at(400)), isFalse);
    expect(d.count, 2);
  });

  test('the third tap inside the window fires, once', () {
    final d = TripleTapDetector();
    d..tap(at(0))..tap(at(500));
    expect(d.tap(at(1000)), isTrue);
    expect(d.count, 0, reason: 'a fourth tap must start a new sequence');
    expect(d.tap(at(1200)), isFalse);
    expect(d.tap(at(1400)), isFalse);
  });

  test('three taps spread over more than the window do not fire', () {
    final d = TripleTapDetector();
    d..tap(at(0))..tap(at(2000));
    expect(d.tap(at(3500)), isFalse,
        reason: 'the first tap is 3.5s old; only two are inside 3s');
    expect(d.tap(at(4000)), isTrue,
        reason: 'taps at 2.0s, 3.5s and 4.0s are inside one window');
  });

  test('a tap exactly at the edge of the window still counts', () {
    final d = TripleTapDetector();
    d..tap(at(0))..tap(at(1500));
    expect(d.tap(at(3000)), isTrue);
  });

  test('reset forgets the taps so far', () {
    final d = TripleTapDetector()..tap(at(0))..tap(at(100));
    d.reset();
    expect(d.tap(at(200)), isFalse);
  });
}

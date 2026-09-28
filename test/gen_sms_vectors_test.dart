// Not a test: a generator, run as one because `flutter test` is the only way
// to execute Dart with this project's dependencies resolved.
//
// It writes the vectors that `hq-dashboard-next` decodes, so the two
// independent implementations of the wire format are proven to agree on real
// bytes rather than on two readings of the same prose.
//
//   flutter test test/gen_sms_vectors_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';

void main() {
  test('write the cross-implementation vectors', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i * 7 % 256));
    final deviceRef = Uint8List.fromList([0xA1, 0xB2, 0xC3, 0xD4]);
    final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i));
    final localRef = Uint8List.fromList([1, 2, 3, 4, 5, 6]);
    final at = DateTime.utc(2026, 9, 28, 14, 30, 5);

    final cases = <String, SmsAlertPayload>{
      'ordinary': SmsAlertPayload(
          categoryCode: 9, severityCode: 3, sentAt: at, localRef: localRef,
          latitude: 9.89654, longitude: 8.85831),
      'duress': SmsAlertPayload(
          categoryCode: 255, severityCode: 3, sentAt: at, localRef: localRef,
          latitude: 9.89654, longitude: 8.85831, isDuress: true),
      'noFix': SmsAlertPayload(
          categoryCode: 0, severityCode: 2, sentAt: at, localRef: localRef),
      'anonymous': SmsAlertPayload(
          categoryCode: 7, severityCode: 1, sentAt: at, localRef: localRef,
          latitude: -1.5, longitude: 30.25, isAnonymous: true),
    };

    final blob = {
      'generatedBy': 'test/gen_sms_vectors_test.dart',
      'keyBase64': base64Encode(key),
      'deviceRefHex': deviceRef
          .map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'sentAtIso': at.toIso8601String(),
      'localRefHex': localRef
          .map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'cases': {
        for (final e in cases.entries)
          e.key: encodeSmsAlert(
              payload: e.value, key: key, deviceRef: deviceRef, nonce: nonce),
      },
    };

    File('test/fixtures/sms_alert_vectors.json')
        .writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(blob)}\n');
    expect(blob['cases'], isNotEmpty);
  });
}

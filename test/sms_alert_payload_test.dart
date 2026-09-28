// An alert that fits in one text message, and cannot be read on the way.
//
// The design first assumed the 160-character limit forced a choice between
// carrying the duress flag and keeping it private. It does not: the whole
// alert, encrypted and authenticated, is 75 characters. These tests pin that,
// because it is the number that decides both the privacy and the bill.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';

void main() {
  final key = Uint8List.fromList(List<int>.generate(32, (i) => i * 7 % 256));
  final otherKey = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
  final deviceRef = Uint8List.fromList([0xA1, 0xB2, 0xC3, 0xD4]);
  final nonce = Uint8List.fromList(List<int>.generate(12, (i) => i));
  final localRef = Uint8List.fromList([1, 2, 3, 4, 5, 6]);

  SmsAlertPayload sample({
    bool duress = false,
    bool anonymous = false,
    double? lat = 9.89654,
    double? lng = 8.85831,
  }) =>
      SmsAlertPayload(
        categoryCode: 9, // Community attack
        severityCode: 3, // critical
        sentAt: DateTime.utc(2026, 9, 28, 14, 30, 5),
        localRef: localRef,
        latitude: lat,
        longitude: lng,
        isDuress: duress,
        isAnonymous: anonymous,
      );

  String encode(SmsAlertPayload p) =>
      encodeSmsAlert(payload: p, key: key, deviceRef: deviceRef, nonce: nonce);

  group('it fits in one message', () {
    test('a full alert is one GSM-7 segment, with room to spare', () {
      final body = encode(sample());
      expect(body.length, lessThanOrEqualTo(160));
      expect(smsSegmentsFor(body), 1);
      // The specific number, so a change to the payload that doubles the bill
      // cannot pass unnoticed.
      expect(body.length, 75);
    });

    test('a duress alert costs exactly the same as an ordinary one', () {
      // If duress were more expensive it would be distinguishable by size
      // alone, which would defeat encrypting it.
      expect(encode(sample(duress: true)).length,
          encode(sample()).length);
    });

    test('an alert with no GPS fix is the same size too', () {
      expect(encode(sample(lat: null, lng: null)).length,
          encode(sample()).length);
    });

    test('every character survives GSM-7, so it is never promoted to UCS-2', () {
      // UCS-2 would cut the segment to 70 characters and the message would
      // split in two. base64url is chosen for exactly this reason.
      final body = encode(sample());
      final gsm7 = RegExp(r'^[A-Za-z0-9_\-]+$');
      expect(gsm7.hasMatch(body.substring(smsAlertPrefix.length)), isTrue);
    });

    test('it is recognisable in a message log without being readable', () {
      expect(encode(sample()).startsWith('OR1'), isTrue);
    });
  });

  group('it round-trips', () {
    test('an ordinary alert comes back intact', () {
      final result = decodeSmsAlert(body: encode(sample()), key: key);
      expect(result.ok, isTrue);
      final p = result.payload!;
      expect(p.categoryCode, 9);
      expect(p.severityCode, 3);
      expect(p.isDuress, isFalse);
      expect(p.localRef, localRef);
      expect(result.deviceRef, deviceRef);
    });

    test('the coordinates survive to about a metre', () {
      final p = decodeSmsAlert(body: encode(sample()), key: key).payload!;
      expect(p.latitude, closeTo(9.89654, 0.00001));
      expect(p.longitude, closeTo(8.85831, 0.00001));
    });

    test('WHEN THE PHONE RAISED IT survives, not when the SMS arrived', () {
      // An SMS can sit in a carrier queue for minutes. A dispatcher looking at
      // a five-minute-old kidnapping needs to know it is five minutes old.
      final p = decodeSmsAlert(body: encode(sample()), key: key).payload!;
      expect(p.sentAt, DateTime.utc(2026, 9, 28, 14, 30, 5));
    });

    test('no fix comes back as no fix, not as the Atlantic', () {
      // Null island is a real bug in this system's history: an SOS with no GPS
      // was reported at a fabricated location. Absent must stay absent.
      final p = decodeSmsAlert(
        body: encode(sample(lat: null, lng: null)), key: key).payload!;
      expect(p.hasLocation, isFalse);
      expect(p.latitude, isNull);
      expect(p.longitude, isNull);
    });

    test('the duress flag survives — which is the point of carrying it', () {
      final p = decodeSmsAlert(body: encode(sample(duress: true)), key: key)
          .payload!;
      expect(
        p.isDuress,
        isTrue,
        reason: 'a duress SOS that degrades to an ordinary one when it travels '
            'by SMS does not work in the one case it exists for',
      );
    });

    test('anonymity survives', () {
      final p = decodeSmsAlert(body: encode(sample(anonymous: true)), key: key)
          .payload!;
      expect(p.isAnonymous, isTrue);
    });
  });

  group('it cannot be read or forged by anybody else', () {
    test('the word DURESS never appears on the wire', () {
      final body = encode(sample(duress: true));
      expect(body.toUpperCase(), isNot(contains('DURESS')));
      expect(body.toUpperCase(), isNot(contains('SOS')));
    });

    test('the coordinates are not legible in the body', () {
      // The plaintext design would have put "9.89654,8.85831" in a message log
      // that anyone holding the handset can read.
      final body = encode(sample());
      expect(body, isNot(contains('9.89')));
      expect(body, isNot(contains('8.85')));
    });

    test('two identical alerts do not produce identical messages', () {
      // Same payload, different nonce. Without this, an observer learns that
      // the same thing was reported twice.
      final a = encodeSmsAlert(
        payload: sample(), key: key, deviceRef: deviceRef,
        nonce: Uint8List.fromList(List<int>.generate(12, (i) => i)));
      final b = encodeSmsAlert(
        payload: sample(), key: key, deviceRef: deviceRef,
        nonce: Uint8List.fromList(List<int>.generate(12, (i) => i + 99)));
      expect(a, isNot(b));
    });

    test('the wrong key does not open it', () {
      final r = decodeSmsAlert(body: encode(sample()), key: otherKey);
      expect(r.ok, isFalse);
    });

    test('a tampered message does not open — HQ cannot be fed a forgery', () {
      // The endpoint this replaces accepted anything that reached it.
      final body = encode(sample());
      final broken = '${body.substring(0, body.length - 2)}AA';
      expect(decodeSmsAlert(body: broken, key: key).ok, isFalse);
    });

    test('flipping a bit in the ciphertext is detected, not silently read', () {
      final body = encode(sample());
      final raw = base64Url.decode(
        body.substring(3).padRight(body.length - 3 +
            ((4 - (body.length - 3) % 4) % 4), '='));
      raw[20] ^= 0x01;
      final tampered = 'OR1${base64Url.encode(raw).replaceAll('=', '')}';
      expect(decodeSmsAlert(body: tampered, key: key).ok, isFalse);
    });

    test('every failure looks the same, so the endpoint is not an oracle', () {
      final wrongKey = decodeSmsAlert(body: encode(sample()), key: otherKey);
      final garbage = decodeSmsAlert(body: 'OR1notbase64!!', key: key);
      final notOurs = decodeSmsAlert(body: 'hello mum', key: key);
      final truncated = decodeSmsAlert(body: 'OR1AAAA', key: key);
      for (final r in [wrongKey, garbage, notOurs, truncated]) {
        expect(r.ok, isFalse);
        expect(r.failure, 'undecodable');
      }
    });
  });

  group('it refuses to build something malformed', () {
    test('a key of the wrong length is rejected at the call site', () {
      expect(
        () => encodeSmsAlert(
          payload: sample(), key: Uint8List(16),
          deviceRef: deviceRef, nonce: nonce),
        throwsArgumentError,
      );
    });

    test('a nonce of the wrong length is rejected', () {
      expect(
        () => encodeSmsAlert(
          payload: sample(), key: key,
          deviceRef: deviceRef, nonce: Uint8List(8)),
        throwsArgumentError,
      );
    });

    test('a local ref of the wrong length is rejected', () {
      expect(
        () => encodeSmsAlert(
          payload: SmsAlertPayload(
            categoryCode: 1, severityCode: 1,
            sentAt: DateTime.utc(2026), localRef: Uint8List(3)),
          key: key, deviceRef: deviceRef, nonce: nonce),
        throwsArgumentError,
      );
    });
  });
}

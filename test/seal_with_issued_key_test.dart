// Not a test: the handset half of scripts/verify_sms_end_to_end.sh.
//
// It seals one alert with a key supplied in the environment — the key a real
// PostgreSQL just issued through `register_sms_device()` — and prints the message
// body. The point is that the key is NOT invented here: every other test in this
// repository seals with material it made up, so nothing had ever checked that a
// key the database issues, rendered the way PostgREST renders BYTEA, opens a
// message the app sealed.
//
// Run through the harness, which supplies SMS_KEY_HEX and SMS_REF_HEX:
//
//   sudo ./scripts/verify_sms_end_to_end.sh
//
// Without those variables it does nothing, so an ordinary `flutter test` run
// neither fails nor prints key material into a log.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/offline/sms_alert_payload.dart';

Uint8List _fromHex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  test('seal an alert with the key the database issued', () {
    final keyHex = Platform.environment['SMS_KEY_HEX'];
    final refHex = Platform.environment['SMS_REF_HEX'];
    if (keyHex == null || refHex == null) {
      // Deliberately a pass: this file sits in the normal test run and must
      // neither fail it nor print anything into it.
      expect(true, isTrue);
      return;
    }

    final body = encodeSmsAlert(
      payload: SmsAlertPayload(
        categoryCode: 0, // Kidnap — index 0 of alertCategories
        severityCode: 3, // CRITICAL
        sentAt: DateTime.utc(2026, 9, 28, 16, 45),
        localRef: _fromHex('aabbccddeeff'),
        latitude: 9.89654,
        longitude: 8.85831,
        // The flag the whole channel exists to carry, and the one a plaintext
        // SMS could not carry safely.
        isDuress: true,
      ),
      key: _fromHex(keyHex),
      deviceRef: _fromHex(refHex),
      // A real nonce, from the platform CSPRNG, not a counter written here.
      nonce: newSmsNonce(),
    );

    expect(body.length, 75, reason: 'one GSM-7 segment, with room to spare');
    stdout.writeln(body);
  });
}

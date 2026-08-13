// Regression tests for configuration handling.
//
// dotenv is deliberately NOT initialised here, which is exactly the state the app
// lands in when `.env` is missing or `dotenv.load()` times out — both of which
// main.dart swallows with a warning.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/config/app_config.dart';

void main() {
  group('AppConfig with no .env loaded', () {
    // REGRESSION: emergency_provider.dart used to read
    //   dotenv.env['DURESS_PIN'] ?? '9999'
    // so a misconfigured build shipped a duress code that is published in this
    // repository. A captor who had read the source would know 9999 signals
    // distress — worse than having no duress feature at all.
    test('REGRESSION: safety-critical PINs never fall back to a constant', () {
      expect(AppConfig.safePin, isNull);
      expect(AppConfig.duressPin, isNull);
      expect(AppConfig.hasEmergencyPins, isFalse);
    });

    test('REGRESSION: HMAC secret never falls back to a constant', () {
      expect(AppConfig.hmacSecret, isNull);
    });

    test('missing required keys are reported, not hidden', () {
      expect(
        AppConfig.missingRequiredKeys(),
        containsAll<String>(['SAFE_PIN', 'DURESS_PIN', 'HMAC_SECRET']),
      );
    });

    test('pin pad falls back to a sane length when unconfigured', () {
      expect(AppConfig.pinEntryLength, 4);
    });

    test('non-safety-critical defaults are still allowed', () {
      expect(AppConfig.sosPhone, isNotEmpty);
    });
  });
}

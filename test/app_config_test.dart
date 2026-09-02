// Regression tests for configuration handling.
//
// dotenv is deliberately NOT initialised here, which is exactly the state the app
// lands in when `.env` is missing or `dotenv.load()` times out — both of which
// main.dart swallows with a warning.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/config/app_config.dart';

void main() {
  group('AppConfig with no .env loaded', () {
    // The emergency PINs used to be build-time constants in `.env` — a Flutter
    // asset, shipped verbatim in every APK — so every install shared one duress
    // code that anyone who unzipped the app could read. They are per-user and
    // server-verified now. If either name ever comes back into requiredKeys, a
    // safety-critical secret has been put back inside the binary.
    test('REGRESSION: no emergency PIN is ever read from the bundle', () {
      expect(AppConfig.requiredKeys, isNot(contains('SAFE_PIN')));
      expect(AppConfig.requiredKeys, isNot(contains('DURESS_PIN')));
    });

    // H-3: the SMS credential moved to the backend, so nothing should be asking
    // the handset for it. If TERMII_API_KEY or HMAC_SECRET ever reappears in
    // requiredKeys, a secret has been reintroduced into a bundled asset.
    test('REGRESSION: no server-side secret is required on the device', () {
      expect(AppConfig.requiredKeys, isNot(contains('TERMII_API_KEY')));
      expect(AppConfig.requiredKeys, isNot(contains('HMAC_SECRET')));
      expect(AppConfig.requiredKeys, isNot(contains('CLOUDINARY_API_SECRET')));
    });

    // Nothing the app needs to keep people safe may depend on a value baked
    // into the binary. An empty list is the correct state, not an oversight.
    test('nothing safety-critical is required from the bundle at all', () {
      expect(AppConfig.requiredKeys, isEmpty);
      expect(AppConfig.missingRequiredKeys(), isEmpty);
    });

    test('HQ API base URL is null when unconfigured', () {
      expect(AppConfig.hqApiBaseUrl, isNull);
    });
  });
}

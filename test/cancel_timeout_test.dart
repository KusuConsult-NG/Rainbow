// A PIN check that never answers must end, and end the same way for any PIN.
//
// verifyCancellation had no time limit, so a stalled connection left the PIN
// screen waiting for minutes. Under duress the screen must behave normally, and
// the timeout's result, CancelOutcome.error, is the "could not be verified"
// message every PIN gets when the server cannot be reached.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rainbow_app/providers/emergency_provider.dart';

import 'support/offline_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => EmergencyNotifier.cancelLimit = const Duration(seconds: 15));

  test('a PIN check that never answers is reported as unverified', () async {
    installOfflineSupabase(handler: (_) => Completer<http.Response>().future);
    EmergencyNotifier.cancelLimit = const Duration(milliseconds: 100);
    final c = ProviderContainer();
    addTearDown(c.dispose);

    for (final pin in ['1234', '9876']) {
      final outcome = await c
          .read(emergencyProvider.notifier)
          .verifyCancellation(pin)
          .timeout(const Duration(seconds: 3),
              onTimeout: () => fail('the PIN check was still waiting'));
      expect(outcome, CancelOutcome.error, reason: 'the same for every PIN');
    }
  });
}

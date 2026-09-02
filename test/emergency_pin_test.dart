// Emergency PIN verification is a server call now.
//
// The device holds no PIN material: `verifyCancellation` sends the entry to
// `resolve_emergency` (or `verify_emergency_pin` when no alert exists yet) and
// acts on the outcome. These tests answer those RPCs from the offline Supabase
// seam and assert the one thing the client is responsible for getting right —
// what happens on each outcome. The PIN logic itself is asserted in
// scripts/emergency_pins_behaviour_test.sql against a real PostgreSQL.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rainbow_app/core/models/emergency_state.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';

import 'support/offline_supabase.dart';

/// Answers `resolve_emergency` / `verify_emergency_pin` with [reply] and records
/// what the app sent.
class _RpcSpy {
  final List<Map<String, dynamic>> calls = [];
  String reply;
  int status;
  _RpcSpy(this.reply, {this.status = 200});

  Future<http.Response> handle(http.Request request) async {
    final fn = request.url.pathSegments.last;
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    calls.add({'fn': fn, ...body});
    return http.Response(
      jsonEncode(reply),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
      request: request,
    );
  }
}

void main() {
  late ProviderContainer container;
  late int stopTrackingCalls;

  setUp(() {
    stopTrackingCalls = 0;
    EmergencyNotifier.stopTrackingOverride = () async => stopTrackingCalls++;
    container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(() => EmergencyNotifier.stopTrackingOverride = null);
  });

  EmergencyNotifier notifierWithAlert(String? alertId) {
    final n = container.read(emergencyProvider.notifier);
    n.state = EmergencyState(isEmergencyActive: true, alertId: alertId);
    return n;
  }

  test('sends the PIN and alert id to resolve_emergency, never compares locally',
      () async {
    final spy = _RpcSpy('RESOLVED');
    installOfflineSupabase(handler: spy.handle);
    final n = notifierWithAlert('alert-1');

    final outcome = await n.verifyCancellation('4321');

    expect(outcome, CancelOutcome.resolved);
    expect(spy.calls, hasLength(1));
    expect(spy.calls.single['fn'], 'resolve_emergency');
    expect(spy.calls.single['p_alert_id'], 'alert-1');
    expect(spy.calls.single['p_pin'], '4321');
  });

  test('the safe PIN clears the emergency and stops tracking', () async {
    installOfflineSupabase(handler: _RpcSpy('RESOLVED').handle);
    final n = notifierWithAlert('alert-1');

    expect(await n.verifyCancellation('1234'), CancelOutcome.resolved);
    expect(n.state.isEmergencyActive, isFalse);
    expect(stopTrackingCalls, 1);
  });

  // The whole point of a duress code: the screen behaves as if everything is
  // fine, but the phone keeps reporting where it is.
  test('the duress PIN clears the screen but keeps tracking running', () async {
    installOfflineSupabase(handler: _RpcSpy('DURESS').handle);
    final n = notifierWithAlert('alert-1');

    expect(await n.verifyCancellation('9999'), CancelOutcome.duress);
    expect(n.state.isEmergencyActive, isFalse);
    expect(stopTrackingCalls, 0);
  });

  test('a wrong PIN changes nothing', () async {
    installOfflineSupabase(handler: _RpcSpy('INVALID').handle);
    final n = notifierWithAlert('alert-1');

    expect(await n.verifyCancellation('0000'), CancelOutcome.invalid);
    expect(n.state.isEmergencyActive, isTrue);
    expect(stopTrackingCalls, 0);
  });

  test('lockout and an unset PIN are surfaced distinctly, not as "wrong PIN"',
      () async {
    installOfflineSupabase(handler: _RpcSpy('LOCKED').handle);
    expect(await notifierWithAlert('a').verifyCancellation('1234'),
        CancelOutcome.locked);

    installOfflineSupabase(handler: _RpcSpy('UNSET').handle);
    expect(await notifierWithAlert('a').verifyCancellation('1234'),
        CancelOutcome.unset);
  });

  test('with no server alert yet, verifies the PIN without touching alerts',
      () async {
    final spy = _RpcSpy('SAFE');
    installOfflineSupabase(handler: spy.handle);
    final n = notifierWithAlert(null);

    expect(await n.verifyCancellation('1234'), CancelOutcome.resolved);
    expect(spy.calls.single['fn'], 'verify_emergency_pin');
    expect(spy.calls.single.containsKey('p_alert_id'), isFalse);
  });

  // The old code returned false here too — an offline cancellation never
  // succeeded — but it is worth pinning that the failure is reported as a
  // connection problem, not as a wrong PIN.
  test('a server failure is reported as an error, and the emergency stays active',
      () async {
    installOfflineSupabase(
      handler: _RpcSpy('permission denied', status: 403).handle,
    );
    final n = notifierWithAlert('alert-1');

    expect(await n.verifyCancellation('1234'), CancelOutcome.error);
    expect(n.state.isEmergencyActive, isTrue);
    expect(stopTrackingCalls, 0);
  });
}

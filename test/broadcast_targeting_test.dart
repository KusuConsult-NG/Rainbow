// Who a mass broadcast reaches.
//
// This is the mechanism HQ uses to warn the public, and it was wrong in a way
// that reported success: the console wrote `target_audience`, the reader
// consulted `target_type`, and `target_type` defaults to 'ALL' — so a "FIELD
// RESPONDERS ONLY" advisory went to every citizen in the state while the
// console told the operator it had gone to responders. Geographic scope was
// never checked at all.
//
// So these tests are about delivery, not parsing. The two that matter most are
// "an advisory addressed to responders does not reach a citizen" and "an
// advisory scoped to one LGA does not reach the next one" — the two failures
// that were live and silent.

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/broadcast_targeting.dart';

const citizen = BroadcastRecipient(isResponder: false, geoLga: 'Jos North', geoWard: 'Gangare', geoPu: 'PU 003');
const responder = BroadcastRecipient(isResponder: true, geoLga: 'Jos North', geoWard: 'Gangare', geoPu: 'PU 003');
const elsewhere = BroadcastRecipient(isResponder: false, geoLga: 'Mangu', geoWard: 'Panyam', geoPu: 'PU 011');
const placeless = BroadcastRecipient(isResponder: false);

Map<String, dynamic> row({
  String? audience,
  String? legacyType,
  String? lga,
  String? ward,
  String? pu,
  bool? active,
  String? expiresAt,
}) => <String, dynamic>{
      'id': 'a1',
      'message': 'Avoid the area.',
      'severity': 'CRITICAL',
      if (audience != null) 'target_audience': audience,
      if (legacyType != null) 'target_type': legacyType,
      if (lga != null) 'target_lga': lga,
      if (ward != null) 'target_ward': ward,
      if (pu != null) 'target_pu': pu,
      if (active != null) 'is_active': active,
      if (expiresAt != null) 'expires_at': expiresAt,
    };

void main() {
  group('audience', () {
    test('an unscoped advisory reaches everybody', () {
      expect(broadcastReaches(row(audience: 'ALL'), citizen), isTrue);
      expect(broadcastReaches(row(audience: 'ALL'), responder), isTrue);
    });

    test('CITIZENS does not reach a responder', () {
      expect(broadcastReaches(row(audience: 'CITIZENS'), citizen), isTrue);
      expect(broadcastReaches(row(audience: 'CITIZENS'), responder), isFalse);
    });

    test('AGENTS does not reach a citizen — the failure that was live', () {
      expect(broadcastReaches(row(audience: 'AGENTS'), responder), isTrue);
      expect(broadcastReaches(row(audience: 'AGENTS'), citizen), isFalse);
    });

    test('reads the canonical column, not the legacy one', () {
      // Exactly the shape the console produced before the fix: addressed to
      // responders, with the legacy column left at its 'ALL' default. Reading
      // the legacy column is what sent it to everybody.
      final consoleRow = row(audience: 'AGENTS', legacyType: 'ALL');
      expect(broadcastReaches(consoleRow, citizen), isFalse);
    });

    test('falls back to the legacy column for rows written before the fix', () {
      expect(broadcastReaches(row(legacyType: 'AGENTS'), citizen), isFalse);
      expect(broadcastReaches(row(legacyType: 'AGENTS'), responder), isTrue);
    });

    test('an unrecognised audience reaches everyone rather than nobody', () {
      // Over-delivery is recoverable; an advisory that reaches nobody because
      // of a typo in a dropdown is not.
      expect(broadcastReaches(row(audience: 'EVERYBODY_PLS'), citizen), isTrue);
    });
  });

  group('geography', () {
    test('an LGA-scoped advisory does not reach the next LGA', () {
      final r = row(audience: 'ALL', lga: 'Jos North');
      expect(broadcastReaches(r, citizen), isTrue);
      expect(broadcastReaches(r, elsewhere), isFalse);
    });

    test('ward and polling unit narrow it further', () {
      expect(broadcastReaches(row(lga: 'Jos North', ward: 'Gangare'), citizen), isTrue);
      expect(broadcastReaches(row(lga: 'Jos North', ward: 'Tudun Wada'), citizen), isFalse);
      expect(broadcastReaches(row(pu: 'PU 003'), citizen), isTrue);
      expect(broadcastReaches(row(pu: 'PU 044'), citizen), isFalse);
    });

    test('place names are matched loosely, because they are typed by hand', () {
      // "Jos North", "JOS NORTH LGA" and "jos north" are one place. Failing to
      // match here drops a warning for somebody standing in the affected area.
      expect(broadcastReaches(row(lga: 'JOS NORTH LGA'), citizen), isTrue);
      expect(broadcastReaches(row(lga: 'jos north'), citizen), isTrue);
    });

    test('ALL and empty mean unscoped', () {
      expect(broadcastReaches(row(lga: 'ALL', ward: '', pu: 'ALL'), elsewhere), isTrue);
    });

    test('a recipient with no recorded place still gets scoped advisories', () {
      // Fails OPEN, on purpose. A missed evacuation order costs more than an
      // irrelevant notification.
      expect(broadcastReaches(row(lga: 'Jos North'), placeless), isTrue);
    });
  });

  group('lifecycle', () {
    final past = DateTime(2026, 1, 1);
    final now = DateTime(2026, 6, 1);
    final future = DateTime(2026, 12, 1);

    test('a withdrawn advisory is not delivered', () {
      expect(broadcastReaches(row(active: false), citizen, now: now), isFalse);
    });

    test('an expired advisory is not delivered', () {
      expect(
        broadcastReaches(row(expiresAt: past.toIso8601String()), citizen, now: now),
        isFalse,
      );
    });

    test('an advisory still within its window is delivered', () {
      expect(
        broadcastReaches(row(expiresAt: future.toIso8601String()), citizen, now: now),
        isTrue,
      );
    });

    test('no expiry means it stands until withdrawn', () {
      expect(broadcastReaches(row(), citizen, now: now), isTrue);
    });

    test('an unparseable expiry does not silently hide the advisory', () {
      expect(broadcastReaches(row(expiresAt: 'not a date'), citizen, now: now), isTrue);
    });
  });

  group('broadcastAudience', () {
    test('prefers the canonical column and normalises case', () {
      expect(broadcastAudience({'target_audience': 'citizens', 'target_type': 'ALL'}), 'CITIZENS');
    });

    test('falls back to legacy, then to ALL', () {
      expect(broadcastAudience({'target_type': 'AGENTS'}), 'AGENTS');
      expect(broadcastAudience({}), 'ALL');
      expect(broadcastAudience({'target_audience': '  '}), 'ALL');
    });
  });
}

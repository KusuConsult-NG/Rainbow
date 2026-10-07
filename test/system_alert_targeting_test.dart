// Who the app-wide advisory banner is actually for.
//
// `SystemAlertListener` wraps every screen in the app (app.dart builder), and
// it had its own targeting filter reading `target_type` and `target_value`. The
// HQ
// console writes neither — it writes `target_audience` plus `target_lga`,
// `target_ward` and `target_pu` — so `target_type` fell to its 'ALL' default
// on every advisory ever sent and the banner showed all of them to all
// users. An
// advisory composed for citizens of one ward reached every responder in
// Plateau.
//
// `broadcast_targeting.dart` exists because of that exact defect, and the fix
// landed in `broadcastProvider` (which feeds BroadcastHud) while this second
// reader of the same table was missed. One surface honoured the targeting and
// one ignored it.
//
// Every fixture here is shaped the way the console writes a row. The existing
// dismiss tests use the legacy `target_type` on purpose — that is the
// back-compatibility path, and it is asserted at the bottom.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/services/user_service.dart';
import 'package:rainbow_app/shared/widgets/system_alert_listener.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpWith(
    WidgetTester tester, {
    required List<Map<String, dynamic>> alerts,
    String role = 'CITIZEN',
    String? geoLga,
    String? geoWard,
    String? geoPu,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          systemAlertsStreamProvider
              .overrideWith((ref) => Stream.value(alerts)),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(
              {
                'role': role,
                'geo_lga': geoLga,
                'geo_ward': geoWard,
                'geo_pu': geoPu,
              },
            ),
          ),
        ],
        child: const MaterialApp(
          home: SystemAlertListener(child: Scaffold(body: SizedBox.shrink())),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// A row exactly as MassBroadcast.tsx inserts it.
  Map<String, dynamic> advisory({
    String id = 'b1',
    String message = 'Curfew from 18:00',
    String audience = 'ALL',
    String lga = 'ALL',
    String ward = 'ALL',
    String pu = 'ALL',
    String? expiresAt,
  }) =>
      {
        'id': id,
        'title': 'ADVISORY',
        'message': message,
        'severity': 'CRITICAL',
        'target_audience': audience,
        'target_agency': 'ALL',
        'target_lga': lga,
        'target_ward': ward,
        'target_pu': pu,
        'is_active': true,
        'expires_at': expiresAt,
      };

  final shown = find.text('CURFEW FROM 18:00');

  group('the audience the composer chose', () {
    testWidgets('a statewide advisory reaches a citizen', (tester) async {
      await pumpWith(tester, alerts: [advisory()]);
      expect(shown, findsOneWidget);
    });

    testWidgets('a statewide advisory reaches a responder', (tester) async {
      await pumpWith(tester, alerts: [advisory()], role: 'WARD_COMMAND');
      expect(shown, findsOneWidget);
    });

    // The one that was wrong. 'CITIZENS' is a choice in the composer, and the
    // banner showed it to every officer in the state.
    testWidgets('a CITIZENS advisory does not reach a responder',
        (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(audience: 'CITIZENS')],
        role: 'WARD_COMMAND',
      );
      expect(shown, findsNothing);
    });

    testWidgets('a CITIZENS advisory reaches a citizen', (tester) async {
      await pumpWith(tester, alerts: [advisory(audience: 'CITIZENS')]);
      expect(shown, findsOneWidget);
    });

    testWidgets('an AGENTS advisory does not reach a citizen', (tester) async {
      await pumpWith(tester, alerts: [advisory(audience: 'AGENTS')]);
      expect(shown, findsNothing);
    });

    testWidgets('an AGENTS advisory reaches a responder', (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(audience: 'AGENTS')],
        role: 'LGA_COMMAND',
      );
      expect(shown, findsOneWidget);
    });
  });

  group('the place the composer chose', () {
    testWidgets('an LGA advisory does not reach another LGA', (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(lga: 'JOS NORTH')],
        geoLga: 'MANGU',
      );
      expect(shown, findsNothing);
    });

    testWidgets('an LGA advisory reaches that LGA', (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(lga: 'JOS NORTH')],
        geoLga: 'JOS NORTH',
      );
      expect(shown, findsOneWidget);
    });

    testWidgets('a ward advisory does not reach another ward', (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(lga: 'MANGU', ward: 'GINDIRI')],
        geoLga: 'MANGU',
        geoWard: 'PANYAM',
      );
      expect(shown, findsNothing);
    });

    testWidgets('a ward advisory reaches that ward', (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(lga: 'MANGU', ward: 'GINDIRI')],
        geoLga: 'MANGU',
        geoWard: 'GINDIRI',
      );
      expect(shown, findsOneWidget);
    });

    // Deliberate, and the same rule broadcastReaches applies: a recipient with
    // no place recorded still gets a scoped warning. Showing it to somebody
    // outside the area costs a notification; withholding it from somebody
    // inside costs more.
    testWidgets('a scoped advisory still reaches a user with no LGA recorded',
        (tester) async {
      await pumpWith(tester, alerts: [advisory(lga: 'JOS NORTH')]);
      expect(shown, findsOneWidget);
    });
  });

  group('advisories that are over', () {
    testWidgets('an expired advisory is not shown', (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(expiresAt: '2020-01-01T00:00:00Z')],
      );
      expect(shown, findsNothing);
    });

    testWidgets('an advisory with a future expiry is shown', (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(expiresAt: '2099-01-01T00:00:00Z')],
      );
      expect(shown, findsOneWidget);
    });

    testWidgets('a withdrawn advisory is not shown', (tester) async {
      final row = advisory()..['is_active'] = false;
      await pumpWith(tester, alerts: [row]);
      expect(shown, findsNothing);
    });
  });

  group('HQ, and the legacy column', () {
    // HQ is the desk that sent the advisory and the desk that withdraws it, so
    // it sees every one regardless of who it was addressed to.
    testWidgets('HQ sees an advisory addressed to citizens elsewhere',
        (tester) async {
      await pumpWith(
        tester,
        alerts: [advisory(audience: 'CITIZENS', lga: 'JOS NORTH')],
        role: 'HQ_OFFICER',
        geoLga: 'MANGU',
      );
      expect(shown, findsOneWidget);
    });

    // Rows written before the column was reconciled carry `target_type` only.
    // `broadcastAudience` reads it as a fallback, so they must still arrive.
    testWidgets('a legacy row carrying only target_type still arrives',
        (tester) async {
      await pumpWith(
        tester,
        alerts: [
          {
            'id': 'legacy-1',
            'target_type': 'ALL',
            'severity': 'CRITICAL',
            'message': 'Curfew from 18:00',
          },
        ],
      );
      expect(shown, findsOneWidget);
    });

    testWidgets('a legacy CITIZENS row is honoured for a responder too',
        (tester) async {
      await pumpWith(
        tester,
        alerts: [
          {
            'id': 'legacy-2',
            'target_type': 'CITIZENS',
            'severity': 'HIGH',
            'message': 'Curfew from 18:00',
          },
        ],
        role: 'UNIT_COMMAND',
      );
      expect(shown, findsNothing);
    });
  });
}

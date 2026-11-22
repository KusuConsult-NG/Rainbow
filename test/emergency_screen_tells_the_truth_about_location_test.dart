// THE SCREEN A CITIZEN SAW IN JOS.
//
//     LOCATION BROADCASTING
//     Alert transmitted · Command HQ triaging...
//
//     LATITUDE  ---    LONGITUDE  ---    ACCURACY  ---
//
// Both at once, on a phone with no GPS fix, over a blank map. The alert
// reached HQ carrying latitude and longitude null.
//
// The repair shipped with a gate that reads the SOURCE
// (scripts/check_a_location_is_not_claimed_without_one.py). A gate that greps
// proves the code is SHAPED right; it cannot prove the screen BEHAVES right.
// These tests build the real screen and read what it puts in front of a
// person.
//
// Why this was never caught by the end-to-end run: scripts/local_e2e/
// mobile_interact.js grants geolocation and sets a position before it touches
// SOS, on purpose — "SOS needs a fix. Without this the permission gate stops
// the flow before any alert is created". So every automated pass over this
// screen has had a location. The one state a person in danger can actually be
// in was the one state nothing exercised.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rainbow_app/core/models/emergency_state.dart';
import 'package:rainbow_app/features/emergency/emergency_active_screen.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

/// Holds whatever state the test wants, and does not move.
class _FixedEmergency extends EmergencyNotifier {
  _FixedEmergency(this._initial);
  final EmergencyState _initial;

  @override
  EmergencyState build() => _initial;
}

Position _fix() => Position(
      latitude: 9.8965,
      longitude: 8.8583,
      timestamp: DateTime.now().toUtc(),
      accuracy: 5,
      altitude: 1200,
      altitudeAccuracy: 3,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

String en(String key) => Translations.get(key, AppLanguage.english);

void main() {
  /// Builds the real emergency screen. The screen runs a one-second periodic
  /// timer and a repeating pulse, so frames are driven by hand: pumpAndSettle
  /// would never return.
  Future<void> pumpScreen(
    WidgetTester tester, {
    required Position? position,
    String? alertId,
    String? hqStatus,
    bool sendFinished = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // The screen starts a one-second periodic timer (cancelled in dispose)
    // and a two-second Future.delayed that reveals the map, which cannot be
    // cancelled at all. Tear the tree down and let that one land, or the
    // binding fails every test here for a pending timer.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          emergencyProvider.overrideWith(
            () => _FixedEmergency(EmergencyState(
              isEmergencyActive: true,
              startTime: DateTime.now(),
              alertId: alertId,
              isSilent: true,
              sendFinished: sendFinished,
            )),
          ),
          userLocationStreamProvider
              .overrideWith((ref) => Stream<Position?>.value(position)),
          alertRowStreamProvider.overrideWith(
            (ref) => (id) => Stream<List<Map<String, dynamic>>>.value(
                  hqStatus == null ? [] : [
                    {'id': id, 'status': hqStatus},
                  ],
                ),
          ),
        ],
        child: const MaterialApp(home: EmergencyActiveScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('with no fix', () {
    // THE SCREENSHOT. An alert HQ has accepted and not yet triaged — status
    // PENDING — on a phone with no fix. This is the branch that printed
    // LOCATION BROADCASTING, and it only runs when the alert row arrives, so
    // the row is delivered here.
    testWidgets('never says LOCATION BROADCASTING, even on a PENDING alert',
        (tester) async {
      await pumpScreen(
        tester,
        position: null,
        alertId: 'alert-1',
        hqStatus: 'PENDING',
      );

      expect(find.text(en('eme_broadcasting')), findsNothing,
          reason: 'this is the exact string the citizen in Jos was shown '
              'while the phone had nothing to send');
      expect(find.text(en('eme_active_no_fix')), findsOneWidget);
      expect(find.text(en('eme_broadcasting_triaging')), findsNothing,
          reason: '"Alert transmitted" was the line under it');
    });

    testWidgets('still says it on a PENDING alert when there IS a fix',
        (tester) async {
      await pumpScreen(
        tester,
        position: _fix(),
        alertId: 'alert-1',
        hqStatus: 'PENDING',
      );

      // The string is not banned — it is true here, and this proves the test
      // above can actually see it.
      expect(find.text(en('eme_broadcasting')), findsOneWidget);
    });

    testWidgets('says plainly that no location is going out', (tester) async {
      await pumpScreen(tester, position: null);

      expect(find.byKey(const ValueKey('emergency_no_location_warning')),
          findsOneWidget);
      expect(find.text(en('eme_no_fix_title')), findsOneWidget);
    });

    testWidgets('offers a way to turn location on', (tester) async {
      await pumpScreen(tester, position: null);

      final button = find.byKey(const ValueKey('emergency_turn_on_location'));
      expect(button, findsOneWidget);
      expect(find.text(en('eme_no_fix_action')), findsOneWidget);
      // It is reachable, not just present.
      expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    });

    testWidgets('promises no location in the status card either',
        (tester) async {
      await pumpScreen(tester, position: null, sendFinished: false);

      // "Sending your alert AND LOCATION to HQ..." was shown whatever the
      // phone had.
      expect(find.text(en('eme_sending_desc')), findsNothing);
    });

    testWidgets('does not claim the location is still being recorded',
        (tester) async {
      await pumpScreen(tester, position: null);

      expect(find.text(en('eme_not_confirmed_desc')), findsNothing,
          reason: 'it ends "Your location is still being recorded."');
      expect(find.text(en('eme_not_confirmed_desc_no_fix')), findsOneWidget);
    });

    testWidgets('shows dashes for the coordinates, not a made-up number',
        (tester) async {
      await pumpScreen(tester, position: null);

      // C-5: a screen that invents coordinates is the worse failure. Three
      // readouts, three dashes.
      expect(find.text('---'), findsNWidgets(3));
    });
  });

  group('with a fix', () {
    testWidgets('shows the real coordinates and no warning', (tester) async {
      await pumpScreen(tester, position: _fix());

      expect(find.byKey(const ValueKey('emergency_no_location_warning')),
          findsNothing);
      expect(find.text('9.89650'), findsOneWidget);
      expect(find.text('8.85830'), findsOneWidget);
    });
  });
}

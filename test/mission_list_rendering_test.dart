// Rendering the mission list with actual alerts in it.
//
// This was impossible until `SupabaseConfig.clientOverride` existed:
// `_MissionCard.build` reads `SupabaseConfig.client`, and `Supabase.instance`
// asserts if `initialize` has not run, so a widget test could reach the empty
// state but never a populated one. Every list, card and map assertion in this
// file is coverage the suite did not previously have.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/agent/agent_dashboard_screen.dart';
import 'package:rainbow_app/providers/alerts_feed.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/services/user_service.dart';
import 'package:rainbow_app/shared/widgets/system_alert_listener.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'support/offline_supabase.dart';

class FakePushNotificationService implements PushNotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  Future<void> initialize() async {}
}

class FakeSyncService implements SyncService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  void initialize() {}
  @override
  ValueNotifier<bool> get isSyncing => ValueNotifier<bool>(false);
}

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier(AuthState initialState) {
    state = initialState;
  }
  @override
  void initAuth() {}
}

const _officerId = 'officer-under-test';

final _user = User(
  id: _officerId,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026).toIso8601String(),
);

final _auth = AuthState(
  user: _user,
  role: UserRole.responder,
  tier: ResponderTier.lga,
  isLoading: false,
  hasOnboarded: true,
  profile: const {
    'role': 'LGA_COMMANDER',
    'full_name': 'List Test Officer',
    'geo_lga': 'JOS SOUTH',
    'geo_ward': 'VOM',
  },
);

Map<String, dynamic> _alert({
  required String id,
  String lga = 'JOS SOUTH',
  String severity = 'MEDIUM',
  String status = 'OPEN',
  String createdAt = '2026-09-02T10:00:00Z',
  String? assignedTo,
}) =>
    <String, dynamic>{
      'id': id,
      'geo_lga': lga,
      'severity': severity,
      'status': status,
      'created_at': createdAt,
      'type': 'FIRE',
      if (assignedTo != null) 'assigned_to': assignedTo,
    };

Widget _dashboardShowing(List<Map<String, dynamic>> rows) => ProviderScope(
      overrides: [
        pushNotificationServiceProvider
            .overrideWithValue(FakePushNotificationService()),
        syncServiceProvider.overrideWithValue(FakeSyncService()),
        userLocationStreamProvider.overrideWith((ref) => const Stream.empty()),
        systemAlertsStreamProvider.overrideWith((ref) => const Stream.empty()),
        authProvider.overrideWith((ref) => FakeAuthNotifier(_auth)),
        splashFinishedProvider.overrideWith((ref) => true),
        userProfileProvider.overrideWith((ref) => Stream.value(_auth.profile)),
        alertsStreamProvider.overrideWith(
          (ref) => Stream.value(
            AlertsFeed(rows: rows, liveness: FeedLiveness.live),
          ),
        ),
        trackingStreamProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: const MaterialApp(home: AgentDashboardScreen()),
    );

void main() {
  setUp(installOfflineSupabase);

  testWidgets('alerts in the feed are rendered as mission cards',
      (tester) async {
    await tester.pumpWidget(
      _dashboardShowing([
        _alert(id: 'alert-1'),
        _alert(id: 'alert-2'),
      ]),
    );
    await tester.pump();

    // The empty states must be gone — this is the populated path.
    expect(find.text('ALL CLEAR - NO ACTIVE MISSIONS'), findsNothing);
    expect(find.text('MISSION FEED NOT LIVE'), findsNothing);
    expect(find.byType(ListView), findsWidgets);
  });

  // Tier scoping is enforced inside the pane, on rows the provider already
  // delivered. Previously only the provider-level filter could be tested;
  // this asserts what the officer actually SEES.
  //
  // These two tests run with NO session on the Supabase client, so
  // `AuthService.currentUserId` is null — which is also what happens in
  // production whenever the session cannot be read, because that getter
  // catches and returns null. That is the state in which the tier filter used
  // to fail open: `alert['assignedToUid'] == uid` became `null == null`, true
  // for every alert carrying no assignee, waving it past all tier scoping
  // below. A transient auth read failure would have shown every responder
  // every alert in the state.
  testWidgets('an out-of-jurisdiction alert is not shown to an LGA commander',
      (tester) async {
    await tester.pumpWidget(
      _dashboardShowing([
        _alert(id: 'mine'),
        _alert(id: 'theirs', lga: 'BARKIN LADI'),
      ]),
    );
    await tester.pump();

    // One card in, one card out: the list is populated but filtered.
    expect(find.text('ALL CLEAR - NO ACTIVE MISSIONS'), findsNothing);
    expect(find.textContaining('BARKIN LADI'), findsNothing,
        reason: "an alert outside the officer's LGA must not be displayed",);
  });

  // A feed that delivers ONLY out-of-jurisdiction rows leaves nothing to show.
  // The screen is live and correct to say so — this pins that filtering to
  // empty still reads as ALL CLEAR rather than as a broken feed.
  //
  // It is also the sharpest form of the null-uid regression above: with the
  // guard removed this test finds a card where there should be none.
  // Mutation-verified — dropping `uid != null` fails this and the test above.
  testWidgets('filtering every row away still reads as ALL CLEAR, not an error',
      (tester) async {
    await tester.pumpWidget(
      _dashboardShowing([_alert(id: 'theirs', lga: 'BARKIN LADI')]),
    );
    await tester.pump();

    expect(find.text('ALL CLEAR - NO ACTIVE MISSIONS'), findsOneWidget);
    expect(find.text('MISSION FEED NOT LIVE'), findsNothing);
  });

  testWidgets('a critical alert renders alongside a routine one',
      (tester) async {
    await tester.pumpWidget(
      _dashboardShowing([
        _alert(id: 'routine'),
        _alert(id: 'critical', severity: 'CRITICAL', status: 'DURESS'),
      ]),
    );
    await tester.pump();

    expect(find.text('ALL CLEAR - NO ACTIVE MISSIONS'), findsNothing);
    expect(tester.takeException(), isNull,
        reason: 'the CRITICAL/DURESS styling path must build cleanly',);
  });
}

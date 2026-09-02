// What the mission feed pane claims when the feed is NOT healthy.
//
// This exists because of the riverpod `.stream` migration. The old code nested
// two `StreamBuilder`s over `provider.stream`; the new code watches the
// providers as `AsyncValue`s. The two APIs disagree about errors in a way that
// matters here:
//
//   * `StreamBuilder` DROPS `snapshot.data` when an error arrives.
//   * `AsyncValue` RETAINS the previous value across an error.
//
// Taking riverpod's behaviour unexamined would leave the last known rows on
// screen still carrying `liveness: live` after the feed had died — the pane
// would assert a liveness it no longer has, and a responder would read a stale
// screen as a current one. The migration maps errors explicitly instead.
//
// The whole point is the difference between "there are no incidents" and "I am
// not being told what is happening", so that is what these assert.
import 'dart:async';

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

final _user = User(
  id: 'mission-feed-test',
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
    'full_name': 'Feed Test Officer',
    'geo_lga': 'JOS SOUTH',
    'geo_ward': 'VOM',
  },
);

Widget _dashboardWith(Stream<AlertsFeed> alerts) => ProviderScope(
      overrides: [
        pushNotificationServiceProvider
            .overrideWithValue(FakePushNotificationService()),
        syncServiceProvider.overrideWithValue(FakeSyncService()),
        userLocationStreamProvider.overrideWith((ref) => const Stream.empty()),
        systemAlertsStreamProvider.overrideWith((ref) => const Stream.empty()),
        authProvider.overrideWith((ref) => FakeAuthNotifier(_auth)),
        splashFinishedProvider.overrideWith((ref) => true),
        userProfileProvider.overrideWith((ref) => Stream.value(_auth.profile)),
        alertsStreamProvider.overrideWith((ref) => alerts),
        trackingStreamProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: const MaterialApp(home: AgentDashboardScreen()),
    );

void main() {
  testWidgets('a live, empty feed is the ONLY thing that says ALL CLEAR',
      (tester) async {
    await tester.pumpWidget(
      _dashboardWith(
        Stream.value(
          const AlertsFeed(rows: [], liveness: FeedLiveness.live),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('ALL CLEAR - NO ACTIVE MISSIONS'), findsOneWidget);
    expect(find.text('MISSION FEED NOT LIVE'), findsNothing);
  });

  testWidgets('a feed error says NOT LIVE, never ALL CLEAR', (tester) async {
    await tester.pumpWidget(
      _dashboardWith(Stream<AlertsFeed>.error(Exception('socket closed'))),
    );
    await tester.pump();

    expect(find.text('MISSION FEED NOT LIVE'), findsOneWidget);
    expect(find.text('ALL CLEAR - NO ACTIVE MISSIONS'), findsNothing);
  });

  // The regression the migration could have introduced, in its worst form.
  //
  // A live feed reports no incidents, so the pane says ALL CLEAR. Then the
  // stream errors. `AsyncValue` still holds that last AlertsFeed — rows empty,
  // liveness `live` — so a pane that trusted `.value` would go on displaying
  // ALL CLEAR after it had stopped being told anything at all. That is the
  // single most dangerous thing this screen can say, and the reason the
  // migration maps errors explicitly instead of reading `.value`.
  testWidgets('ALL CLEAR is withdrawn the moment the feed dies',
      (tester) async {
    final controller = StreamController<AlertsFeed>();
    addTearDown(controller.close);

    await tester.pumpWidget(_dashboardWith(controller.stream));

    controller.add(const AlertsFeed(rows: [], liveness: FeedLiveness.live));
    await tester.pump();
    await tester.pump();
    expect(find.text('ALL CLEAR - NO ACTIVE MISSIONS'), findsOneWidget,
        reason: 'precondition: a healthy feed reporting nothing',);

    controller.addError(Exception('realtime dropped'));
    await tester.pump();
    await tester.pump();

    expect(find.text('ALL CLEAR - NO ACTIVE MISSIONS'), findsNothing,
        reason: 'a dead feed cannot go on claiming there are no incidents',);
    expect(find.text('MISSION FEED NOT LIVE'), findsOneWidget);
  });
}

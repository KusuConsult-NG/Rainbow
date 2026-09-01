// Responder tier scoping — PU vs WARD vs LGA.
//
// Audit finding M-3. The pre-existing "multi-role" tests pump the agent
// dashboard for all three tiers and then assert the SAME string
// (`find.text('TACTICAL COMMAND')`) in each case. Those tests pass whether tier
// scoping works or is completely broken — they cannot detect the regression
// they are named for.
//
// These assert the parts of the UI that actually DIFFER by tier, so a change
// that collapses the tiers together fails here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/agent/agent_dashboard_screen.dart';
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
  id: 'responder-tier-test',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026).toIso8601String(),
);

AuthState _stateFor(ResponderTier tier, String role) => AuthState(
      user: _user,
      role: UserRole.responder,
      tier: tier,
      isLoading: false,
      hasOnboarded: true,
      profile: {
        'role': role,
        'full_name': 'Tier Test Officer',
        'geo_lga': 'JOS SOUTH',
        'geo_ward': 'VOM',
      },
    );

Widget _dashboardFor(AuthState auth) => ProviderScope(
      overrides: [
        pushNotificationServiceProvider
            .overrideWithValue(FakePushNotificationService()),
        syncServiceProvider.overrideWithValue(FakeSyncService()),
        userLocationStreamProvider.overrideWith((ref) => const Stream.empty()),
        systemAlertsStreamProvider.overrideWith((ref) => const Stream.empty()),
        authProvider.overrideWith((ref) => FakeAuthNotifier(auth)),
        splashFinishedProvider.overrideWith((ref) => true),
        userProfileProvider.overrideWith((ref) => Stream.value(auth.profile)),
      ],
      child: const MaterialApp(home: AgentDashboardScreen()),
    );

void main() {
  // agent_dashboard_screen.dart::_roleTitle maps tier -> banner text. If that
  // switch loses a case or the tier stops being resolved, these diverge.
  group('the dashboard banner reflects the responder tier', () {
    const cases = <ResponderTier, ({String role, String title})>{
      ResponderTier.lga: (role: 'LGA_COMMANDER', title: 'LGA COMMAND'),
      ResponderTier.ward: (role: 'WARD_COMMANDER', title: 'WARD COMMAND'),
      ResponderTier.pu: (role: 'UNIT_COMMANDER', title: 'UNIT COMMAND'),
    };

    cases.forEach((tier, expected) {
      testWidgets('${tier.name} shows "${expected.title}"', (tester) async {
        await tester.pumpWidget(_dashboardFor(_stateFor(tier, expected.role)));
        await tester.pump();

        expect(find.text(expected.title), findsWidgets,
            reason: '${tier.name} must render its own command banner');

        // ...and NOT another tier's. This is the half the old tests omitted:
        // asserting only the positive lets every tier render the same thing.
        for (final other in cases.values) {
          if (other.title == expected.title) continue;
          expect(find.text(other.title), findsNothing,
              reason: '${tier.name} must not render ${other.title}');
        }
      });
    });

    // An unresolved tier must not silently present as a command tier.
    testWidgets('an unknown tier falls back to a non-command banner',
        (tester) async {
      await tester.pumpWidget(
        _dashboardFor(_stateFor(ResponderTier.unknown, 'RESPONDER')),
      );
      await tester.pump();

      expect(find.text('LGA COMMAND'), findsNothing);
      expect(find.text('WARD COMMAND'), findsNothing);
      expect(find.text('UNIT COMMAND'), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/agent/mission_resolution_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
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

final fakeAgentUser = User(
  id: 'agent-user-001',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

void main() {
  testWidgets('Mission Resolution Screen: Render final report & archive controls', (tester) async {
    final alertData = {
      'id': 'alert-tactical-001',
      'type': 'KIDNAP - IMMEDIATE ABDUCTION',
      'description': 'Armed suspects fleeing towards Terminus Market.',
      'status': 'ON_SITE',
      'severity': 'HIGH',
      'latitude': 9.9285,
      'longitude': 8.8921,
      'geo_lga': 'JOS NORTH',
      'geo_ward': 'TUDUN WADA',
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          splashFinishedProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          home: MissionResolutionScreen(alertData: alertData),
        ),
      ),
    );

    // Verify Mission Resolution title
    expect(find.text('MISSION DEBRIEF & RESOLUTION'), findsOneWidget);
    expect(find.text('CLOSING OPERATIONAL REPORT'), findsOneWidget);
  });
}

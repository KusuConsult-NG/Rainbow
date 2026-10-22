import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/features/report/report_details_screen.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/shared/widgets/system_alert_listener.dart';
import 'package:rainbow_app/services/voice_note_service.dart';
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

class FakeAlertService implements AlertService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
  @override
  Future<String?> submitAlert({
    required String type,
    required String description,
    required String reportedBy,
    double? latitude,
    double? longitude,
    bool isCritical = false,
    AlertPriority priority = AlertPriority.medium,
    List<String>? attachments,
    VoiceNote? voiceNote,
    String? geoLga,
    String? geoWard,
    String? geoSiecWard,
    String? geoPu,
    String syncStatus = 'COMPLETED',
  }) async {
    return 'media-test-alert-123';
  }
}

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier(AuthState initialState) {
    state = initialState;
  }
  @override
  void initAuth() {}
  @override
  Future<void> resolveRole(dynamic user) async {}
}

Future<void> pumpSettleWithMax(WidgetTester tester, {int maxPumps = 30}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final fakeUser = User(
  id: 'test-media-user-123',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

void main() {
  testWidgets('Media Reporting: Renders voice recording, video, and camera controls', (tester) async {
    final kidnapCat = alertCategories.firstWhere((c) => c.label == 'Kidnap');
    final authState = AuthState(
      user: fakeUser,
      role: UserRole.citizen,
      isLoading: false,
      hasOnboarded: true,
      profile: {
        'role': 'CITIZEN',
        'displayName': 'Media Test User',
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(FakePushNotificationService()),
          syncServiceProvider.overrideWithValue(FakeSyncService()),
          alertServiceProvider.overrideWithValue(FakeAlertService()),
          userLocationStreamProvider.overrideWith((ref) => const Stream.empty()),
          systemAlertsStreamProvider.overrideWith((ref) => const Stream.empty()),
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ReportDetailsScreen(
              categoryInfo: kidnapCat,
              subType: 'IMMEDIATE ABDUCTION',
            ),
          ),
        ),
      ),
    );

    await pumpSettleWithMax(tester);

    // Verify Voice Reporting section
    expect(find.text('VOICE REPORTING (OPTIONAL)'), findsOneWidget);
    expect(find.text('RECORD VOICE REPORT'), findsOneWidget);

    // Verify Visual Telemetry section (Photo & Video)
    // Each control is scrolled to on its own.
    //
    // The category's response prompts — the armed/when/how-they-left questions
    // a responder needs — now sit above the narrative box, so everything below
    // moved down. This is a lazy scroll view: a control past the viewport is
    // not merely off-screen, it has not been BUILT, and the finder reports
    // "Found 0 widgets" for it, which reads identically to the control having
    // been deleted. Scrolling to each keeps the assertion honest about what it
    // is checking — that all four exist — without encoding how tall the screen
    // happens to be.
    for (final label in const [
      'VISUAL TELEMETRY (OPTIONAL)',
      'SCAN PHOTO',
      'RECORD VIDEO',
      'VIDEO INTEL',
    ]) {
      final control = find.text(label);
      await tester.scrollUntilVisible(
        control,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(control, findsOneWidget, reason: '$label is missing');
    }
  });
}

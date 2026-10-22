import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/features/report/report_category_screen.dart';
import 'package:rainbow_app/features/report/report_details_screen.dart';
import 'package:rainbow_app/features/report/report_subtype_screen.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/services/user_service.dart';
import 'package:rainbow_app/shared/widgets/system_alert_listener.dart';
import 'package:rainbow_app/services/voice_note_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

// ─── Fake Implementations ──────────────────────────────────────────────────

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
    return 'test-alert-id-99999';
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
  id: 'test-user-uuid-12345',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  testWidgets('E2E Reporting: Category selection renders all available categories', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(FakePushNotificationService()),
          syncServiceProvider.overrideWithValue(FakeSyncService()),
          userLocationStreamProvider.overrideWith((ref) => const Stream.empty()),
          systemAlertsStreamProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ReportCategoryScreen(),
          ),
        ),
      ),
    );

    await pumpSettleWithMax(tester);

    expect(find.byType(ReportCategoryScreen), findsOneWidget);
    expect(find.text('KIDNAP'), findsOneWidget);
    expect(find.text('FIRE'), findsOneWidget);
    expect(find.text('DRUG ABUSE'), findsOneWidget);
  });

  testWidgets('E2E Reporting: Selecting Kidnap category navigates to Subtypes', (tester) async {
    final kidnapCat = alertCategories.firstWhere((c) => c.label == 'Kidnap');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(FakePushNotificationService()),
          syncServiceProvider.overrideWithValue(FakeSyncService()),
          userLocationStreamProvider.overrideWith((ref) => const Stream.empty()),
          systemAlertsStreamProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ReportSubtypeScreen(categoryInfo: kidnapCat),
          ),
        ),
      ),
    );

    await pumpSettleWithMax(tester);

    expect(find.byType(ReportSubtypeScreen), findsOneWidget);
    expect(find.text('KIDNAP'), findsOneWidget);
    expect(find.text('IMMEDIATE ABDUCTION'), findsOneWidget);
    expect(find.text('HELD HOSTAGE'), findsOneWidget);
  });

  testWidgets('E2E Reporting: Filling details and submitting report generates alert & submits cleanly', (tester) async {
    final kidnapCat = alertCategories.firstWhere((c) => c.label == 'Kidnap');
    final authState = AuthState(
      user: fakeUser,
      role: UserRole.citizen,
      isLoading: false,
      hasOnboarded: true,
      profile: {
        'role': 'CITIZEN',
        'displayName': 'Test Citizen',
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
          userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
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

    expect(find.byType(ReportDetailsScreen), findsOneWidget);
    expect(find.text('INCIDENT DOSSIER'), findsOneWidget);

    // Scroll to it first, as this test already does for the submit button.
    //
    // The narrative box used to be the first thing under the header. The
    // category's response prompts now sit above it — the armed/when/how-they-
    // left questions a responder needs, answerable in a tap — so on a short
    // viewport the field is below the fold and a lazy scroll view has not
    // built it yet. `find.byType(TextField).first` then threw "Bad state: No
    // element", which is the finder saying the widget does not exist rather
    // than that it is out of view.
    final textField = find.byType(TextField);
    await tester.scrollUntilVisible(
      textField,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      textField.first,
      'Suspect vehicle seen fleeing towards Market Square',
    );
    await pumpSettleWithMax(tester, maxPumps: 5);

    expect(find.text('Suspect vehicle seen fleeing towards Market Square'), findsOneWidget);

    final submitBtn = find.text('INITIATE TRANSMISSION');
    await tester.scrollUntilVisible(submitBtn, 300, scrollable: find.byType(Scrollable).first);
    expect(submitBtn, findsOneWidget);
    await tester.tap(submitBtn);
    await pumpSettleWithMax(tester);
  });
}

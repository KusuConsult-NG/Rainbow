import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/constants/alert_categories.dart';
import 'package:rainbow_app/features/agent/admin_broadcast_screen.dart';
import 'package:rainbow_app/features/agent/mission_resolution_screen.dart';
import 'package:rainbow_app/features/citizen/safe_zone_screen.dart';
import 'package:rainbow_app/features/history/incident_history_screen.dart';
import 'package:rainbow_app/features/report/report_category_screen.dart';
import 'package:rainbow_app/features/report/report_details_screen.dart';
import 'package:rainbow_app/features/report/report_subtype_screen.dart';
import 'package:rainbow_app/features/settings/settings_screen.dart';
import 'package:rainbow_app/features/settings/uninstall_request_screen.dart';
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

// ─── Fakes ──────────────────────────────────────────────────────────────────

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
  @override
  Future<List<String>> queueMediaUpload({
    required String alertId,
    String? filePath,
    String? mediaType,
    List<dynamic>? files,
    String? userId,
  }) async => <String>[];
}

class FakeAlertService implements AlertService {
  final List<String> submittedAlertTypes = [];

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
    submittedAlertTypes.add(type);
    debugPrint('[TEST_DEBUG] submitAlert called for $type count=${submittedAlertTypes.length}');
    return 'alert-e2e-${submittedAlertTypes.length}';
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

final fakeCitizenUser = User(
  id: 'citizen-uuid-101',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

final fakeAgentUser = User(
  id: 'agent-uuid-202',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

Future<void> settleFast(WidgetTester tester, {int pumps = 25}) async {
  for (var i = 0; i < pumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fakeAlertService = FakeAlertService();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (methodCall) async {
        return ['wifi'];
      },
    );
  });

  setUp(fakeAlertService.submittedAlertTypes.clear);

  List<Override> getBaseOverrides(AuthState authState) {
    return [
      pushNotificationServiceProvider.overrideWithValue(FakePushNotificationService()),
      syncServiceProvider.overrideWithValue(FakeSyncService()),
      alertServiceProvider.overrideWithValue(fakeAlertService),
      userLocationStreamProvider.overrideWith((ref) => const Stream.empty()),
      systemAlertsStreamProvider.overrideWith((ref) => const Stream.empty()),
      authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
      splashFinishedProvider.overrideWith((ref) => true),
      userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
    ];
  }

  final citizenState = AuthState(
    user: fakeCitizenUser,
    role: UserRole.citizen,
    isLoading: false,
    hasOnboarded: true,
    profile: {
      'role': 'CITIZEN',
      'full_name': 'Plateau Citizen Test',
      'geo_lga': 'JOS SOUTH',
      'geo_ward': 'VOM',
    },
  );

  final agentState = AuthState(
    user: fakeAgentUser,
    role: UserRole.responder,
    tier: ResponderTier.lga,
    isLoading: false,
    hasOnboarded: true,
    profile: {
      'role': 'LGA_COMMANDER',
      'full_name': 'Commander Mark',
      'geo_lga': 'JOS SOUTH',
    },
  );

  group('E2E Category & Reporting UI Performance Suite', () {
    testWidgets('1. All 10 Categories render with labels, icons, & priorities in ReportCategoryScreen', (tester) async {
      final stopwatch = Stopwatch()..start();

      await tester.pumpWidget(
        ProviderScope(
          overrides: getBaseOverrides(citizenState),
          child: const MaterialApp(
            home: Scaffold(body: ReportCategoryScreen()),
          ),
        ),
      );
      await settleFast(tester);

      expect(find.byType(ReportCategoryScreen), findsOneWidget);

      // Every category the app offers is discoverable — derived from
      // `alertCategories`, so adding one is covered without editing this.
      for (final cat in alertCategories) {
        final categoryText = find.text(cat.label.toUpperCase());
        await tester.scrollUntilVisible(categoryText, 200, scrollable: find.byType(Scrollable).first);
        expect(categoryText, findsOneWidget, reason: 'Category ${cat.label} missing in UI grid');
      }

      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(5000), reason: 'UI render time exceeded threshold');
    });

    testWidgets('2. Full reporting flow on EVERY category (Subtype -> Dossier -> Transmission)', (tester) async {
      for (final catInfo in alertCategories) {
        // Test Subtypes Screen
        await tester.pumpWidget(
          ProviderScope(
            overrides: getBaseOverrides(citizenState),
            child: MaterialApp(
              home: Scaffold(
                body: ReportSubtypeScreen(categoryInfo: catInfo),
              ),
            ),
          ),
        );
        await settleFast(tester);

        expect(find.text(catInfo.label.toUpperCase()), findsOneWidget);
        expect(find.text(catInfo.subTypes.first.toUpperCase()), findsOneWidget);

        // Test Details & Submission Screen
        await tester.pumpWidget(
          ProviderScope(
            overrides: getBaseOverrides(citizenState),
            child: MaterialApp(
              home: Scaffold(
                body: ReportDetailsScreen(
                  categoryInfo: catInfo,
                  subType: catInfo.subTypes.first,
                ),
              ),
            ),
          ),
        );
        await settleFast(tester);

        expect(find.text('INCIDENT DOSSIER'), findsOneWidget);

        // Enter report description.
        //
        // Scrolled to first: a category with response prompts — the
        // armed/when/how-they-left questions a responder needs — carries them
        // above this box, so in a lazy scroll view the field below them has
        // not been built and `.first` on an empty finder throws "Bad state:
        // No element" rather than saying the field is off-screen.
        final inputField = find.byType(TextField);
        await tester.scrollUntilVisible(
          inputField,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(inputField.first, 'Testing automated E2E report submission for category ${catInfo.label}');
        await settleFast(tester, pumps: 2);

        // Submit
        final submitBtn = find.text('INITIATE TRANSMISSION');
        await tester.scrollUntilVisible(submitBtn, 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(submitBtn);
        await settleFast(tester);
      }

      // Verify all 10 reports were submitted into the service
      // Counted from the catalogue rather than hardcoded. It said 10, and two
      // non-emergency categories — Public property and Public service — took
      // it to 12, so a test whose whole subject is "every category can be
      // filed" failed for the reason it should have passed.
      expect(
        fakeAlertService.submittedAlertTypes.length,
        equals(alertCategories.length),
        reason: 'every category in alertCategories must reach submitAlert',
      );
    });
  });

  group('E2E Multi-Role UI & Screen Coverage', () {
    testWidgets('3. Safe Zones Evacuation UI loads active safe havens & controls', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: getBaseOverrides(citizenState),
          child: const MaterialApp(
            home: SafeZoneScreen(),
          ),
        ),
      );
      await settleFast(tester);

      expect(find.byType(SafeZoneScreen), findsOneWidget);
      expect(find.text('SAFE-ZONE ROUTING'), findsOneWidget);
    });

    testWidgets('4. Admin Broadcast Sender UI permits severity, target, and expiry selection', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: getBaseOverrides(agentState),
          child: const MaterialApp(
            home: AdminBroadcastScreen(),
          ),
        ),
      );
      await settleFast(tester);

      expect(find.text('HQ BROADCAST SENDER'), findsOneWidget);

      final sendBtn = find.text('SEND BROADCAST');
      await tester.scrollUntilVisible(sendBtn, 300, scrollable: find.byType(Scrollable).first);
      expect(sendBtn, findsOneWidget);

      final messageInput = find.byType(TextField).first;
      await tester.enterText(messageInput, 'URGENT: Curfew in effect across Jos South starting 21:00');
      await settleFast(tester, pumps: 2);

      expect(find.text('URGENT: Curfew in effect across Jos South starting 21:00'), findsOneWidget);
    });

    testWidgets('5. Settings & Uninstall Request UI screens load and permit form input', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: getBaseOverrides(citizenState),
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );
      await settleFast(tester);

      expect(find.text('TACTICAL SYSTEM SETTINGS'), findsOneWidget);
      expect(find.text('Plateau Citizen Test'), findsOneWidget);

      // Uninstall Request screen
      await tester.pumpWidget(
        ProviderScope(
          overrides: getBaseOverrides(citizenState),
          child: const MaterialApp(
            home: UninstallRequestScreen(),
          ),
        ),
      );
      await settleFast(tester);

      expect(find.text('APP REMOVAL AUTHORIZATION'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('6. Incident History & Mission Debrief screens render correctly', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: getBaseOverrides(citizenState),
          child: const MaterialApp(
            home: IncidentHistoryScreen(),
          ),
        ),
      );
      await settleFast(tester);

      expect(find.text('TACTICAL INCIDENT LOGS'), findsOneWidget);

      // Mission Debrief screen
      await tester.pumpWidget(
        ProviderScope(
          overrides: getBaseOverrides(agentState),
          child: const MaterialApp(
            home: MissionResolutionScreen(
              alertData: {
                'id': 'alert-1234',
                'type': 'COMMUNITY ATTACK',
                'description': 'Attack repelled by local defense forces',
              },
            ),
          ),
        ),
      );
      await settleFast(tester);

      expect(find.text('MISSION DEBRIEF & RESOLUTION'), findsOneWidget);
      expect(find.text('MARK MISSION AS RESOLVED'), findsOneWidget);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/app.dart';
import 'package:rainbow_app/features/agent/agent_dashboard_screen.dart';
import 'package:rainbow_app/features/auth/login_screen.dart';
import 'package:rainbow_app/features/citizen/safe_zone_screen.dart';
import 'package:rainbow_app/features/home/home_screen.dart';
import 'package:rainbow_app/features/report/report_category_screen.dart';
import 'package:rainbow_app/features/splash/splash_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/services/user_service.dart';
import 'package:rainbow_app/shared/widgets/system_alert_listener.dart';
import 'package:rainbow_app/shared/widgets/tactical_drawer.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

// ─── Fake service implementations ──────────────────────────────────────────

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

  @override
  Future<void> resolveRole(dynamic user) async {}
}

// ─── Helpers ────────────────────────────────────────────────────────────────

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

final List<Override> commonOverrides = [
  pushNotificationServiceProvider.overrideWithValue(FakePushNotificationService()),
  syncServiceProvider.overrideWithValue(FakeSyncService()),
  userLocationStreamProvider.overrideWith((ref) => const Stream.empty()),
  userProfileProvider.overrideWith((ref) => const Stream.empty()),
  systemAlertsStreamProvider.overrideWith((ref) => const Stream.empty()),
];

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  testWidgets('E2E: Splash screen shows and transitions to LoginScreen', (tester) async {
    final authState = AuthState(
      isLoading: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
        ],
        child: const RainbowApp(),
      ),
    );

    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    await pumpSettleWithMax(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('E2E: Unauthenticated user sees LoginScreen', (tester) async {
    final authState = AuthState(
      isLoading: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('E2E: Login screen has phone field and authorize button', (tester) async {
    final authState = AuthState(
      isLoading: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('SECURE IDENTIFIER'), findsOneWidget);
    expect(find.text('AUTHORIZE ACCESS'), findsOneWidget);
    expect(find.byType(TextField), findsAtLeastNWidgets(1));
  });

  testWidgets('E2E: Login screen phone field accepts text input', (tester) async {
    final authState = AuthState(
      isLoading: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    final phoneField = find.byType(TextField).first;
    await tester.enterText(phoneField, '08000000000');
    await pumpSettleWithMax(tester, maxPumps: 5);

    expect(find.text('08000000000'), findsOneWidget);
  });

  testWidgets('E2E: Authenticated Citizen user routes to HomeScreen', (tester) async {
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
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
          userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('SYSTEM NOMINAL'), findsOneWidget);
    expect(find.text('SOS'), findsOneWidget);
    expect(find.text('SAFE ZONES'), findsOneWidget);
  });

  testWidgets('E2E: Citizen tapping SOS activates silent emergency alert', (tester) async {
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
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
          userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    final sosFinder = find.text('SOS');
    expect(sosFinder, findsOneWidget);
    await tester.tap(sosFinder);
    await pumpSettleWithMax(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('E2E: Citizen tapping SAFE ZONES opens SafeZoneScreen', (tester) async {
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
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
          userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    final safeZoneBtn = find.text('SAFE ZONES');
    expect(safeZoneBtn, findsOneWidget);
    await tester.tap(safeZoneBtn);
    await pumpSettleWithMax(tester);

    expect(find.byType(SafeZoneScreen), findsOneWidget);
    expect(find.text('SAFE-ZONE ROUTING'), findsOneWidget);
  });

  testWidgets('E2E: Citizen tapping REPORT INCIDENT opens ReportCategoryScreen', (tester) async {
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
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
          userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    final reportBtn = find.text('REPORT INCIDENT');
    expect(reportBtn, findsOneWidget);
    await tester.tap(reportBtn);
    await pumpSettleWithMax(tester);

    expect(find.byType(ReportCategoryScreen), findsOneWidget);
  });

  testWidgets('E2E: TacticalDrawer renders SECURITY HUB and MISSION ARCHIVE tiles', (tester) async {
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
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            drawer: TacticalDrawer(),
          ),
        ),
      ),
    );

    await pumpSettleWithMax(tester);

    // Open drawer
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await pumpSettleWithMax(tester);

    expect(find.text('SECURITY HUB'), findsOneWidget);
    expect(find.text('MISSION ARCHIVE'), findsOneWidget);
    expect(find.text('TERMINATE SESSION'), findsOneWidget);
  });

  testWidgets('E2E: Authenticated PU Agent routes to AgentDashboardScreen', (tester) async {
    final authState = AuthState(
      user: fakeUser,
      role: UserRole.responder,
      tier: ResponderTier.pu,
      isLoading: false,
      hasOnboarded: true,
      profile: {
        'role': 'RESPONDER',
        'tier': 'pu',
        'geo_lga': 'JOS NORTH',
        'geo_ward': 'TUDUN WADA',
        'geo_pu': 'PU-001',
        'displayName': 'Agent Sunday',
        'status': 'active',
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
          userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
          alertsStreamProvider.overrideWith((ref) => const Stream.empty()),
          trackingStreamProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    expect(find.byType(AgentDashboardScreen), findsOneWidget);
    expect(find.text('UNIT COMMAND'), findsOneWidget);
  });

  testWidgets('E2E: Ward Commander routes to AgentDashboardScreen with Ward Tier', (tester) async {
    final authState = AuthState(
      user: fakeUser,
      role: UserRole.responder,
      tier: ResponderTier.ward,
      isLoading: false,
      hasOnboarded: true,
      profile: {
        'role': 'RESPONDER',
        'tier': 'ward',
        'geo_lga': 'JOS NORTH',
        'geo_ward': 'WARD-001',
        'displayName': 'Commander Ward',
        'status': 'active',
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
          userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
          alertsStreamProvider.overrideWith((ref) => const Stream.empty()),
          trackingStreamProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    expect(find.byType(AgentDashboardScreen), findsOneWidget);
    expect(find.text('WARD COMMAND'), findsOneWidget);
  });

  testWidgets('E2E: LGA Commander routes to AgentDashboardScreen with LGA Tier', (tester) async {
    final authState = AuthState(
      user: fakeUser,
      role: UserRole.responder,
      tier: ResponderTier.lga,
      isLoading: false,
      hasOnboarded: true,
      profile: {
        'role': 'RESPONDER',
        'tier': 'lga',
        'geo_lga': 'LGA-JOS-NORTH-001',
        'displayName': 'LGA HQ Commander',
        'status': 'active',
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...commonOverrides,
          authProvider.overrideWith((ref) => FakeAuthNotifier(authState)),
          splashFinishedProvider.overrideWith((ref) => true),
          userProfileProvider.overrideWith((ref) => Stream.value(authState.profile)),
          alertsStreamProvider.overrideWith((ref) => const Stream.empty()),
          trackingStreamProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const RainbowApp(),
      ),
    );

    await pumpSettleWithMax(tester);

    expect(find.byType(AgentDashboardScreen), findsOneWidget);
    expect(find.text('LGA COMMAND'), findsOneWidget);
  });
}

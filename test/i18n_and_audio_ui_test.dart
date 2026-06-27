import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rainbow_app/features/home/home_screen.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/push_notification_service.dart';
import 'package:rainbow_app/services/sync_service.dart';
import 'package:rainbow_app/services/broadcast_service.dart';
import 'package:rainbow_app/shared/widgets/broadcast_hud.dart';

// Mocks to isolate screen widget from hardware/services
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
  Future<Map<String, String>> flushOfflineQueue() async => {};
}

class FakeAuthNotifier extends AuthNotifier {
  FakeAuthNotifier() {
    state = AuthState(
      user: null,
      role: UserRole.citizen,
      isLoading: false,
    );
  }

  @override
  void initAuth() {}
}

Future<void> pumpSettleWithMax(WidgetTester tester, {int maxPumps = 10}) async {
  for (int i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TargetPlatform? originalPlatform;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    originalPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = originalPlatform;
  });

  testWidgets('Mobile UI: Language Selector Dropdown on HomeScreen updates text to Hausa', (tester) async {
    const channel = MethodChannel('id.flutter.background.service');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'isRunning') {
        return false;
      }
      return null;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushNotificationServiceProvider.overrideWithValue(FakePushNotificationService()),
          syncServiceProvider.overrideWithValue(FakeSyncService()),
          alertServiceProvider.overrideWithValue(FakeAlertService()),
          authProvider.overrideWith((ref) => FakeAuthNotifier()),
          broadcastProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await pumpSettleWithMax(tester);

    // 1. Verify default title is in English
    expect(find.text('OPERATION RAINBOW'), findsOneWidget);
    expect(find.text('SAFE ZONES'), findsOneWidget);

    // 2. Verify the Language dropdown button itself is visible on the App Bar
    final langMenuFinder = find.byType(PopupMenuButton<AppLanguage>);
    expect(langMenuFinder, findsOneWidget);

    // 3. Programmatically change language to Hausa via Riverpod Container
    final element = tester.element(find.byType(HomeScreen));
    final container = ProviderScope.containerOf(element);
    
    container.read(languageProvider.notifier).setLanguage(AppLanguage.hausa);
    await pumpSettleWithMax(tester);

    // 4. Verify title and bottom navigation options update immediately to Hausa translations
    expect(find.text('AIKIN RAINBOW'), findsOneWidget);
    expect(find.text('SASHEN TSIRA'), findsOneWidget);

    // 5. Programmatically change language to Pidgin
    container.read(languageProvider.notifier).setLanguage(AppLanguage.pidgin);
    await pumpSettleWithMax(tester);

    // 6. Verify title updates back (Pidgin uses English title but translates nav actions)
    expect(find.text('OPERATION RAINBOW'), findsOneWidget);
    expect(find.text('SAFE AREA DEM'), findsOneWidget); 

    // Restore platform inside the test body before invariant check runs
    debugDefaultTargetPlatformOverride = originalPlatform;
  });
}

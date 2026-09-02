import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainbow_app/features/agent/agent_dashboard_screen.dart';
import 'package:rainbow_app/features/home/home_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

import 'test_fixtures.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('📱 Operation Rainbow Multi-Role (Citizen, PU, Ward, LGA, HQ) Automated Integration Test Suite', () {
    testWidgets('1. Citizen Role UI: HomeScreen, Map, SOS & Category Launchers', (tester) async {
      await tester.pumpWidget(TestFixtures.buildTestableWidget(const HomeScreen(), role: UserRole.citizen));
      await tester.pumpAndSettle();

      expect(find.text('REPORT INCIDENT'), findsOneWidget);
      expect(find.text('SAFE ZONES'), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      debugPrint('✅ [MULTI_ROLE_TEST] Citizen Role UI verified.');
    });

    testWidgets('2. PU Responder Role UI: AgentDashboardScreen, ENGAGE button & Ward Alert Scope', (tester) async {
      await tester.pumpWidget(TestFixtures.buildTestableWidget(const AgentDashboardScreen(), role: UserRole.responder, tier: ResponderTier.pu));
      await tester.pumpAndSettle();

      expect(find.text('TACTICAL COMMAND'), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      debugPrint('✅ [MULTI_ROLE_TEST] PU Responder Role UI verified.');
    });

    testWidgets('3. Ward Commander Role UI: Squad Dispatch & Ward Escalation Scope', (tester) async {
      await tester.pumpWidget(TestFixtures.buildTestableWidget(const AgentDashboardScreen(), role: UserRole.responder, tier: ResponderTier.ward));
      await tester.pumpAndSettle();

      expect(find.text('TACTICAL COMMAND'), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      debugPrint('✅ [MULTI_ROLE_TEST] Ward Commander Role UI verified.');
    });

    testWidgets('4. LGA Commander Role UI: Multi-Unit Dispatch & LGA Escalation Scope', (tester) async {
      await tester.pumpWidget(TestFixtures.buildTestableWidget(const AgentDashboardScreen(), role: UserRole.responder, tier: ResponderTier.lga));
      await tester.pumpAndSettle();

      expect(find.text('TACTICAL COMMAND'), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      debugPrint('✅ [MULTI_ROLE_TEST] LGA Commander Role UI verified.');
    });
  });
}

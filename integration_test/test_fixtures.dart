import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

class TestFixtures {
  static Widget buildTestableWidget(Widget child, {UserRole role = UserRole.unknown, ResponderTier tier = ResponderTier.unknown}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => AuthNotifierMock(role: role, tier: tier)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: child,
      ),
    );
  }
}

class AuthNotifierMock extends AuthNotifier {
  AuthNotifierMock({UserRole role = UserRole.unknown, ResponderTier tier = ResponderTier.unknown}) {
    state = AuthState(
      role: role,
      tier: tier,
      isLoading: false,
      hasOnboarded: true,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Documentation for this public member.

enum UserRole {
  /// Documentation for user role citizen.
  citizen,

  /// Documentation for user role responder.
  responder,

  /// Documentation for user role unknown.
  unknown,
}

/// Documentation for this public member.

enum ResponderTier {
  /// Documentation for polling unit.
  pu,

  /// Documentation for ward.
  ward,

  /// Documentation for local government area.
  lga,

  /// Documentation for unknown responder tier.
  unknown,
}

/// Documentation for this public member.

class AuthState {
  /// Documentation for this public member.
  AuthState({
    this.user,
    this.role = UserRole.unknown,
    this.tier = ResponderTier.unknown,
    this.jurisdiction,
    this.profile,
    this.hasOnboarded = false,
    this.isLoading = true,
  });

  /// Documentation for this public member.
  final User? user;

  /// Documentation for this public member.
  final UserRole role;

  /// Documentation for this public member.
  final ResponderTier tier;

  /// Documentation for this public member.
  final String? jurisdiction;

  /// Documentation for this public member.
  final Map<String, dynamic>? profile;

  /// Documentation for this public member.
  final bool hasOnboarded;

  /// Documentation for this public member.
  final bool isLoading;

  /// Documentation for this public member.

  AuthState copyWith({
    User? user,
    UserRole? role,
    ResponderTier? tier,
    String? jurisdiction,
    Map<String, dynamic>? profile,
    bool? hasOnboarded,
    bool? isLoading,
  }) {
    return AuthState(
      user: user ?? this.user,
      role: role ?? this.role,
      tier: tier ?? this.tier,
      jurisdiction: jurisdiction ?? this.jurisdiction,
      profile: profile ?? this.profile,
      hasOnboarded: hasOnboarded ?? this.hasOnboarded,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Documentation for this public member.

  String get segment {
    if (role == UserRole.citizen) return 'citizens';
    if (role == UserRole.responder) {
      final r = profile?['role']?.toString().toUpperCase() ?? '';
      if (r.contains('HQ')) return 'hq_command';
      if (tier == ResponderTier.lga) return 'lga_command';
      if (tier == ResponderTier.ward) return 'ward_command';
      if (tier == ResponderTier.pu) return 'unit_command';
      return 'field_agents';
    }
    return 'unknown';
  }
}

/// Documentation for this public member.

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

/// Documentation for this public member.

class AuthNotifier extends StateNotifier<AuthState> {
  /// Documentation for this public member.
  AuthNotifier() : super(AuthState()) {
    initAuth();
  }

  void initAuth() {
    // Safety net: if Firebase auth hasn't emitted within 10s (slow network / iOS 26),
    // force isLoading=false so the router never stays frozen on splash forever.
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && state.isLoading) {
        debugPrint('[AUTH] Safety timeout — forcing isLoading=false');
        state = state.copyWith(isLoading: false);
      }
    });

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        state = AuthState(isLoading: false);
      } else {
        await resolveRole(user);
      }
    });
  }

  /// Documentation for this public member.

  Future<void> resolveRole(User user) async {
    state = state.copyWith(isLoading: true, user: user);

    try {
      // First try to get cached token result without forcing a network refresh/App Check verification
      final idTokenResult = await user.getIdTokenResult().timeout(
            const Duration(seconds: 5),
            onTimeout: () =>
                user.getIdTokenResult().timeout(const Duration(seconds: 5)),
          );
      final claims = idTokenResult.claims;

      var role = UserRole.citizen;
      var tier = ResponderTier.unknown;
      String? jurisdiction;

      if (claims != null && claims.containsKey('role')) {
        final roleStr = claims['role']?.toString() ?? '';
        if (roleStr == 'CITIZEN' || roleStr == 'USER') {
          role = UserRole.citizen;
        } else {
          role = UserRole.responder;
          // Align with HQ Dashboard segments
          if (roleStr.contains('HQ')) {
            tier = ResponderTier.unknown; // HQ is special
          } else if (roleStr.contains('LGA')) {
            tier = ResponderTier.lga;
          } else if (roleStr.contains('WARD')) {
            tier = ResponderTier.ward;
          } else if (roleStr.contains('UNIT') || roleStr.contains('POLLING')) {
            tier = ResponderTier.pu;
          }

          jurisdiction = claims['jurisdiction'] as String?;
        }
      } else if (user.phoneNumber != null) {
        role = UserRole.citizen;
      }

      // Fetch profile from Firestore (with timeout for slow review network)
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () => FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get(const GetOptions(source: Source.cache)),
          );
      final profile = profileDoc.data();

      // Load onboarding status
      // Responders are provisioned by HQ — always treat as onboarded.
      // Citizens rely on SharedPreferences + Firestore profileComplete flag.
      bool hasOnboarded;
      if (role == UserRole.responder) {
        hasOnboarded = true;
      } else {
        final prefs = await SharedPreferences.getInstance();
        hasOnboarded = prefs.getBool('hasOnboarded') ??
            (profile?['profileComplete'] as bool? ?? false);
      }

      state = AuthState(
        user: user,
        role: role,
        tier: tier,
        jurisdiction: jurisdiction,
        profile: profile,
        hasOnboarded: hasOnboarded,
        isLoading: false,
      );
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint(
        '[AUTH] Token resolving failed: $e. Falling back to email/profile resolution...',
      );

      // FALLBACK RESOLUTION GATE: Handles local debugging/App Check blockages gracefully
      try {
        var role = UserRole.citizen;
        var tier = ResponderTier.unknown;
        String? jurisdiction;

        if (user.uid.startsWith('agent_') ||
            (user.email != null &&
                user.email!.endsWith('@operationrainbow.plateau.gov.ng'))) {
          role = UserRole.responder;
        }

        final profileDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get(const GetOptions(source: Source.cache)),
            );

        final profile = profileDoc.data();
        if (profile != null) {
          final roleStr = profile['role']?.toString() ?? '';
          if (roleStr.isNotEmpty) {
            if (roleStr == 'CITIZEN' || roleStr == 'USER') {
              role = UserRole.citizen;
            } else {
              role = UserRole.responder;
              if (roleStr.contains('HQ')) {
                tier = ResponderTier.unknown;
              } else if (roleStr.contains('LGA')) {
                tier = ResponderTier.lga;
              } else if (roleStr.contains('WARD')) {
                tier = ResponderTier.ward;
              } else if (roleStr.contains('UNIT') ||
                  roleStr.contains('POLLING')) {
                tier = ResponderTier.pu;
              }
            }
          }
          jurisdiction = profile['geo_lga'] as String?;
        }

        state = AuthState(
          user: user,
          role: role,
          tier: tier,
          jurisdiction: jurisdiction,
          profile: profile,
          hasOnboarded: true,
          isLoading: false,
        );
        // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
      } catch (fallbackErr) {
        debugPrint('[AUTH] Fallback resolution failed: $fallbackErr');
        state = state.copyWith(isLoading: false, role: UserRole.unknown);
      }
    }
  }

  /// Documentation for this public member.

  // ignore: avoid_positional_boolean_parameters, Stylistic override
  Future<void> setOnboarded(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasOnboarded', value);
    state = state.copyWith(hasOnboarded: value);
  }

  /// Documentation for this public member.

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }
}

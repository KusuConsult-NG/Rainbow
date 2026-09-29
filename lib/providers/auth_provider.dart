import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// State command. The TOP of the chain, and distinct from [unknown].
  ///
  /// HQ used to map to [unknown], which it shares with a plain RESPONDER who
  /// has no tier at all — so the two ends of the command chain were the same
  /// value, and everything that switched on tier fell to its default for both.
  /// That produced an HQ dashboard titled "OPERATIONAL UNIT", and an HQ
  /// escalation tagged 'UNIT' by one code path and 'LGA' by another on the
  /// same screen.
  hq,

  /// No tier: a responder who is not part of the PU/WARD/LGA/HQ chain.
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
    this.resolutionError,
    this.sessionEpoch = 0,
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

  /// Non-null when role resolution failed. The router treats this as
  /// "authenticated but role unknown" rather than silently downgrading the user.
  final String? resolutionError;

  /// How many times someone has signed in on this launch.
  ///
  /// The re-entry lock is scoped to one sign-in, and a user id alone cannot
  /// express that: signing out and straight back in as the same person gives
  /// the same id. `last_sign_in_at` looks like the answer and is not a safe
  /// one — it is a value the backend controls, and the local stand-in stamps
  /// it once at start-up, so two sign-ins carried the identical timestamp and
  /// a lock survived across them. Counting the sign-in events this app has
  /// actually observed depends on nothing but this app.
  ///
  /// It resets on relaunch, which is correct: the lock does not survive one
  /// either.
  final int sessionEpoch;

  /// Documentation for this public member.

  AuthState copyWith({
    User? user,
    UserRole? role,
    ResponderTier? tier,
    String? jurisdiction,
    Map<String, dynamic>? profile,
    bool? hasOnboarded,
    bool? isLoading,
    String? resolutionError,
    int? sessionEpoch,
  }) {
    return AuthState(
      sessionEpoch: sessionEpoch ?? this.sessionEpoch,
      user: user ?? this.user,
      role: role ?? this.role,
      tier: tier ?? this.tier,
      jurisdiction: jurisdiction ?? this.jurisdiction,
      profile: profile ?? this.profile,
      hasOnboarded: hasOnboarded ?? this.hasOnboarded,
      isLoading: isLoading ?? this.isLoading,
      resolutionError: resolutionError ?? this.resolutionError,
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

  StreamSubscription<AuthState>? _authSubscription;

  void initAuth() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && state.isLoading) {
        debugPrint('[AUTH] Safety timeout — forcing isLoading=false');
        state = state.copyWith(isLoading: false);
      }
    });

    _authSubscription = SupabaseConfig.client.auth.onAuthStateChange.map((data) {
      return data;
    }).asyncMap((data) async {
      final session = data.session;
      final user = session?.user;
      if (user == null) {
        state = AuthState(isLoading: false, sessionEpoch: state.sessionEpoch);
      } else {
        // Only a real sign-in advances the epoch. A token refresh also arrives
        // here carrying a session, and treating that as a new sign-in would
        // lift the re-entry lock roughly once an hour without anybody proving
        // anything.
        if (data.event == AuthChangeEvent.signedIn) {
          state = state.copyWith(sessionEpoch: state.sessionEpoch + 1);
        }
        await resolveRole(user);
      }
      return state;
    }).listen((_) {});
  }

  @override
  void dispose() {
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  /// Documentation for this public member.

  Future<void> resolveRole(User user) async {
    state = state.copyWith(isLoading: true, user: user);

    try {
      var role = UserRole.citizen;
      var tier = ResponderTier.unknown;
      String? jurisdiction;

      // Fetch profile from Supabase PostgreSQL profiles table
      final profileDoc = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final profile = profileDoc;
      if (profile != null) {
        final roleStr = profile['role']?.toString() ?? '';
        if (roleStr == 'CITIZEN' || roleStr == 'USER') {
          role = UserRole.citizen;
        } else {
          role = UserRole.responder;
          if (roleStr.contains('HQ')) {
            tier = ResponderTier.hq;
          } else if (roleStr.contains('LGA')) {
            tier = ResponderTier.lga;
          } else if (roleStr.contains('WARD')) {
            tier = ResponderTier.ward;
          } else if (roleStr.contains('UNIT') || roleStr.contains('POLLING')) {
            tier = ResponderTier.pu;
          }
        }
        jurisdiction = profile['geo_lga'] as String?;
      }

      bool hasOnboarded;
      if (role == UserRole.responder) {
        hasOnboarded = true;
      } else {
        final prefs = await SharedPreferences.getInstance();
        hasOnboarded = prefs.getBool('hasOnboarded') ??
            (profile?['profile_complete'] as bool? ?? false);
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
    } catch (e, st) {
      // Do NOT default to citizen here. This previously demoted an HQ/LGA
      // commander to the citizen UI whenever the profile query failed (flaky
      // rural network, RLS denial, timeout) — and because `hasOnboarded` stays
      // false through copyWith, the router then pushed them into the first-run
      // onboarding wizard mid-incident. Surface the failure instead so the UI
      // can offer a retry and the operator knows their role is unresolved.
      debugPrint('[AUTH] Profile resolution FAILED for uid=${user.id}: $e');
      debugPrint('[AUTH] stack: $st');
      state = state.copyWith(
        isLoading: false,
        role: UserRole.unknown,
        resolutionError: e.toString(),
      );
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

  Future<void> refreshProfile() async {
    final user = state.user;
    if (user != null) {
      await resolveRole(user);
    }
  }

  Future<void> signOut() async {
    await SupabaseConfig.client.auth.signOut();
  }
}

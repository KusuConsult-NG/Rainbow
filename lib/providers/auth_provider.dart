import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/auth/last_known_role.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/services/mesh_service.dart';
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

/// Every staff role name this product has been deployed with, and its rung.
///
/// THERE ARE TWO VOCABULARIES, AND BOTH ARE LIVE.
///
/// The code was written against `*_COMMAND`. The production project's accounts
/// were created with `STATE_COMMANDER` / `LGA_COMMANDER` / `WARD_COMMANDER` /
/// `POLLING_UNIT_OFFICER` — 21 of its 22 staff accounts, none of which appears
/// anywhere in this repository.
///
/// The tier was decided by a chain of substring tests:
///
///     if (roleStr.contains('HQ'))        tier = hq;
///     else if (roleStr.contains('LGA'))  tier = lga;
///     else if (roleStr.contains('WARD')) tier = ward;
///     else if (roleStr.contains('UNIT') || roleStr.contains('POLLING')) …
///
/// Three of those four production names survive that by accident of spelling.
/// `STATE_COMMANDER` contains none of the four tokens, so it fell through to
/// `unknown` — and `assignedTierLabel(unknown)` is `'UNIT'`. Every HQ duty
/// officer was silently demoted to a polling unit, scoped to one ward, and
/// shown a board that was correct about the wrong jurisdiction. A citizen's
/// SOS and a building fire were on that project, in another ward, invisible,
/// with no error anywhere. See E2E_AUDIT_REPORT.md T-85.
///
/// Explicit names, so a rung is never decided by whether one string happens to
/// contain another. Adding a deployment's vocabulary here is the fix for that
/// deployment; the substring chain is kept below it only as a last resort, and
/// says so loudly when it fires.
const Map<String, ResponderTier> staffRoleTiers = <String, ResponderTier>{
  // The vocabulary this repository is written against.
  'HQ_COMMAND': ResponderTier.hq,
  'LGA_COMMAND': ResponderTier.lga,
  'WARD_COMMAND': ResponderTier.ward,
  'UNIT_COMMAND': ResponderTier.pu,

  // The vocabulary the production project's accounts actually carry.
  'STATE_COMMANDER': ResponderTier.hq,
  'LGA_COMMANDER': ResponderTier.lga,
  'WARD_COMMANDER': ResponderTier.ward,
  'POLLING_UNIT_OFFICER': ResponderTier.pu,

  // Staff who are deliberately outside the PU/WARD/LGA/HQ chain. `unknown`
  // means "no rung", which is what these are — not "unrecognised".
  'RESPONDER': ResponderTier.unknown,
  'POLICE_LIAISON': ResponderTier.unknown,
  'ARMY_LIAISON': ResponderTier.unknown,
};

/// The rung [roleStr] acts at, or null when nothing in this product knows it.
///
/// Null is the case worth caring about: it is a deployment carrying a role name
/// no release has heard of, which is exactly how an HQ commander came to be
/// shown a polling unit's board. The caller logs it; it must never be quietly
/// turned into the bottom of the chain.
ResponderTier? tierForStaffRole(String roleStr) {
  final key = roleStr.trim().toUpperCase();
  final mapped = staffRoleTiers[key];
  if (mapped != null) return mapped;

  // LAST RESORT, and loud. Kept so that a vocabulary nobody has added here
  // still gets a best-effort rung rather than being demoted to UNIT — but it
  // is a defect in this map, not a working feature, and the log says so.
  ResponderTier? guessed;
  if (key.contains('HQ') || key.contains('STATE')) {
    guessed = ResponderTier.hq;
  } else if (key.contains('LGA')) {
    guessed = ResponderTier.lga;
  } else if (key.contains('WARD')) {
    guessed = ResponderTier.ward;
  } else if (key.contains('UNIT') || key.contains('POLLING')) {
    guessed = ResponderTier.pu;
  }
  if (guessed != null) {
    debugPrint(
      '⚠️ [AUTH] role "$roleStr" is not in staffRoleTiers — guessed '
      '${guessed.name} from its spelling. Add it to the map: a rung decided '
      'by substring is how STATE_COMMANDER became a polling unit (T-85).',
    );
  }
  return guessed;
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
    this.roleFromCache = false,
    this.roleConfirmedAt,
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

  /// Whether [role] came from this handset's own record rather than the server.
  ///
  /// True means the app opened without being able to ask. The screens say so,
  /// because opening as who you were yesterday is only honest if it admits it —
  /// and a responder whose rung changed this morning needs to know this board
  /// may be the wrong one. T-100.
  final bool roleFromCache;

  /// When the server last confirmed this identity, when known.
  final DateTime? roleConfirmedAt;

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
    bool? roleFromCache,
    DateTime? roleConfirmedAt,
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
      roleFromCache: roleFromCache ?? this.roleFromCache,
      roleConfirmedAt: roleConfirmedAt ?? this.roleConfirmedAt,
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

  /// How long any one network step in resolution may take.
  ///
  /// The profile fetch had NO bound. `computeRedirect` holds the router on the
  /// splash while `isLoading` is true, so with no network the app sat there for
  /// as long as the operating system takes to give up on a TCP connection to an
  /// unreachable host — minutes on Android — in an app whose whole purpose is
  /// to work when the network does not. T-100.
  static const Duration resolveTimeout = Duration(seconds: 6);

  Timer? _loadingWatchdog;

  /// Re-armed every time the state enters loading.
  ///
  /// It used to be a single `Future.delayed` in the constructor. That cannot
  /// cover a SECOND entry into loading, and `resolveRole` is a second entry:
  /// by the time it set `isLoading = true` the one-shot had already fired, so
  /// nothing was watching the step that actually hung. A guard that runs once
  /// protects only the first case.
  void _armLoadingWatchdog() {
    _loadingWatchdog?.cancel();
    // Longer than `resolveTimeout` on purpose: this is the net under the
    // bounded steps, not a second bound on them. If it is what clears the
    // state, something awaited is unbounded and that is a defect, so it says
    // so rather than quietly recovering.
    _loadingWatchdog = Timer(resolveTimeout + const Duration(seconds: 4), () {
      if (mounted && state.isLoading) {
        debugPrint(
          '[AUTH] Loading watchdog fired. Every await in resolution is '
          'supposed to be bounded, so reaching this is a bug — but the app '
          'opens rather than sitting on the splash.',
        );
        state = state.copyWith(isLoading: false);
      }
    });
  }

  void initAuth() {
    _armLoadingWatchdog();

    // The subscription below is set up SYNCHRONOUSLY, inside this notifier's
    // constructor, which runs inside the `appRouter` provider, which is
    // `ref.watch`ed inside `RainbowApp.build`. So a throw from
    // `SupabaseConfig.client` here is a throw during the app's first build —
    // and in a release build that paints a pale rectangle with no text and
    // stops. That was the blank page an installed APK opened to.
    //
    // A missing backend client must not be able to kill the whole widget
    // tree. Report it as a resolution failure instead: the router already
    // knows how to read that (`computeRedirect`, the `resolutionError`
    // branch) and sends the user to the login screen, where the failure is
    // visible and recoverable, rather than to nothing at all.
    final SupabaseClient supabase;
    try {
      supabase = SupabaseConfig.client;
    } catch (error) {
      debugPrint('🔥 [AUTH] No Supabase client — cannot watch auth: $error');
      state = state.copyWith(
        isLoading: false,
        resolutionError: 'auth-unavailable: $error',
      );
      return;
    }

    _authSubscription = supabase.auth.onAuthStateChange.map((data) {
      return data;
    }).asyncMap((data) async {
      final session = data.session;
      final user = session?.user;
      if (user == null) {
        state = AuthState(isLoading: false, sessionEpoch: state.sessionEpoch);
        // A session that ended without signOut() — expiry, revocation — must
        // stop the Bluetooth mesh just as signing out does.
        unawaited(MeshService.instance.onSignedOut());
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
    _loadingWatchdog?.cancel();
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  /// Documentation for this public member.

  Future<void> resolveRole(User user) async {
    state = state.copyWith(isLoading: true, user: user);
    // Armed here as well as in initAuth: this is a SECOND entry into loading,
    // and the constructor's timer has long since fired by now. T-100.
    _armLoadingWatchdog();

    try {
      var role = UserRole.citizen;
      var tier = ResponderTier.unknown;
      String? jurisdiction;

      // BOUNDED. This had no timeout, and `computeRedirect` holds the router
      // on the splash while `isLoading` is true — so with no network the app
      // did not start at all, it waited out the OS TCP timeout on the splash
      // screen. In an app built for a place where the network fails. T-100.
      final profileDoc = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle()
          .timeout(resolveTimeout);

      final profile = profileDoc;
      if (profile != null) {
        final roleStr = profile['role']?.toString() ?? '';
        if (roleStr == 'CITIZEN' || roleStr == 'USER') {
          role = UserRole.citizen;
        } else {
          role = UserRole.responder;
          // One explicit map, not four substring tests. See staffRoleTiers:
          // STATE_COMMANDER contains none of HQ/LGA/WARD/UNIT/POLLING, so
          // every HQ duty officer on the production project fell through to
          // `unknown` — which assignedTierLabel renders as 'UNIT' — and was
          // shown a polling unit's board for one ward while a CRITICAL SOS
          // sat in another. T-85.
          final mapped = tierForStaffRole(roleStr);
          if (mapped != null) {
            tier = mapped;
          } else {
            debugPrint(
              '⚠️ [AUTH] role "$roleStr" is not a rung this release knows. '
              'Acting with NO tier rather than the bottom of the chain — a '
              'silent demotion to UNIT is what T-85 was.',
            );
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

      final confirmedAt = DateTime.now();
      state = AuthState(
        user: user,
        role: role,
        tier: tier,
        jurisdiction: jurisdiction,
        profile: profile,
        hasOnboarded: hasOnboarded,
        isLoading: false,
        roleConfirmedAt: confirmedAt,
      );
      // Recorded so the NEXT start can open without asking. Not awaited into
      // the state: a storage failure must not turn a successful resolution
      // into a failed one.
      unawaited(
        saveLastKnownRole(
          LastKnownRole(
            userId: user.id,
            role: role,
            tier: tier,
            jurisdiction: jurisdiction,
            hasOnboarded: hasOnboarded,
            savedAt: confirmedAt,
          ),
        ),
      );
      // The mesh needs the role: responders relay by default, citizens opt
      // in. Runs on every resolution, including token refreshes; starting an
      // already-running mesh is a no-op.
      unawaited(MeshService.instance.onSignedIn(isResponder: role == UserRole.responder));
    } catch (e, st) {
      // Do NOT default to citizen here. This previously demoted an HQ/LGA
      // commander to the citizen UI whenever the profile query failed (flaky
      // rural network, RLS denial, timeout) — and because `hasOnboarded` stays
      // false through copyWith, the router then pushed them into the first-run
      // onboarding wizard mid-incident. Surface the failure instead so the UI
      // can offer a retry and the operator knows their role is unresolved.
      debugPrint('[AUTH] Profile resolution FAILED for uid=${user.id}: $e');
      debugPrint('[AUTH] stack: $st');

      // ── OPEN AS WHO WE WERE, IF WE EVER KNEW ──
      //
      // This used to end here, with `resolutionError` set — and
      // `computeRedirect` reads a resolution error as terminal and sends the
      // user to the LOGIN SCREEN. Offline, that cannot succeed: the app
      // offered the one action that needs a network as the way out of having
      // no network.
      //
      // A handset that has resolved this account before knows what it was.
      // Using that is not a security decision — `is_command()` and the
      // row-level security built on it still refuse this handset everything it
      // is not entitled to, exactly as before. It decides which SCREEN opens,
      // and the cost of being wrong is a screen whose data will not load,
      // which is visible and recoverable. The cost of the old behaviour was
      // the panic button. T-100.
      final remembered = await readLastKnownRole(user.id);
      if (remembered != null) {
        debugPrint(
          "[AUTH] Opening from this handset's own record: "
          '${remembered.role.name}/${remembered.tier.name}, last confirmed '
          '${remembered.savedAt.toIso8601String()}',
        );
        state = AuthState(
          user: user,
          role: remembered.role,
          tier: remembered.tier,
          jurisdiction: remembered.jurisdiction,
          hasOnboarded: remembered.hasOnboarded,
          isLoading: false,
          roleFromCache: true,
          roleConfirmedAt: remembered.savedAt,
          // Kept, so a screen can say why it is working from a record. NOT
          // read by the router as terminal any more: a cached role IS a
          // resolved role for the purpose of choosing a screen.
          resolutionError: e.toString(),
        );
        return;
      }

      // Never resolved on this handset, so there is nothing to open as. Login
      // is the right destination: we do not know who this is.
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

  /// Documentation for this public member.
  Future<void> signOut() async {
    // Forgotten BEFORE the sign-out call, not after, and not only on success.
    //
    // `signOut()` reaches the network to revoke the token and throws when it
    // cannot. If the record were cleared after, signing out on a bad link
    // would leave the next person to pick up this handset able to open it as
    // the previous one — and in a command post this is a shared phone.
    // Clearing first costs a re-resolve for somebody who stays signed in
    // after a failed sign-out, which is the safe direction. T-100.
    await clearLastKnownRole();
    await SupabaseConfig.client.auth.signOut();
  }
}

/// Who this handset was signed in as last time, so the app can open offline.
///
/// ## Why this exists
///
/// The app did not start without a network. Not "worked in a reduced way" —
/// did not get past the splash screen.
///
/// A signed-in handset restores its session from local storage, which needs no
/// network. `AuthNotifier.resolveRole()` then set `isLoading = true` and issued
/// a PostgREST fetch of `profiles` with **no timeout**, and
/// `computeRedirect()` holds the router on the splash for as long as
/// `isLoading` is true. The only guard was a single
/// `Future.delayed(Duration(seconds: 5))` armed in the notifier's constructor —
/// which had already fired by the time `resolveRole` put the state back into
/// loading, and a one-shot timer cannot cover a second entry.
///
/// So with no network the app sat on the splash for however long the operating
/// system takes to give up on a TCP connection to an unreachable host — on
/// Android, minutes — and then, because the failure set `resolutionError`,
/// `computeRedirect` sent the user to the **login screen**, which offline
/// cannot succeed either. The app was unusable in precisely the conditions it
/// exists for.
///
/// Everything else in this product is built for that case: the offline alert
/// queue, the Bluetooth mesh, the encrypted SMS fallback, the USSD path. All of
/// it sits behind a screen the user could not reach.
///
/// ## Why caching the role is sound
///
/// This is not access control and must never be read as any. `profiles.role`
/// on the server, through `is_command()` and the row-level security built on
/// it, is what decides what anybody may actually read or write — a handset
/// claiming to be a commander gets refused by the database exactly as before.
/// What the cache decides is which SCREEN opens while offline, which is the
/// same class of decision as `console-access.ts` makes in the console: "hiding
/// a control is not access control — the database decides — but OFFERING one
/// that will be refused is its own defect".
///
/// Getting it wrong offline therefore costs a screen that cannot load its data,
/// which is visible and recoverable. Getting it wrong the old way cost the
/// panic button.
///
/// ## What is stored, and what deliberately is not
///
/// The rung, the jurisdiction (an LGA name), whether onboarding is done, and
/// when it was written — scoped to the user id it was resolved for, so one
/// person's handset can never open as somebody else.
///
/// NOT the profile row. That carries a full name, a phone number and a badge,
/// and this app is used in a conflict zone where a seized handset is a real
/// threat: the uninstall-request flow and the duress PIN exist because of it.
/// Nothing is cached here that was not already needed to choose a screen.
///
/// See E2E_AUDIT_REPORT.md T-100.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The identity this handset last resolved from the server.
@immutable
class LastKnownRole {
  /// Documentation for this public member.
  const LastKnownRole({
    required this.userId,
    required this.role,
    required this.tier,
    required this.hasOnboarded,
    required this.savedAt,
    this.jurisdiction,
  });

  /// The account this was resolved for. A cache is only ever used for the id
  /// it was written for.
  final String userId;

  /// Documentation for this public member.
  final UserRole role;

  /// Documentation for this public member.
  final ResponderTier tier;

  /// Documentation for this public member.
  final String? jurisdiction;

  /// Documentation for this public member.
  final bool hasOnboarded;

  /// When the server last confirmed this. Shown to the user, because opening
  /// as who you were yesterday is only honest if it says so.
  final DateTime savedAt;

  /// Documentation for this public member.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'userId': userId,
        'role': role.name,
        'tier': tier.name,
        'jurisdiction': jurisdiction,
        'hasOnboarded': hasOnboarded,
        'savedAt': savedAt.toUtc().toIso8601String(),
      };

  /// Null rather than a throw for anything unreadable.
  ///
  /// A cache written by an older release, hand-edited, or carrying a rung this
  /// build has never heard of must not be the reason the app fails to open —
  /// that would reintroduce the defect this file exists to fix, one layer in.
  static LastKnownRole? fromJson(Map<String, dynamic> json) {
    final userId = json['userId'] as String?;
    final roleName = json['role'] as String?;
    final savedRaw = json['savedAt'] as String?;
    if (userId == null || userId.isEmpty || roleName == null) return null;

    final role = UserRole.values.where((r) => r.name == roleName).firstOrNull;
    if (role == null) return null;
    final tier = ResponderTier.values
        .where((t) => t.name == (json['tier'] as String? ?? ''))
        .firstOrNull;
    final savedAt = savedRaw == null ? null : DateTime.tryParse(savedRaw);
    if (savedAt == null) return null;

    return LastKnownRole(
      userId: userId,
      role: role,
      tier: tier ?? ResponderTier.unknown,
      jurisdiction: json['jurisdiction'] as String?,
      hasOnboarded: json['hasOnboarded'] as bool? ?? false,
      savedAt: savedAt,
    );
  }
}

const String _key = 'lastKnownRole';

/// Records what the server said, so the next start can use it without asking.
///
/// Never throws: a storage failure must not turn a successful resolution into
/// a failed one.
Future<void> saveLastKnownRole(LastKnownRole identity) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(identity.toJson()));
  } on Object catch (e) {
    debugPrint('[AUTH_CACHE] could not store the resolved role: $e');
  }
}

/// What this handset last resolved for [userId], or null.
///
/// Scoped to the id on purpose. A handset that has been signed into by two
/// people must not open the second one as the first — and on a shared phone in
/// a command post, it will have been.
Future<LastKnownRole?> readLastKnownRole(String userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final identity = LastKnownRole.fromJson(decoded);
    if (identity == null || identity.userId != userId) return null;
    return identity;
  } on Object catch (e) {
    debugPrint('[AUTH_CACHE] could not read the stored role: $e');
    return null;
  }
}

/// Forgets it. Called on sign-out, so the next person to use this handset gets
/// the login screen rather than somebody else's board.
Future<void> clearLastKnownRole() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  } on Object catch (e) {
    debugPrint('[AUTH_CACHE] could not clear the stored role: $e');
  }
}

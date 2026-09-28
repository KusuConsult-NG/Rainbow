// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/offline/sms_device_key.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/secure_storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(secureStorageProvider));
});

/// Handles all authentication logic for Operation Rainbow users on Supabase.
class AuthService {
  AuthService(this._secureStorage);
  final SecureStorageService _secureStorage;

  String? _lastAuthError;
  String? _pendingPhone; // stores phone between step1 and step2

  /// Surface the last authentication error message
  String? get lastAuthError => _lastAuthError;

  /// Retrieves the current user ID
  String? get currentUserId {
    try {
      return SupabaseConfig.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  // ── CITIZEN PATH: Phone Auth with Demo Bypass ───────────────────────────────

  /// Legacy combined method (phone + otp in one call) — kept for backward compat
  Future<bool> signInWithPhone(String phoneNumber, String otpCode) async {
    _lastAuthError = null;

    final cleanPhone = phoneNumber.replaceAll(RegExp('[^0-9+]'), '');

    // Demo Citizen Bypass
    if (cleanPhone == '08000000000' ||
        cleanPhone == '2348000000000' ||
        cleanPhone == '+2348000000000') {
      try {
        final demoEmail = dotenv.env['DEMO_CITIZEN_EMAIL'];
        final demoPass  = dotenv.env['DEMO_CITIZEN_PASS'];
        if (demoEmail == null || demoPass == null) {
          _lastAuthError = 'DEMO_CITIZEN_EMAIL / DEMO_CITIZEN_PASS not configured in .env';
          return false;
        }
        final res = await SupabaseConfig.client.auth.signInWithPassword(
          email: demoEmail,
          password: demoPass,
        );
        return await _sessionEstablished(res.session);
      } catch (e) {
        _lastAuthError = e.toString();
        return false;
      }
    }

    try {
      final res = await SupabaseConfig.client.auth.verifyOTP(
        type: OtpType.sms,
        token: otpCode,
        phone: cleanPhone,
      );
      return await _sessionEstablished(res.session);
    } catch (e) {
      _lastAuthError = e.toString();
      return false;
    }
  }

  // ── AGENT PATH: Badge / Email Login ───────────────────────────────────────

  /// Authenticate agent with Badge ID / Email and Password
  Future<bool> signInWithBadge(String badgeOrEmail, String password) async {
    _lastAuthError = null;
    final trimmed = badgeOrEmail.trim().toLowerCase();
    final email = trimmed.contains('@')
        ? trimmed
        : '$trimmed@operationrainbow.plateau.gov.ng';

    try {
      final res = await SupabaseConfig.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return await _sessionEstablished(res.session);
    } catch (e) {
      _lastAuthError = e.toString();
      return false;
    }
  }

  Future<bool> signInWithAccessCode(String code) async {
    final cleanCode = code.trim().toLowerCase();
    final agentPass = dotenv.env['AGENT_DEFAULT_PASS'] ?? '';
    if (agentPass.isEmpty) {
      _lastAuthError = 'AGENT_DEFAULT_PASS not configured in .env';
      return false;
    }
    if (cleanCode.contains('@')) {
      return signInWithBadge(cleanCode, agentPass);
    }
    return signInWithBadge('$cleanCode@operationrainbow.plateau.gov.ng', agentPass);
  }

  static bool isDemoNumber(String phone) {
    final clean = phone.trim().replaceAll(RegExp('[^0-9+]'), '');
    return clean == '08000000000' ||
        clean == '2348000000000' ||
        clean == '+2348000000000';
  }

  // ── TWO-STEP CITIZEN FLOW ──────────────────────────────────────────────────

  /// Step 1: Store phone number and trigger OTP send (or flag demo bypass).
  Future<void> verifyPhoneNumber(String phone) async {
    _lastAuthError = null;
    final cleanPhone = phone.trim().replaceAll(RegExp('[^0-9+]'), '');
    _pendingPhone = cleanPhone;

    debugPrint('[AUTH] verifyPhoneNumber: $cleanPhone');

    if (isDemoNumber(cleanPhone)) {
      debugPrint('[AUTH] Demo phone detected — use OTP 123456');
      return;
    }

    // Real phones: send OTP via Supabase
    try {
      await SupabaseConfig.client.auth.signInWithOtp(phone: cleanPhone);
      debugPrint('[AUTH] OTP sent to $cleanPhone');
    } catch (e) {
      _lastAuthError = e.toString();
      debugPrint('[AUTH] OTP send failed: $e');
    }
  }

  /// Step 2: Verify OTP and create Supabase session.
  Future<bool> verifyOTP(String otp) async {
    _lastAuthError = null;
    final phone = _pendingPhone;

    if (phone == null) {
      _lastAuthError = 'SESSION EXPIRED — PLEASE RE-ENTER YOUR PHONE NUMBER';
      return false;
    }

    debugPrint('[AUTH] verifyOTP: phone=$phone otp=$otp');

    if (isDemoNumber(phone)) {
      // Demo citizen: only accept OTP 123456
      if (otp == '123456') {
        try {
          final demoEmail = dotenv.env['DEMO_CITIZEN_EMAIL'];
          final demoPass  = dotenv.env['DEMO_CITIZEN_PASS'];
          if (demoEmail == null || demoPass == null) {
            _lastAuthError = 'DEMO_CITIZEN_EMAIL / DEMO_CITIZEN_PASS not configured in .env';
            return false;
          }
          final res = await SupabaseConfig.client.auth.signInWithPassword(
            email: demoEmail,
            password: demoPass,
          );
          if (res.session != null) {
            _pendingPhone = null;
            return await _sessionEstablished(res.session);
          }
          _lastAuthError = 'DEMO LOGIN FAILED — CHECK SUPABASE CONFIGURATION';
          return false;
        } catch (e) {
          _lastAuthError = e.toString();
          return false;
        }
      } else {
        _lastAuthError = 'INVALID OTP — USE 123456 FOR DEMO';
        return false;
      }
    }

    // Real phone: verify via Supabase
    try {
      final res = await SupabaseConfig.client.auth.verifyOTP(
        type: OtpType.sms,
        token: otp,
        phone: phone,
      );
      if (res.session != null) {
        _pendingPhone = null;
        return await _sessionEstablished(res.session);
      }
      _lastAuthError = 'OTP VERIFICATION FAILED';
      return false;
    } catch (e) {
      _lastAuthError = e.toString();
      return false;
    }
  }

  /// Test seam: obtaining the SMS device key, which reaches secure storage and
  /// Supabase and so cannot run under `flutter test`.
  @visibleForTesting
  static Future<void> Function()? provisionSmsKeyOverride;

  /// Everything that has to happen once a session exists.
  ///
  /// THE OFFLINE CHANNELS ARE OBTAINED HERE OR NOT AT ALL.
  ///
  /// The SMS and mesh channels both authenticate with a per-device key that has
  /// to be fetched from the server. The whole point of them is that they work
  /// when there is no data connection, so the key cannot be fetched at the moment
  /// it is needed — by then there is nothing to fetch it over. Sign-in is the one
  /// moment the app is guaranteed to have both a session and a network, so this
  /// is where it happens.
  ///
  /// It runs on EVERY sign-in and costs one secure-storage read when a key is
  /// already held. Failure is never fatal and never blocks the sign-in: a handset
  /// with no key still works normally, it simply has one fewer way to reach HQ
  /// when the network dies. Saying so out loud matters, because the failure is
  /// silent until the night it counts.
  Future<bool> _sessionEstablished(Session? session) =>
      onSessionEstablished(session != null);

  /// The body of [_sessionEstablished], taking a bool rather than a `Session`.
  ///
  /// Split out only so it can be tested: constructing a real gotrue `Session` in
  /// a unit test means constructing a `User`, a token and an expiry, none of
  /// which this decision looks at. The production paths all go through
  /// [_sessionEstablished].
  @visibleForTesting
  Future<bool> onSessionEstablished(bool hasSession) async {
    if (!hasSession) return false;
    try {
      await (provisionSmsKeyOverride ??
          () async => SmsDeviceKeyService().ensureProvisioned())();
    } catch (e) {
      debugPrint('[SIGNIN_SMSKEY_ERR] could not obtain a device key: $e');
    }
    return true;
  }

  /// Test seam: BackgroundTrackingService talks to platform channels, which do
  /// not exist under `flutter test`.
  @visibleForTesting
  static Future<void> Function()? stopTrackingOverride;

  /// Test seam: the SMS key service reaches secure storage and Supabase.
  @visibleForTesting
  static Future<void> Function()? forgetSmsKeyOverride;

  /// Sign out user session.
  ///
  /// STOPPING LOCATION IS PART OF SIGNING OUT.
  ///
  /// This cleared the session and the secure storage and left the background
  /// location service running. Its keys live in SharedPreferences, which
  /// `deleteAll()` does not touch, and the isolate re-initialises Supabase by
  /// itself — so the phone carried on transmitting its position every few
  /// seconds under the signed-out user's uid, with the app showing a login
  /// screen. Signing out is the clearest statement a person can make that they
  /// are done being observed, and it was the one action that did not stop it.
  ///
  /// First, so that a failure below cannot leave tracking alive.
  Future<void> signOut() async {
    try {
      await (stopTrackingOverride ?? BackgroundTrackingService().stopTracking)();
    } catch (e) {
      debugPrint('[SIGNOUT_TRACKING_ERR] could not stop tracking: $e');
    }
    // And give up the SMS device key, for the same reason tracking stops: this
    // handset is no longer authorised to speak for that person, and the key
    // can both send an emergency in their name and decrypt the ones they send.
    try {
      await (forgetSmsKeyOverride ?? SmsDeviceKeyService().forget)();
    } catch (e) {
      debugPrint('[SIGNOUT_SMSKEY_ERR] could not retire the SMS key: $e');
    }
    await SupabaseConfig.client.auth.signOut();
    await _secureStorage.deleteAll();
    _pendingPhone = null;
  }
}

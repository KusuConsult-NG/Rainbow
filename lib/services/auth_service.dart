// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
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

    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');

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
        return res.session != null;
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
      return res.session != null;
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
      return res.session != null;
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
    final clean = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    return clean == '08000000000' ||
        clean == '2348000000000' ||
        clean == '+2348000000000';
  }

  // ── TWO-STEP CITIZEN FLOW ──────────────────────────────────────────────────

  /// Step 1: Store phone number and trigger OTP send (or flag demo bypass).
  Future<void> verifyPhoneNumber(String phone) async {
    _lastAuthError = null;
    final cleanPhone = phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
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
            return true;
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
        return true;
      }
      _lastAuthError = 'OTP VERIFICATION FAILED';
      return false;
    } catch (e) {
      _lastAuthError = e.toString();
      return false;
    }
  }

  /// Sign out user session
  Future<void> signOut() async {
    await SupabaseConfig.client.auth.signOut();
    await _secureStorage.deleteAll();
    _pendingPhone = null;
  }
}

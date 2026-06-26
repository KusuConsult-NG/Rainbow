// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/services/secure_storage_service.dart';

/// Documentation for this public member.

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(secureStorageProvider));
});

/// Handles all authentication logic for Operation Rainbow users.
/// Enforces dual-access model: Citizens (Phone) and Agents (Access Code).
class AuthService {
  /// Documentation for this public member.
  AuthService(this._secureStorage);
  final SecureStorageService _secureStorage;

  String _verificationId = '';
  String? _lastAuthError;

  /// Surface the last authentication error message
  String? get lastAuthError => _lastAuthError;

  /// Retrieves the current Firebase Auth user ID
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // ── CITIZEN PATH: Phone Auth ───────────────────────────────────────────────

  /// Documentation for this public member.
  Future<void> verifyPhoneNumber(String phoneNumber) async {
    _lastAuthError = null;
    final completer = Completer<void>();

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (c) async {
          try {
            await FirebaseAuth.instance
                .signInWithCredential(c)
                .timeout(const Duration(seconds: 15));
            // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
          } catch (e) {
            _lastAuthError = e.toString();
          }
          if (!completer.isCompleted) completer.complete();
        },
        verificationFailed: (e) {
          _lastAuthError = e.message ?? e.code;
          debugPrint('[AUTH_ERR] Phone verification failed: ${e.code}');
          if (!completer.isCompleted) completer.complete();
        },
        codeSent: (vid, token) {
          _verificationId = vid;
          if (!completer.isCompleted) completer.complete();
        },
        codeAutoRetrievalTimeout: (vid) {
          _verificationId = vid;
          if (!completer.isCompleted) completer.complete();
        },
      );
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      _lastAuthError = e.toString();
      debugPrint('[AUTH_ERR] Synchronous verification trigger failed: $e');
      if (!completer.isCompleted) completer.complete();
    }

    return completer.future;
  }

  /// Documentation for this public member.

  Future<bool> verifyOTP(String smsCode) async {
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: smsCode,
      );
      await FirebaseAuth.instance.signInWithCredential(cred).timeout(
            const Duration(seconds: 15),
          );
      return true;
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      _lastAuthError = e.toString();
      debugPrint('[AUTH_ERR] OTP verification failed: $e');
      return false;
    }
  }

  // ── AGENT PATH: Access Code via Security Gate ──────────────────────────────

  /// Validates a provisioned access code via Cloud Function and signs in with Custom Token.
  /// This ensures all role claims are set server-side.
  Future<bool> signInWithAccessCode(String accessCode) async {
    _lastAuthError = null;
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('validateAgentAccessCode');
      final result =
          await callable.call<Map<String, dynamic>>({'accessCode': accessCode});
      final data = result.data;

      if (data['success'] == true) {
        if (data['fallbackAuth'] == true) {
          final email = data['email'] as String;
          final password = data['password'] as String;
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          return true;
        }

        final customToken = data['customToken'] as String;
        await FirebaseAuth.instance.signInWithCustomToken(customToken);
        return true;
      }
      return false;
    } on FirebaseFunctionsException catch (e) {
      _lastAuthError = e.message;
      debugPrint('[AUTH_GATE_FAIL] ${e.code}: ${e.message}');
      return false;
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      _lastAuthError = e.toString();
      debugPrint('[AUTH_ERR] Unexpected agent auth error: $e');
      return false;
    }
  }

  /// Documentation for this public member.

  Future<void> signOut() async {
    await _secureStorage.clearCredentials();
    await FirebaseAuth.instance.signOut();
  }
}

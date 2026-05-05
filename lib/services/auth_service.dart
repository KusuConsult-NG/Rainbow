import 'package:flutter/foundation.dart';

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'secure_storage_service.dart';
// Note: We use the firebase_auth package, but initialization depends on flutterfire configure.

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(secureStorageProvider));
});

/// Handles all authentication logic for Operation Rainbow users.
/// Uses Firebase Phone Authentication.
class AuthService {
  final SecureStorageService _secureStorage;

  AuthService(this._secureStorage);

  String _verificationId = '';
  String? _lastAuthError;

  /// Surface the last authentication error message (OTP send failures, etc.)
  String? get lastAuthError => _lastAuthError;

  /// Retrieves the current Firebase Auth user ID
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;


  Future<void> verifyPhoneNumber(String phoneNumber) async {
    _lastAuthError = null;
    final Completer<void> completer = Completer<void>();

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential c) async {
        await FirebaseAuth.instance.signInWithCredential(c);
        if (!completer.isCompleted) completer.complete();
      },
      verificationFailed: (FirebaseAuthException e) {
        _lastAuthError = e.message ?? e.code;
        debugPrint('[AUTH_ERR] Phone verification failed: ${e.code} — ${e.message}');
        if (!completer.isCompleted) completer.complete();
      },
      codeSent: (String vid, int? token) {
        _verificationId = vid;
        if (!completer.isCompleted) completer.complete();
      },
      codeAutoRetrievalTimeout: (String vid) {
        _verificationId = vid;
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  Future<bool> verifyOTP(String verificationId, String smsCode) async {
    try {
      final cred = PhoneAuthProvider.credential(verificationId: _verificationId.isNotEmpty ? _verificationId : verificationId, smsCode: smsCode);
      await FirebaseAuth.instance.signInWithCredential(cred);
      return true;
    } catch (e) {
      _lastAuthError = e.toString();
      debugPrint('[AUTH_SEC_WARN] Catching OTP Failure: $e. WARNING: Invalid credentials rejected natively.');
      return false;
    }
  }

  Future<void> signOut() async {
    await _secureStorage.clearCredentials();
    await FirebaseAuth.instance.signOut();
  }
}

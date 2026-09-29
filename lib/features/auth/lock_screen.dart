// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit

/// The screen shown when the app has been left and picked up again.
///
/// It asks for a code sent to the number the account was created with. What it
/// does NOT do is stand between the person and the panic button: the emergency
/// action is on this screen, above the code box, and works whether or not
/// anybody has proved anything. See `lib/core/auth/reentry_lock.dart` for why
/// that is the right trade and not a hole.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/auth/phone_number.dart';
import 'package:rainbow_app/core/auth/reentry_lock.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/providers/reentry_lock_provider.dart';
import 'package:rainbow_app/services/auth_service.dart';

/// The re-entry lock screen.
class LockScreen extends ConsumerStatefulWidget {
  /// The re-entry lock screen.
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _otpController = TextEditingController();

  bool _sending = false;
  bool _checking = false;
  bool _codeSent = false;
  String? _message;
  UnlockPath _path = UnlockPath.codeBySms;

  @override
  void initState() {
    super.initState();
    unawaitedCheckConnection();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  /// Ask the radio once, so the screen can say what is actually possible.
  ///
  /// A connection is not proof that an SMS will arrive, and its absence IS
  /// proof that one will not, which is the direction that matters here.
  void unawaitedCheckConnection() {
    unawaited(
      Connectivity().checkConnectivity().then((results) {
        if (!mounted) return;
        final offline = results.isEmpty ||
            results.every((r) => r == ConnectivityResult.none);
        setState(() => _path = unlockPathFor(online: !offline));
      }).catchError((Object _) {
        // A radio we cannot read is not a reason to claim either state. Leave
        // the code path open and let the send itself fail with a real message.
      }),
    );
  }

  String get _number {
    final phone = ref.read(authProvider).user?.phone;
    if (phone == null || phone.isEmpty) return 'your number';
    final e164 = phone.startsWith('+') ? phone : '+$phone';
    return displayNigerianPhone(e164);
  }

  Future<void> _sendCode() async {
    final phone = ref.read(authProvider).user?.phone;
    if (phone == null || phone.isEmpty) {
      // No number on the account means no way to verify it. Signing out is the
      // only honest option, and saying so beats a button that does nothing.
      setState(
        () => _message = 'This account has no phone number on it. '
            'Sign out and sign in again.',
      );
      return;
    }

    setState(() {
      _sending = true;
      _message = null;
    });
    final auth = ref.read(authServiceProvider);
    final sent = await auth.verifyPhoneNumber(phone);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _codeSent = sent;
      _message = sent ? null : auth.lastAuthError;
      if (!sent) _path = unlockPathFor(online: false);
    });
  }

  Future<void> _check() async {
    final code = _otpController.text.trim();
    if (code.length < 6) return;

    setState(() {
      _checking = true;
      _message = null;
    });
    final auth = ref.read(authServiceProvider);
    final ok = await auth.verifyOTP(code);
    if (!mounted) return;

    if (ok) {
      ref.read(reentryLockProvider.notifier).unlock();
      final role = ref.read(authProvider).role;
      context.go(
        role == UserRole.responder ? AppRoutes.agentDashboard : AppRoutes.home,
      );
      return;
    }
    setState(() {
      _checking = false;
      _message = auth.lastAuthError ?? 'That code was not accepted.';
    });
  }

  Future<void> _raiseEmergency() async {
    // Deliberately before any verification. Whoever is holding this phone can
    // raise an alarm; that is the product.
    await ref.read(emergencyProvider.notifier).startEmergency();
    if (!mounted) return;
    context.go(AppRoutes.emergencyActive);
  }

  @override
  Widget build(BuildContext context) {
    final offline = _path == UnlockPath.emergencyOnly;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 56),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'WELCOME BACK',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  lockScreenExplanation(_path),
                  key: const ValueKey('lock_explanation'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 28),

                // The emergency action, ABOVE the code box, not below it.
                // Its position is the statement: nothing on this screen stands
                // in front of it.
                SizedBox(
                  height: 60,
                  child: ElevatedButton.icon(
                    key: const ValueKey('lock_sos'),
                    onPressed: _raiseEmergency,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.campaign_rounded),
                    label: Text(
                      'EMERGENCY — SEND SOS NOW',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Works whether or not you unlock.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppColors.textDim,
                    fontSize: 11,
                  ),
                ),

                const SizedBox(height: 32),
                const Divider(color: AppColors.outline),
                const SizedBox(height: 24),

                if (!offline) ...[
                  if (!_codeSent)
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        key: const ValueKey('lock_send_code'),
                        onPressed: _sending ? null : _sendCode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _sending ? 'SENDING…' : 'SEND MY CODE',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    )
                  else ...[
                    Text(
                      'CODE SENT TO $_number',
                      key: const ValueKey('lock_sent_to'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      key: const ValueKey('lock_otp_field'),
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                      ),
                      cursorColor: AppColors.primary,
                      decoration: InputDecoration(
                        hintText: '000000',
                        hintStyle: GoogleFonts.outfit(
                          color: AppColors.textDim,
                          letterSpacing: 8,
                        ),
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.surfaceContainer,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        key: const ValueKey('lock_unlock'),
                        onPressed: _checking ? null : _check,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _checking ? 'CHECKING…' : 'UNLOCK',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _sending ? null : _sendCode,
                      child: Text(
                        'SEND ANOTHER CODE',
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ] else
                  // Offline. Saying "try again" here would be asking the person
                  // to keep pulling a lever that is not connected to anything.
                  TextButton(
                    key: const ValueKey('lock_retry_connection'),
                    onPressed: unawaitedCheckConnection,
                    child: Text(
                      'CHECK FOR A CONNECTION AGAIN',
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),

                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _message!,
                    key: const ValueKey('lock_message'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                TextButton(
                  key: const ValueKey('lock_sign_out'),
                  onPressed: () async {
                    await ref.read(authProvider.notifier).signOut();
                    if (!context.mounted) return;
                    ref.read(reentryLockProvider.notifier).unlock();
                    context.go(AppRoutes.login);
                  },
                  child: Text(
                    'SIGN OUT INSTEAD',
                    style: GoogleFonts.outfit(
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

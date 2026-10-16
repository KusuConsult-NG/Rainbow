// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/auth/phone_number.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/auth_service.dart';
import 'package:rainbow_app/shared/widgets/build_stamp.dart';

/// Documentation for this public member.

class LoginScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _inputController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _otpSent = false;

  /// A badge or access code was typed, so a PASSWORD is now required.
  ///
  /// There was no password field on this screen at all. A non-phone input
  /// signed straight in with `AGENT_DEFAULT_PASS` out of the bundled `.env` —
  /// one password shared by every officer, shipping inside the APK as a Flutter
  /// asset and extracting with `unzip`. The access code was the username; the
  /// password was published. See AuthService.
  bool _needPassword = false;
  /// The badge or code being signed in with, kept while the password is typed.
  String? _staffIdentifier;
  /// The number the code went to, in the form the person wrote it.
  String? _sentTo;
  bool _loading = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    unawaited(_pulseController.repeat(reverse: true));
  }

  @override
  void dispose() {
    _inputController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handlePrimaryAction() async {
    if (_otpSent) {
      await _verifyOTP();
      return;
    }

    // Second step for staff: the password for the badge already entered.
    if (_needPassword) {
      final password = _passwordController.text;
      if (password.isEmpty) return;
      setState(() => _loading = true);
      await _submitStaffPassword(_staffIdentifier!, password);
      if (mounted) setState(() => _loading = false);
      return;
    }

    final input = _inputController.text.trim();
    if (input.isEmpty) return;

    // Heuristic: Detection of Phone vs Access Code
    // Phones usually start with + or are long numeric strings (8+ digits)
    if (_isLikelyPhone(input)) {
      setState(() => _loading = true);
      await _submitPhone(input);
      if (mounted) setState(() => _loading = false);
      return;
    }

    // A badge or access code. Ask for the password rather than signing in —
    // this is the step that did not exist, and its absence meant one published
    // password let anybody in as any officer whose code they knew or guessed.
    setState(() {
      _staffIdentifier = input;
      _needPassword = true;
    });
  }

  /// One field takes both a citizen's phone number and an officer's badge, so
  /// something has to decide which was typed.
  ///
  /// This used to require the input to be ALL digits after spaces were
  /// removed, so `0803-000-1111` — a perfectly ordinary way to write a number —
  /// was sent down the badge path and refused as an unknown access code. The
  /// person had typed their own number correctly.
  ///
  /// It now asks the phone reader, which understands every way the number is
  /// written. A badge (`HQ-001`) or an email has letters in it and can never be
  /// mistaken for a number. A `+` prefix counts as a phone even when the reader
  /// refuses it, so that someone entering a non-Nigerian number is told that,
  /// rather than being told their access code is invalid.
  bool _isLikelyPhone(String input) {
    final trimmed = input.trim();
    if (trimmed.contains('@') || RegExp('[A-Za-z]').hasMatch(trimmed)) {
      return false;
    }
    if (trimmed.startsWith('+')) return true;
    return readNigerianPhone(trimmed).isValid;
  }

  Future<void> _submitPhone(String phone) async {
    // `verifyPhoneNumber` used to return void, and this decided whether the
    // code had been sent by reading `lastAuthError` afterwards. When the send
    // failed silently — which is what happens when the project has no SMS
    // provider wired up, the commonest failure of all — the screen still
    // advanced, and the person sat in front of a box waiting for a code that
    // was never sent. It now says so.
    final auth = ref.read(authServiceProvider);
    final sent = await auth.verifyPhoneNumber(phone);
    if (!mounted) return;
    if (sent) {
      setState(() {
        _otpSent = true;
        _sentTo = auth.pendingPhoneForDisplay;
      });
    } else {
      _showTacticalError(auth.lastAuthError ?? 'THE CODE COULD NOT BE SENT.');
    }
  }

  Future<void> _submitStaffPassword(String identifier, String password) async {
    final success = await ref
        .read(authServiceProvider)
        .signInWithBadge(identifier, password);
    final error = ref.read(authServiceProvider).lastAuthError;

    if (mounted && !success) {
      // Deliberately does not say which of the two was wrong. Saying "no such
      // badge" would turn this screen into a roster of who works here.
      _showTacticalError(error ?? 'BADGE OR PASSWORD NOT RECOGNISED');
    }
  }

  Future<void> _verifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) return;

    setState(() => _loading = true);
    final success = await ref.read(authServiceProvider).verifyOTP(otp);
    final error = ref.read(authServiceProvider).lastAuthError;

    if (mounted) {
      setState(() => _loading = false);
      if (!success) {
        _showTacticalError(error ?? 'VERIFICATION FAILED');
      }
    }
  }

  void _showTacticalError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message.toUpperCase(),
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12),
        ),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 60),
                // ── Tactical HUD Header ──────────────────────────
                _buildTacticalLogo(),
                const SizedBox(height: 64),

                // ── Unified Input Section ────────────────────────
                Text(
                  _otpSent
                      ? 'IDENTITY VERIFICATION'
                      : _needPassword
                          ? 'STAFF PASSWORD'
                          : 'SECURE IDENTIFIER',
                  style: GoogleFonts.outfit(
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 1.5,
                  ),
                ),
                // Which number the code went to. Without it the screen asks
                // for a code and gives no way to notice that it went to a
                // mistyped number — the one mistake this screen invites.
                if (_otpSent && _sentTo != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'CODE SENT TO $_sentTo',
                    key: const ValueKey('otp_sent_to'),
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _otpSent
                      ? _buildOtpField()
                      : _needPassword
                          ? _buildPasswordField()
                          : _buildUnifiedField(),
                ),

                const SizedBox(height: 32),

                _buildActionButton(),

                if (_otpSent || _needPassword) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => setState(() {
                      _otpSent = false;
                      _sentTo = null;
                      _otpController.clear();
                      _needPassword = false;
                      _staffIdentifier = null;
                      _passwordController.clear();
                    }),
                    child: Text(
                      'BACK TO IDENTIFIER',
                      style: GoogleFonts.outfit(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                const BuildStamp(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTacticalLogo() {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) => Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.1),
                width: 4 * (1 - _pulseController.value),
              ),
            ),
          ),
        ),
        ScaleTransition(
          scale: Tween<double>(begin: 1, end: 1.02).animate(_pulseController),
          child: Hero(
            tag: 'app_logo',
            child: Image.asset(
              'assets/images/app_icon_large.png',
              width: 180,
              height: 180,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnifiedField() {
    return TextField(
      key: const ValueKey('unified_field'),
      controller: _inputController,
      style: GoogleFonts.outfit(
        color: Colors.black, // Explicitly black for visibility
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        hintText: 'PHONE OR ACCESS CODE',
        hintStyle:
            GoogleFonts.outfit(color: AppColors.textDim, letterSpacing: 1),
        prefixIcon: const Icon(Icons.vpn_key_rounded, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  /// The staff password. There was no such field on this screen.
  ///
  /// `obscureText` and `autocorrect: false` matter on a shared handset; so does
  /// NOT offering to remember it, because these devices are passed between
  /// shifts.
  Widget _buildPasswordField() {
    return TextField(
      key: const ValueKey('staff_password_field'),
      controller: _passwordController,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      textAlign: TextAlign.center,
      onSubmitted: (_) => _handlePrimaryAction(),
      style: GoogleFonts.outfit(
        color: Colors.black,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
      ),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        hintText: 'PASSWORD FOR ${_staffIdentifier?.toUpperCase() ?? 'BADGE'}',
        hintStyle: GoogleFonts.outfit(color: AppColors.textDim, fontSize: 12),
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildOtpField() {
    return TextField(
      key: const ValueKey('otp_field'),
      controller: _otpController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: GoogleFonts.outfit(
        color: Colors.black, // Explicitly black for visibility
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: 8,
      ),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        hintText: '000000',
        hintStyle:
            GoogleFonts.outfit(color: AppColors.textDim, letterSpacing: 8),
        counterText: '',
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: _loading ? null : _handlePrimaryAction,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
        ),
        child: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.white,
                ),
              )
            : Text(
                _otpSent
                    ? 'VERIFY OTP'
                    : _needPassword
                        ? 'SIGN IN'
                        : 'AUTHORIZE ACCESS',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
      ),
    );
  }
}

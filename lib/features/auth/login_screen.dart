import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  late AnimationController _shieldController;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Listen for automatic sign-ins (Test Numbers / Android Auto-Retrieval)
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null && mounted) {
        _authSubscription?.cancel();
        final prefs = await SharedPreferences.getInstance();
        final hasOnboarded = prefs.getBool('hasOnboarded') ?? false;
        if (mounted) {
          context.go(hasOnboarded ? AppRoutes.home : AppRoutes.onboardingPermissions);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    _shieldController.dispose();
    super.dispose();
  }

  void _processLogin() async {
    final input = _phoneController.text.trim();
    if (input.isEmpty) return;

    // Determine if it's an access code (contains letters) or a phone number.
    final isAccessCode = input.contains(RegExp(r'[A-Za-z]'));

    if (isAccessCode) {
      _processAgentLogin(input);
    } else {
      _sendOtp();
    }
  }

  void _processAgentLogin(String code) async {
    setState(() => _loading = true);

    try {
      final badgeId = code.toLowerCase();
      // Since they only entered an access code, use it as the password as well,
      // or use a unified fallback password pattern. For flexibility, we use the code.
      // (This matches standard "Access Code" patterns for field devices)
      final emailDomain = badgeId.contains('@') ? '' : '@operationrainbow.plateau.gov.ng';
      final formattedEmail = '$badgeId$emailDomain';
      
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: formattedEmail,
        password: badgeId, // Access Code serves as both ID and secure key.
      );

      if (cred.user != null) {
        await DeviceService().registerDeviceSession(cred.user!.uid);
        DeviceService().listenForForcedLogout(cred.user!.uid, () {
          if (mounted) context.go(AppRoutes.login);
        });
      }

      if (mounted) {
        setState(() => _loading = false);
        // Determine role from code pattern if needed, else default to Dashboard.
        // Wait, standard agents go to agentDashboard. We'll pass 'AGENT' as roleId.
        // The dashboard itself relies on Firestore user claims/roles.
        context.go(AppRoutes.agentDashboard, extra: 'AGENT');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid Access Code'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _sendOtp() async {
    if (_phoneController.text.length < 10) return;
    setState(() => _loading = true);
    
    await ref.read(authServiceProvider).verifyPhoneNumber(_phoneController.text.trim());

    final error = ref.read(authServiceProvider).lastAuthError;
    if (mounted) {
      setState(() { _loading = false; });
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send OTP: $error'), backgroundColor: Colors.red),
        );
      } else {
        setState(() { _otpSent = true; });
      }
    }
  }

  void _verifyOtp() async {
    if (_otpController.text.length < 6) return;
    setState(() => _loading = true);
    
    final success = await ref.read(authServiceProvider).verifyOTP('', _otpController.text.trim());
    final error = ref.read(authServiceProvider).lastAuthError;
    
    if (mounted) {
      setState(() => _loading = false);
      if (success) {
        _authSubscription?.cancel();
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // PRD §5 + §14: Device binding on citizen login
          await DeviceService().registerDeviceSession(user.uid);
          DeviceService().listenForForcedLogout(user.uid, () {
            if (mounted) context.go(AppRoutes.login);
          });
        }
        final prefs = await SharedPreferences.getInstance();
        final hasOnboarded = prefs.getBool('hasOnboarded') ?? false;
        if (!mounted) return;
        context.go(hasOnboarded ? AppRoutes.home : AppRoutes.onboardingPermissions);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification Failed: ${error ?? "Unknown Error"}'), duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          children: [
            // Header visual
            Expanded(
              flex: 2,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 16,
                    left: 16,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          // No longer falling back to roleSelection, just exit app
                          SystemNavigator.pop();
                        }
                      },
                    ),
                  ),
                  // Background glow
                  AnimatedBuilder(
                    animation: _shieldController,
                    builder: (_, __) => Container(
                      width: 280 + _shieldController.value * 30,
                      height: 280 + _shieldController.value * 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withAlpha((_shieldController.value * 15).toInt()),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_rounded, color: Colors.white, size: 100),
                      const SizedBox(height: 16),
                      Text(
                        'OPERATION RAINBOW',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'PLATEAU STATE EMERGENCY RESPONSE',
                        style: GoogleFonts.inter(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Login card
            Container(
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _otpSent ? 'Enter OTP' : 'Sign In',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _otpSent
                        ? 'Enter the 6-digit code sent to ${_phoneController.text}'
                        : 'Enter your registered phone number or assigned access code',
                    style: GoogleFonts.inter(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _otpSent
                        ? _buildOtpField()
                        : _buildUnifiedField(),
                  ),
                  const SizedBox(height: 20),

                  // Action button
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _loading ? null : (_otpSent ? _verifyOtp : _processLogin),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _otpSent ? 'VERIFY & CONTINUE' : 'SECURE LOGIN',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: 1.5,
                              ),
                            ),
                    ),
                  ),

                  if (_otpSent) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: () => setState(() => _otpSent = false),
                        child: Text(
                          'Change number',
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),



                  // Terms
                  Center(
                    child: Text(
                      'By continuing, you agree to Operation Rainbow\nTerms of Service & Privacy Policy',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppColors.outline,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedField() {
    return TextField(
      key: const ValueKey('phone_or_code'),
      controller: _phoneController,
      keyboardType: TextInputType.visiblePassword,
      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18),
      decoration: InputDecoration(
        hintText: '+234 800... or ACCESS-CODE',
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        prefixIcon: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Container(width: 1, height: 24, color: AppColors.outlineVariant),
              const SizedBox(width: 12),
            ],
          ),
        ),
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
      key: const ValueKey('otp'),
      controller: _otpController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w900,
        fontSize: 28,
        letterSpacing: 12,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: '——————',
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
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
}


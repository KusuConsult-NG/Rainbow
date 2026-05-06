import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';
import '../../services/device_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _credentialController = TextEditingController();
  final _secondaryController = TextEditingController();
  
  bool _secondarySent = false;
  bool _isAgentFlow = false;
  bool _loading = false;
  bool _obscurePassword = true;
  
  late AnimationController _pulseController;
  StreamSubscription<User?>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user != null && mounted) {
        _authSubscription?.cancel();
        final prefs = await SharedPreferences.getInstance();
        final hasOnboarded = prefs.getBool('hasOnboarded') ?? false;
        
        // Let's check if they are an agent or a citizen by checking users collection
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (!mounted) return;
        
        if (doc.exists && doc.data()?['role'] != null) {
          final role = doc.data()!['role'] as String;
          context.go(AppRoutes.agentDashboard, extra: role);
        } else {
          context.go(hasOnboarded ? AppRoutes.home : AppRoutes.onboardingPermissions);
        }
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _credentialController.dispose();
    _secondaryController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _submitCredential() async {
    final input = _credentialController.text.trim();
    if (input.isEmpty) return;
    
    // Check if phone or agent code (starts with + or contains only digits and spaces)
    final isPhone = RegExp(r'^\+?[0-9\s]+$').hasMatch(input);

    if (isPhone) {
      setState(() {
        _loading = true;
        _isAgentFlow = false;
      });
      await ref.read(authServiceProvider).verifyPhoneNumber(input);
      final error = ref.read(authServiceProvider).lastAuthError;
      if (mounted) {
        setState(() => _loading = false);
        if (error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $error'), backgroundColor: AppColors.primary),
          );
        } else {
          setState(() => _secondarySent = true);
        }
      }
    } else {
      // Agent flow
      setState(() {
        _isAgentFlow = true;
        _secondarySent = true;
      });
    }
  }

  void _verifySecondary() async {
    if (_secondaryController.text.isEmpty) return;
    setState(() => _loading = true);

    if (!_isAgentFlow) {
      final success = await ref.read(authServiceProvider).verifyOTP('', _secondaryController.text.trim());
      final error = ref.read(authServiceProvider).lastAuthError;
      if (mounted) {
        setState(() => _loading = false);
        if (success) {
          _authSubscription?.cancel();
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
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
            SnackBar(content: Text('Verification failed: ${error ?? "Please retry"}'), backgroundColor: AppColors.primary),
          );
        }
      }
    } else {
      // Agent login
      try {
        final badgeId = _credentialController.text.trim().toLowerCase();
        final cleanBadgeId = badgeId.startsWith('access-') ? badgeId.substring(7) : badgeId;
        final pin = _secondaryController.text;
        
        final emailDomain = cleanBadgeId.contains('@') ? '' : '@operationrainbow.plateau.gov.ng';
        final formattedEmail = '$cleanBadgeId$emailDomain';
        
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: formattedEmail,
          password: pin,
        );

        if (cred.user != null) {
          await DeviceService().registerDeviceSession(cred.user!.uid);
          DeviceService().listenForForcedLogout(cred.user!.uid, () {
            if (mounted) context.go(AppRoutes.login);
          });
          
          final doc = await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).get();
          final role = doc.data()?['role'] ?? 'HQ_OFFICER';
          
          if (mounted) {
            setState(() => _loading = false);
            context.go(AppRoutes.agentDashboard, extra: role);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Access denied.'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Stealth header with branding ──────────────────────────
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => Container(
                        width: 90 + _pulseController.value * 10,
                        height: 90 + _pulseController.value * 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(
                            (20 + _pulseController.value * 15).toInt(),
                          ),
                        ),
                        child: const Icon(
                          Icons.shield_rounded,
                          color: Colors.white,
                          size: 52,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'SECURE ACCESS',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'OPERATION RAINBOW',
                      style: GoogleFonts.inter(
                        color: Colors.white60,
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── White card at bottom ───────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _secondarySent ? (_isAgentFlow ? 'Authorization' : 'Verify Code') : 'Sign In',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      color: Colors.black87,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _secondarySent
                        ? (_isAgentFlow ? 'Enter your secure PIN' : 'Enter the 6-digit code sent to your phone')
                        : 'Enter your registered phone number or assigned access code',
                    style: GoogleFonts.inter(
                      color: Colors.black45,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _secondarySent 
                        ? (_isAgentFlow ? _buildPasswordField() : _buildOtpField()) 
                        : _buildCredentialField(),
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: _loading ? null : (_secondarySent ? _verifySecondary : _submitCredential),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primary.withAlpha(120),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _secondarySent ? 'VERIFY' : 'SECURE LOGIN',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                letterSpacing: 1.5,
                              ),
                            ),
                    ),
                  ),

                  if (_secondarySent) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _secondarySent = false;
                          _secondaryController.clear();
                        }),
                        child: Text(
                          'Change credential',
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      'By continuing, you agree to Operation Rainbow\nTerms of Service & Privacy Policy',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.black26,
                        fontSize: 11,
                        height: 1.6,
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

  Widget _buildCredentialField() {
    return TextField(
      key: const ValueKey('credential'),
      controller: _credentialController,
      keyboardType: TextInputType.text,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: '+234 800... or ACCESS-...',
        hintStyle: GoogleFonts.inter(color: Colors.black26, fontSize: 15),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        prefixIcon: const Icon(Icons.shield_rounded, color: AppColors.primary, size: 22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
    );
  }

  Widget _buildOtpField() {
    return TextField(
      key: const ValueKey('otp'),
      controller: _secondaryController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        color: AppColors.primary,
        fontWeight: FontWeight.w900,
        fontSize: 32,
        letterSpacing: 10,
      ),
      decoration: InputDecoration(
        counterText: '',
        hintText: '• • • • • •',
        hintStyle: GoogleFonts.inter(
          color: Colors.black12,
          fontSize: 28,
          letterSpacing: 8,
        ),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 20),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      key: const ValueKey('password'),
      controller: _secondaryController,
      keyboardType: TextInputType.text,
      obscureText: _obscurePassword,
      style: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: 'Enter PIN',
        hintStyle: GoogleFonts.inter(color: Colors.black26, fontSize: 15),
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.primary, size: 22),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.primary,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),
    );
  }
}

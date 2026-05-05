import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _fadeIn;

  int _statusIndex = 0;
  final List<String> _statusMessages = [
    'INITIALIZING ENCRYPTED PROTOCOL',
    'ESTABLISHING SECURE CHANNEL...',
    'VERIFYING SENTINEL GUARD v4.2...',
    'ALL SYSTEMS OPERATIONAL',
  ];

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _fadeIn = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    // Cycle status messages
    Timer.periodic(const Duration(milliseconds: 800), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_statusIndex < _statusMessages.length - 1) {
        setState(() => _statusIndex++);
      } else {
        timer.cancel();
        _verifyIdentityAndRoute();
      }
    });
  }

  void _verifyIdentityAndRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final hasOnboarded = prefs.getBool('hasOnboarded') ?? false;

    // Fix #5: .first hangs forever without internet — add 8s timeout, fall back to roleSelection
    FirebaseAuth.instance
        .authStateChanges()
        .first
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () => null,
        )
        .then((user) {
      if (!mounted) return;
      if (user != null) {
        context.go(hasOnboarded ? AppRoutes.home : AppRoutes.onboardingPermissions);
      } else {
        context.go(AppRoutes.login);
      }
    }).catchError((_) {
      // Any Firebase init error → send to login safely
      if (mounted) context.go(AppRoutes.login);
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: FadeTransition(
        opacity: _fadeIn,
        child: Stack(
          children: [
            // Background radial glow
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 1.0,
                    colors: [Color(0xFFD32F2F), Color(0xFF7A0B12)],
                  ),
                ),
              ),
            ),

            // Top-right light blob
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(20),
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  // Rotating ring + shield
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return SizedBox(
                        width: 200,
                        height: 200,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.rotate(
                              angle: _pulseController.value * 6.28318,
                              child: Container(
                                width: 190,
                                height: 190,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white.withAlpha(50),
                                    width: 3,
                                  ),
                                ),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(top: 4),
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 160,
                              height: 160,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withAlpha(20),
                              ),
                            ),
                            const Icon(
                              Icons.shield_rounded,
                              color: Colors.white,
                              size: 100,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 40),

                  // Title
                  Text(
                    'OPERATION',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 40,
                      letterSpacing: -1.5,
                      height: 1.0,
                    ),
                  ),
                  Text(
                    'RAINBOW',
                    style: GoogleFonts.inter(
                      color: Colors.white.withAlpha(229),
                      fontWeight: FontWeight.w900,
                      fontSize: 40,
                      letterSpacing: -1.5,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(height: 1, width: 30, color: Colors.white30),
                      const SizedBox(width: 12),
                      Text(
                        'PLATEAU STATE SECURITY RESPONSE',
                        style: GoogleFonts.inter(
                          color: Colors.white.withAlpha(178),
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(height: 1, width: 30, color: Colors.white30),
                    ],
                  ),

                  const Spacer(),

                  // Progress section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, _) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _progressController.value,
                                backgroundColor: Colors.white.withAlpha(25),
                                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                minHeight: 4,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.cell_tower, color: Colors.white54, size: 14),
                            const SizedBox(width: 8),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 400),
                              child: Text(
                                _statusMessages[_statusIndex],
                                key: ValueKey(_statusIndex),
                                style: GoogleFonts.inter(
                                  color: Colors.white54,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 9,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Bottom status bar
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(40),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withAlpha(13)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.tertiaryFixed,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.tertiaryFixed.withAlpha(128),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'NETWORK: CRITICAL ONLY',
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 9,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'SENTINEL GUARD v4.2',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontWeight: FontWeight.w700,
                            fontSize: 9,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
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
}

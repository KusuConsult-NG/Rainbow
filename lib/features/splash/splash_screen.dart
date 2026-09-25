import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/navigation_provider.dart';

/// Documentation for this public member.

class SplashScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
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
    );
    unawaited(_progressController.forward());

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_pulseController.repeat());

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    unawaited(_fadeController.forward());

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
        ref.read(splashFinishedProvider.notifier).state = true;
      }
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
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeIn,
        child: Stack(
          children: [
            // Top-right tactical glow
            Positioned(
              top: -150,
              right: -150,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.05),
                      AppColors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Main content
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  // High-Resolution Branding Mark
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 1.0 + (_pulseController.value * 0.05),
                        child: SizedBox(
                          width: 180,
                          height: 180,
                          child: Image.asset(
                            'assets/images/app_icon_large.png',
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      );
                    },
                  ),
                  const Spacer(),

                  // Tactical Status Feed
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 50),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _progressController,
                          builder: (context, _) {
                            return Stack(
                              children: [
                                Container(
                                  height: 2,
                                  width: double.infinity,
                                  color:
                                      AppColors.primary.withValues(alpha: 0.1),
                                ),
                                Container(
                                  height: 2,
                                  width: MediaQuery.of(context).size.width *
                                      0.7 *
                                      _progressController.value,
                                  color: AppColors.primary,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.security,
                              color: AppColors.primary,
                              size: 12,
                            ),
                            const SizedBox(width: 10),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              child: Text(
                                _statusMessages[_statusIndex],
                                key: ValueKey(_statusIndex),
                                style: GoogleFonts.inter(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.8),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 8,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),

                  // Footer Security Signature
                  Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'ENCRYPTION: AES-256',
                              style: GoogleFonts.inter(
                                color: AppColors.primary.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w800,
                                fontSize: 8,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'COMMAND v4.5.0',
                          style: GoogleFonts.inter(
                            color: AppColors.primary.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w800,
                            fontSize: 8,
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

/// Documentation for this public member.

class GridPainter extends CustomPainter {
  /// Documentation for this public member.
  GridPainter({required this.color});

  /// Documentation for this public member.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    const spacing = 40;

    for (double i = 0; i <= size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i <= size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

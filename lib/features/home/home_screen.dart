import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../providers/emergency_provider.dart';
import '../../shared/widgets/bottom_nav_bar.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/alert_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _safePulseController;

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat(reverse: true);

    _safePulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    ref.read(alertServiceProvider).flushOfflineQueue();

    Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) {
        ref.read(alertServiceProvider).flushOfflineQueue();
      }
    });
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _safePulseController.dispose();
    super.dispose();
  }

  void _triggerPanic({required bool silent}) {
    HapticFeedback.heavyImpact();
    ref.read(emergencyProvider.notifier).startEmergency();

    if (silent) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SILENT SOS ACTIVATED · SURVEILLANCE ACTIVE', 
            style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.0)),
          backgroundColor: AppColors.surfaceContainerHighest,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      context.go(AppRoutes.emergencyActive);
    }
  }

  String get _greetingContext {
    final hour = DateTime.now().hour;
    if (hour < 5 || hour > 22) return "LATE NIGHT · VIGILANCE MODE";
    if (hour < 12) return "GOOD MORNING · SYSTEMS READY";
    if (hour < 17) return "GOOD AFTERNOON · ALL CLEAR";
    return "GOOD EVENING · SECURE PERIMETER";
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'OPERATION RAINBOW',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 3.0,
              fontSize: 14,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white60),
              onPressed: () {},
            ),
            const SizedBox(width: 8),
          ],
        ),
      drawer: const _TacticalDrawer(),
      body: Stack(
        children: [
          // Background ambient pulse
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.5,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.03),
                    AppColors.background,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // TOP: Safety Status
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedBuilder(
                    animation: _safePulseController,
                    builder: (context, _) {
                      return Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primary,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(alpha: _safePulseController.value * 0.5),
                                        blurRadius: 12,
                                        spreadRadius: _safePulseController.value * 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SYSTEM NOMINAL',
                                      style: GoogleFonts.outfit(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _greetingContext,
                                      style: GoogleFonts.outfit(
                                        fontSize: 9,
                                        color: Colors.white38,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                Expanded(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _breathingController,
                      builder: (context, child) {
                        final scale = 1.0 + (_breathingController.value * 0.04);
                        return GestureDetector(
                          onTapDown: (_) => HapticFeedback.mediumImpact(),
                          onTap: () => _triggerPanic(silent: false),
                          onLongPress: () => _triggerPanic(silent: true),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer ripple
                              Container(
                                width: 300 * scale,
                                height: 300 * scale,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.emergency.withValues(alpha: 0.1 * (1 - _breathingController.value)),
                                    width: 2,
                                  ),
                                ),
                              ),
                              // Core button
                              Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 240,
                                  height: 240,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFFFF1744), Color(0xFF880E4F)],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.emergency.withValues(alpha: 0.2 + (_breathingController.value * 0.3)),
                                        blurRadius: 50,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                    border: Border.all(color: Colors.white24, width: 2),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.emergency_rounded, color: Colors.white, size: 64),
                                      const SizedBox(height: 12),
                                      Text(
                                        'SOS',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 42,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 6.0,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'HOLD FOR SILENT',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white60,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // BOTTOM: Report Action
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      context.push(AppRoutes.reportCategory);
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'INITIATE TACTICAL REPORT',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const SizedBox(width: 16),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
        bottomNavigationBar: const RainbowBottomNav(currentIndex: 0),
      ),
    );
  }
}

class _TacticalDrawer extends StatelessWidget {
  const _TacticalDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      width: MediaQuery.of(context).size.width * 0.8,
      child: Column(
        children: [
          _DrawerHeader(),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _DrawerTile(icon: Icons.shield_rounded, label: 'SECURITY HUB', onTap: () => context.push(AppRoutes.settings)),
                _DrawerTile(icon: Icons.history_edu_rounded, label: 'MISSION ARCHIVE', onTap: () => context.push(AppRoutes.incidentHistory)),
                _DrawerTile(icon: Icons.contact_emergency_rounded, label: 'EXTRACTION LIST', onTap: () => context.push(AppRoutes.onboardingContacts)),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: AppColors.white05, height: 1),
                ),
                _DrawerTile(
                  icon: Icons.power_settings_new_rounded, 
                  label: 'TERMINATE SESSION', 
                  color: AppColors.emergency, 
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('hasOnboarded', false);
                    if (context.mounted) context.go(AppRoutes.login);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'v1.4.2 · ENCRYPTED CONNECTION',
              style: GoogleFonts.outfit(
                color: Colors.white12,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 40),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: const Border(bottom: BorderSide(color: AppColors.white05)),
      ),
      child: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          final user = snapshot.data;
          final name = user?.displayName ?? 'OPERATIVE';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: Text(
                    name[0].toUpperCase(), 
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                name.toUpperCase(), 
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.0),
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? 'ID: RAINBOW-ALPHA', 
                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap; final Color? color;
  const _DrawerTile({required this.icon, required this.label, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    leading: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: (color ?? Colors.white).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color ?? Colors.white60, size: 20),
    ),
    title: Text(
      label, 
      style: GoogleFonts.outfit(
        color: color ?? Colors.white, 
        fontSize: 13, 
        fontWeight: FontWeight.w800, 
        letterSpacing: 1.0,
      ),
    ),
    onTap: onTap,
  );
}


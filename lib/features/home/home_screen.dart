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
    // Huge red panic button slow breathing
    _breathingController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat(reverse: true);

    // Subtle green dot pulse
    _safePulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);

    // Initial flush of offline queue
    ref.read(alertServiceProvider).flushOfflineQueue();

    // Listen for connectivity changes
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
    ref.read(emergencyProvider.notifier).startEmergency(); // we can pass silent param later if needed

    if (silent) {
      // In silent mode, we don't immediately change screens, but maybe show a tiny top snackbar.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Silent SOS Activated. We are tracking you.', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.surfaceContainerHighest,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      context.go(AppRoutes.emergencyActive);
    }
  }

  String get _greetingContext {
    final hour = DateTime.now().hour;
    if (hour < 5 || hour > 22) {
      return "Late night · We're keeping an eye out";
    } else if (hour < 12) {
      return "Good morning · Systems are active";
    } else if (hour < 17) {
      return "Good afternoon · Connections verified";
    } else {
      return "Good evening · You are secure";
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // On Android back press from home, minimize instead of crash
        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.primary),
          title: Text(
            'RainBow',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              letterSpacing: -0.5,
            ),
          ),
          centerTitle: true,
        ),
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.primary),
              child: StreamBuilder(
                stream: FirebaseAuth.instance.authStateChanges(),
                builder: (context, snapshot) {
                  final user = snapshot.data;
                  final name = user?.displayName ?? 'Citizen';
                  final photoUrl = user?.photoURL;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white,
                        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                        child: photoUrl == null
                            ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'C',
                                style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary))
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        name,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        user?.phoneNumber ?? 'Operation Rainbow Citizen',
                        style: GoogleFonts.inter(color: Colors.white.withAlpha(200), fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: AppColors.outline),
              title: Text('Settings', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () {
                context.pop();
                context.push(AppRoutes.settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: AppColors.outline),
              title: Text('Incident History', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () {
                context.pop();
                context.push(AppRoutes.incidentHistory);
              },
            ),
            ListTile(
              leading: const Icon(Icons.contacts_rounded, color: AppColors.outline),
              title: Text('Emergency Contacts', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onTap: () {
                context.pop();
                context.push(AppRoutes.onboardingContacts);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: Text('Log Out', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.redAccent)),
              onTap: () async {
                context.pop();
                // Actually sign out of Firebase
                await FirebaseAuth.instance.signOut();
                // Clear onboarded status so next user starts fresh
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('hasOnboarded', false);
                if (context.mounted) {
                  context.go(AppRoutes.login);
                }
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // TOP: Safety Status
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: AnimatedBuilder(
                animation: _safePulseController,
                builder: (context, _) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9), // softly green
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFC8E6C9), width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF4CAF50),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4CAF50).withAlpha((_safePulseController.value * 60 + 20).toInt()),
                                blurRadius: 12,
                                spreadRadius: _safePulseController.value * 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'You are safe',
                              style: GoogleFonts.inter(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF2E7D32),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _greetingContext,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF388E3C),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
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
                    final scale = 1.0 + (_breathingController.value * 0.08); // 8% scale bounce
                    final shadowOpacity = 50 + (_breathingController.value * 80).toInt();

                    return GestureDetector(
                      onTapDown: (_) => HapticFeedback.mediumImpact(),
                      onTap: () => _triggerPanic(silent: false),
                      onLongPressStart: (_) => HapticFeedback.heavyImpact(),
                      onLongPress: () => _triggerPanic(silent: true),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFD32F2F).withAlpha(shadowOpacity),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.shield_rounded, color: Colors.white, size: 64),
                              const SizedBox(height: 12),
                              Text(
                                'SOS',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.0,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap to Panic\nHold for Silent',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  color: Colors.white.withAlpha(200),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
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
                borderRadius: BorderRadius.circular(100),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Something feels wrong?',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Report',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
        bottomNavigationBar: const RainbowBottomNav(currentIndex: 0),
      ),
    );
  }
}

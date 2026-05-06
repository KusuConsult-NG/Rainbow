import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../providers/permissions_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class OnboardingPermissionsScreen extends ConsumerWidget {
  const OnboardingPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perms = ref.watch(permissionsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const OnboardingHeader(step: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.emergency.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.emergency.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.security_rounded, color: AppColors.emergency, size: 32),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TACTICAL CLEARANCE',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Establish operational permissions to enable field telemetry.',
                              style: GoogleFonts.outfit(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                  children: [
                    _TacticalPermCard(
                      icon: Icons.location_on_rounded,
                      title: 'GEOSPATIAL',
                      desc: 'Real-time location beacon',
                      value: perms.location,
                      onChanged: (_) => ref.read(permissionsProvider.notifier).toggle('location'),
                    ),
                    _TacticalPermCard(
                      icon: Icons.sms_rounded,
                      title: 'COMMS LINK',
                      desc: 'Offline SMS redundancy',
                      value: perms.sms,
                      onChanged: (_) => ref.read(permissionsProvider.notifier).toggle('sms'),
                    ),
                    _TacticalPermCard(
                      icon: Icons.mic_rounded,
                      title: 'FIELD AUDIO',
                      desc: 'Active evidence recording',
                      value: perms.audio,
                      onChanged: (_) => ref.read(permissionsProvider.notifier).toggle('audio'),
                    ),
                    _TacticalPermCard(
                      icon: Icons.battery_saver_rounded,
                      title: 'PERSISTENCE',
                      desc: 'Background session lock',
                      value: perms.persistence,
                      onChanged: (_) => ref.read(permissionsProvider.notifier).toggle('persistence'),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Center(
                  child: Text(
                    'CLEARANCE LEVEL: CITIZEN-ALPHA',
                    style: GoogleFonts.outfit(
                      color: Colors.white12,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: OnboardingBottomNav(
        onBack: () => context.go(AppRoutes.login),
        onNext: () async {
          await Permission.locationAlways.request();
          await Permission.sms.request();
          await Permission.microphone.request();
          await Permission.ignoreBatteryOptimizations.request();

          final locStatus = await Permission.locationAlways.status;
          final smsStatus = await Permission.sms.status;
          final micStatus = await Permission.microphone.status;

          if (locStatus.isGranted) ref.read(permissionsProvider.notifier).toggle('location');
          if (smsStatus.isGranted) ref.read(permissionsProvider.notifier).toggle('sms');
          if (micStatus.isGranted) ref.read(permissionsProvider.notifier).toggle('audio');
          ref.read(permissionsProvider.notifier).toggle('persistence');

          if (context.mounted) context.go(AppRoutes.onboardingProfile);
        },
        nextLabel: 'GRANT CLEARANCE',
      ),
    );
  }
}

class _TacticalPermCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TacticalPermCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: value ? AppColors.primary.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? AppColors.primary.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                icon,
                color: value ? AppColors.primary : Colors.white24,
                size: 28,
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: AppColors.primary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: GoogleFonts.outfit(
              fontSize: 10,
              color: Colors.white38,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingHeader extends StatelessWidget {
  final int step;
  const OnboardingHeader({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radio_button_checked_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 12),
              Text(
                'INITIALIZATION',
                style: GoogleFonts.outfit(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 2.0,
                ),
              ),
              const Spacer(),
              Text(
                'STEP $step / 3',
                style: GoogleFonts.outfit(
                  color: Colors.white38,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(3, (i) => Expanded(
              child: Container(
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                decoration: BoxDecoration(
                  color: i < step ? AppColors.primary : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: i < step ? [
                    BoxShadow(color: AppColors.primary.withValues(alpha: 0.5), blurRadius: 4)
                  ] : [],
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }
}

class OnboardingBottomNav extends StatelessWidget {
  final VoidCallback onBack;
  final Future<void> Function()? onNext;
  final String nextLabel;
  const OnboardingBottomNav({super.key, required this.onBack, required this.onNext, required this.nextLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                nextLabel,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

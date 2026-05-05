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
          // Progress header
          const OnboardingHeader(step: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                    const SizedBox(height: 16),
                    // Critical alert banner
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppColors.primaryContainer, AppColors.primary],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
                          const SizedBox(height: 10),
                          Text('CRITICAL PERMISSIONS', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: -0.3)),
                          const SizedBox(height: 6),
                          Text('These permissions power emergency features. Denying them may prevent alerts from reaching responders.', style: GoogleFonts.inter(color: Colors.white.withAlpha(220), fontSize: 13, height: 1.5)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.92,
                      children: [
                        _PermCard(icon: Icons.location_on_rounded, bg: const Color(0xFFE3F2FD), iconColor: AppColors.secondary, title: 'Location (Always)', desc: 'Required for accurate emergency dispatch and live tracking.', value: perms.location, onChanged: (_) => ref.read(permissionsProvider.notifier).toggle('location')),
                        _PermCard(icon: Icons.sms_rounded, bg: AppColors.errorContainer, iconColor: AppColors.primary, title: 'SMS Access', desc: 'Send alerts via SMS when internet is unavailable.', value: perms.sms, onChanged: (_) => ref.read(permissionsProvider.notifier).toggle('sms')),
                        _PermCard(icon: Icons.mic_rounded, bg: const Color(0xFFE8F5E9), iconColor: const Color(0xFF1B5E20), title: 'Microphone', desc: 'Auto-record audio evidence during active emergency.', value: perms.audio, onChanged: (_) => ref.read(permissionsProvider.notifier).toggle('audio')),
                        _PermCard(icon: Icons.battery_charging_full_rounded, bg: const Color(0xFFFFF8E1), iconColor: const Color(0xFFF57F17), title: 'Background Run', desc: 'Keep the app active for continuous tracking.', value: perms.persistence, onChanged: (_) => ref.read(permissionsProvider.notifier).toggle('persistence')),
                      ],
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
          // Request real OS-level permissions
          await Permission.locationAlways.request();
          await Permission.sms.request();
          await Permission.microphone.request();
          await Permission.ignoreBatteryOptimizations.request();

          // Update in-memory state to reflect actual OS grant outcome
          final locStatus = await Permission.locationAlways.status;
          final smsStatus = await Permission.sms.status;
          final micStatus = await Permission.microphone.status;

          ref.read(permissionsProvider.notifier);
          if (locStatus.isGranted) ref.read(permissionsProvider.notifier).toggle('location');
          if (smsStatus.isGranted) ref.read(permissionsProvider.notifier).toggle('sms');
          if (micStatus.isGranted) ref.read(permissionsProvider.notifier).toggle('audio');
          ref.read(permissionsProvider.notifier).toggle('persistence');

          if (context.mounted) context.go(AppRoutes.onboardingProfile);
        },
        nextLabel: 'GRANT ALL & CONTINUE',
      ),
    );
  }
}

class _PermCard extends StatelessWidget {
  final IconData icon; final Color bg, iconColor; final String title, desc; final bool value; final ValueChanged<bool> onChanged;
  const _PermCard({required this.icon, required this.bg, required this.iconColor, required this.title, required this.desc, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: value ? AppColors.primary.withAlpha(8) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: value ? AppColors.primary.withAlpha(80) : Colors.transparent, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: iconColor, size: 20)),
            Transform.scale(scale: 0.82, child: Switch(value: value, onChanged: onChanged)),
          ]),
          const Spacer(),
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, height: 1.2)),
          const SizedBox(height: 4),
          Text(desc, style: GoogleFonts.inter(fontSize: 10, color: AppColors.onSurfaceVariant, height: 1.4)),
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
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 16, 24, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Text('SETUP', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 2.0)),
              const Spacer(),
              Text('Step $step of 3', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: List.generate(3, (i) => Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              decoration: BoxDecoration(
                color: i < step ? AppColors.primary : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ))),
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
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, -5))]),
      child: Row(children: [
        OutlinedButton(
          onPressed: onBack,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: onNext,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: Text(nextLabel, style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1.5)),
          ),
        ),
      ]),
    );
  }
}

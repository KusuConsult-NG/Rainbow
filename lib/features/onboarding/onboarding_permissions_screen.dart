// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/permissions_provider.dart';
import 'package:rainbow_app/shared/widgets/location_disclosure_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Documentation for this public member.

class OnboardingPermissionsScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const OnboardingPermissionsScreen({super.key});

  @override
  ConsumerState<OnboardingPermissionsScreen> createState() =>
      _OnboardingPermissionsScreenState();
}

class _OnboardingPermissionsScreenState
    extends ConsumerState<OnboardingPermissionsScreen> {
  bool _isProcessing = false;

  Future<void> _handlePermissions() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      // 1. Check prominent location disclosure status before any native prompts
      final prefs = await SharedPreferences.getInstance();
      var isDisclosureAccepted =
          prefs.getBool('location_disclosure_accepted') ?? false;

      if (!isDisclosureAccepted) {
        if (!mounted) return;
        final accepted = await LocationDisclosureDialog.show(context);
        isDisclosureAccepted = accepted;
        if (!mounted) return;
      }

      // 2. PRD: High-Assurance Permission Acquisition (Location triggered only if disclosure was agreed)
      if (isDisclosureAccepted) {
        try {
          final locStatus = await Permission.location.request();
          if (locStatus.isGranted) {
            try {
              await Permission.locationAlways.request().timeout(
                    const Duration(seconds: 3),
                    onTimeout: () => PermissionStatus.denied,
                  );
            } catch (e) {
              debugPrint('[PERM_WARN] Background location request skipped: $e');
            }
          }
        } catch (e) {
          debugPrint('[PERM_ERR] Location permission request failed: $e');
        }
      } else {
        debugPrint(
          '[PERM_WARN] User declined location prominent disclosure, skipping native location request.',
        );
      }

      final locStatus = await Permission.location.status;
      final locAlwaysStatus = await Permission.locationAlways.status;

      if (!locStatus.isGranted && !locAlwaysStatus.isGranted) {
        if (mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.background,
              title: Text(
                'LOCATION REQUIRED',
                style: GoogleFonts.outfit(
                  color: AppColors.emergency,
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: Text(
                'Operation Rainbow requires location access to map emergency alerts to local responders. You cannot proceed without granting location permission.',
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                  },
                  child: Text(
                    'RETRY',
                    style: GoogleFonts.outfit(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await openAppSettings();
                  },
                  child: Text(
                    'OPEN SETTINGS',
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return;
      }

      await Permission.sms.request();
      await Permission.microphone.request();
      await Permission.ignoreBatteryOptimizations.request();

      final smsStatus = await Permission.sms.status;
      final micStatus = await Permission.microphone.status;

      if (!mounted) return;

      final perms = ref.read(permissionsProvider);

      // Force explicit provider state matching based on actual native permissions status
      if (locStatus.isGranted || locAlwaysStatus.isGranted) {
        if (!perms.location) {
          ref.read(permissionsProvider.notifier).toggle('location');
        }
      } else {
        if (perms.location) {
          ref.read(permissionsProvider.notifier).toggle('location');
        }
      }

      if (smsStatus.isGranted) {
        if (!perms.sms) ref.read(permissionsProvider.notifier).toggle('sms');
      } else {
        if (perms.sms) ref.read(permissionsProvider.notifier).toggle('sms');
      }

      if (micStatus.isGranted) {
        if (!perms.audio) {
          ref.read(permissionsProvider.notifier).toggle('audio');
        }
      } else {
        if (perms.audio) ref.read(permissionsProvider.notifier).toggle('audio');
      }

      // Ensure persistence toggles correctly based on user state
      ref.read(permissionsProvider.notifier).toggle('persistence');

      context.go(AppRoutes.onboardingProfile);
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[PERM_ERR] Authorization failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PERMISSION SYSTEM FAILURE: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = ref.watch(permissionsProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          children: [
            const OnboardingHeader(step: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.emergency.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.emergency.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.security_rounded,
                          color: AppColors.emergency,
                          size: 32,
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TACTICAL CLEARANCE',
                                style: GoogleFonts.outfit(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Establish operational permissions to enable field telemetry.',
                                style: GoogleFonts.outfit(
                                  color: AppColors.textSecondary,
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
                        onChanged: (_) => ref
                            .read(permissionsProvider.notifier)
                            .toggle('location'),
                      ),
                      _TacticalPermCard(
                        icon: Icons.sms_rounded,
                        title: 'COMMS LINK',
                        desc: 'Offline SMS redundancy',
                        value: perms.sms,
                        onChanged: (_) => ref
                            .read(permissionsProvider.notifier)
                            .toggle('sms'),
                      ),
                      _TacticalPermCard(
                        icon: Icons.mic_rounded,
                        title: 'FIELD AUDIO',
                        desc: 'Active evidence recording',
                        value: perms.audio,
                        onChanged: (_) => ref
                            .read(permissionsProvider.notifier)
                            .toggle('audio'),
                      ),
                      _TacticalPermCard(
                        icon: Icons.battery_saver_rounded,
                        title: 'PERSISTENCE',
                        desc: 'Background session lock',
                        value: perms.persistence,
                        onChanged: (_) => ref
                            .read(permissionsProvider.notifier)
                            .toggle('persistence'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: Text(
                      'CLEARANCE LEVEL: STANDARD',
                      style: GoogleFonts.outfit(
                        color: AppColors.textDim,
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
      ),
      bottomNavigationBar: OnboardingBottomNav(
        onBack: () => context.go(AppRoutes.login),
        onNext: _isProcessing ? null : _handlePermissions,
        nextLabel: _isProcessing ? 'AUTHORIZING...' : 'GRANT CLEARANCE',
      ),
    );
  }
}

class _TacticalPermCard extends StatelessWidget {
  const _TacticalPermCard({
    required this.icon,
    required this.title,
    required this.desc,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final String desc;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: value
            ? AppColors.primary.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.outline,
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
                color: value ? AppColors.primary : AppColors.textDim,
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
              color: AppColors.onBackground,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: GoogleFonts.outfit(
              fontSize: 10,
              color: AppColors.textDim,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Documentation for this public member.

class OnboardingHeader extends StatelessWidget {
  /// Documentation for this public member.
  const OnboardingHeader({required this.step, super.key});

  /// Documentation for this public member.
  final int step;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 16,
        24,
        24,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.radio_button_checked_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                'INITIALIZATION',
                style: GoogleFonts.outfit(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                'STEP $step / 3',
                style: GoogleFonts.outfit(
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(
              3,
              (i) => Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  decoration: BoxDecoration(
                    color: i < step ? AppColors.primary : AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: i < step
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ]
                        : [],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Documentation for this public member.

class OnboardingBottomNav extends StatelessWidget {
  /// Documentation for this public member.
  const OnboardingBottomNav({
    required this.onBack,
    required this.onNext,
    required this.nextLabel,
    super.key,
  });

  /// Documentation for this public member.
  final VoidCallback onBack;

  /// Documentation for this public member.
  final VoidCallback? onNext;

  /// Documentation for this public member.
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.outline),
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.onBackground,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
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

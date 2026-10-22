import 'dart:async';
// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/permissions_provider.dart';
import 'package:rainbow_app/shared/widgets/language_picker.dart';
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

  /// The key that says this handset has already been through setup.
  ///
  /// Checked in [initState] so a returning user never sees this screen twice.
  /// It is the screen, not the OS prompt, that is skipped: the OS remembers
  /// its own grants, and re-showing an explainer for a decision already made
  /// is the kind of thing that makes people close an app they need.
  static const String _grantedKey = 'permissions_granted';

  @override
  void initState() {
    super.initState();
    unawaited(_skipIfAlreadyGranted());
  }

  Future<void> _skipIfAlreadyGranted() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getBool(_grantedKey) ?? false) {
      context.go(AppRoutes.emergencyPins, extra: {'onboarding': true});
    }
  }

  /// ONE prompt, and then into the app.
  ///
  /// What this replaced, and why. The old flow asked four times in sequence:
  /// a prominent-disclosure modal, then `Permission.location.request()`, then
  /// `Permission.locationAlways.request()` behind a 3-second timeout, then
  /// three more `.request()` calls one after another. Two things were wrong
  /// with that beyond the tapping:
  ///
  ///   * The 3-second timeout raced the OS. `locationAlways` on Android 11+
  ///     does not show a dialog at all — it sends the user to Settings — so
  ///     the timeout fired on a prompt that was never coming, and the next
  ///     `.request()` went out while the OS still had one open. Android
  ///     answers a second request made while one is in flight by denying it
  ///     without asking.
  ///   * A denied location BLOCKED setup — an unskippable "You cannot proceed
  ///     without granting location permission" dialog, and `return`. A person
  ///     who declines once could not use the app at all, which for a duress
  ///     alarm is the worst possible failure: the one who most needs to send
  ///     a silent alert is the one most likely to refuse a location prompt
  ///     the first time somebody is watching.
  ///
  /// Now: `[...].request()` — permission_handler's batch form, which hands
  /// the OS one request for the lot and lets it present a single flow. Every
  /// outcome continues to the PIN screen. Location is asked for here because
  /// an alert without coordinates is a report nobody can reach; it is not a
  /// gate, and `AlertService` already handles a report that has none.
  ///
  /// `locationAlways` is deliberately NOT requested. Background tracking runs
  /// inside a foreground service with its own notification, which needs only
  /// foreground location, and asking for it here is what produced the second
  /// dialog and the race.
  Future<void> _handlePermissions() async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      // One call, one flow. The screen above the button IS the prominent
      // disclosure — the user has read why location is wanted and tapped to
      // agree before anything native appears, which is what the policy asks
      // for and what the separate modal was doing less well.
      final results = await [
        Permission.location,
        Permission.sms,
        Permission.microphone,
        Permission.ignoreBatteryOptimizations,
      ].request();

      final locationGranted =
          results[Permission.location]?.isGranted ?? false;
      final smsGranted = results[Permission.sms]?.isGranted ?? false;
      final micGranted = results[Permission.microphone]?.isGranted ?? false;

      if (!mounted) return;

      // Keep the in-app toggles honest about what the OS actually said, so
      // Settings does not show a switch on for a permission that is off.
      final perms = ref.read(permissionsProvider);
      if (locationGranted != perms.location) {
        ref.read(permissionsProvider.notifier).toggle('location');
      }
      if (smsGranted != perms.sms) {
        ref.read(permissionsProvider.notifier).toggle('sms');
      }
      if (micGranted != perms.audio) {
        ref.read(permissionsProvider.notifier).toggle('audio');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_grantedKey, true);
      // The disclosure was shown on this screen and accepted by tapping.
      await prefs.setBool('location_disclosure_accepted', true);

      if (!mounted) return;
      context.go(AppRoutes.emergencyPins, extra: {'onboarding': true});
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[PERM_ERR] the permission request failed: $e');
      if (!mounted) return;
      // A failure here must not strand anybody in setup either. Say so, and
      // carry on: every permission can be granted later from Settings, and
      // none of them is needed to reach the SOS button.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SOME PERMISSIONS COULD NOT BE SET. YOU CAN GRANT THEM IN SETTINGS.',
          ),
        ),
      );
      context.go(AppRoutes.emergencyPins, extra: {'onboarding': true});
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
                  // FIRST, on the first screen of setup. Everything below this
                  // is read by somebody who may not read English, and the only
                  // language control used to be a flag button on the home
                  // screen — which is three screens past here.
                  const LanguagePicker(),
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
                  const SizedBox(height: 24),
                  // Said plainly, on the screen that asks for the most. This
                  // app takes a phone number and nothing else: no name, no
                  // NIN, no next of kin. Somebody deciding whether to let an
                  // emergency app see where they are deserves to know that
                  // before they decide, not in a policy they will not read.
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.emerald.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: AppColors.emeraldDeep,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You stay anonymous. No personal data is collected '
                            '\u2014 your phone number is your only identity in '
                            'this app, and it is there so responders can reach '
                            'you.',
                            style: GoogleFonts.outfit(
                              color: AppColors.emeraldDeep,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
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
                'STEP $step / 2',
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
              2,
              (i) => Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 1 ? 8 : 0),
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

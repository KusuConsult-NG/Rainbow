// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/features/home/widgets/voice_report_dialog.dart';
import 'package:rainbow_app/models/alert_model.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/services/alert_service.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/shared/widgets/broadcast_hud.dart';

/// Documentation for this public member.

class HomeScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late AnimationController _safePulseController;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  // Cache tracking state — do NOT call platform channel inside AnimatedBuilder (60fps)
  bool _isTracking = false;

  Future<void> _refreshTrackingState() async {
    try {
      final running = await FlutterBackgroundService().isRunning();
      if (mounted) setState(() => _isTracking = running);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    unawaited(_breathingController.repeat(reverse: true));

    _safePulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_safePulseController.repeat(reverse: true));

    // Initial sync
    unawaited(ref.read(alertServiceProvider).flushOfflineQueue());
    unawaited(_refreshTrackingState());

    // Listen for connectivity restoration
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((result) {
      if (!mounted) return;
      if (!result.contains(ConnectivityResult.none)) {
        unawaited(ref.read(alertServiceProvider).flushOfflineQueue());
      }
    });
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _safePulseController.dispose();
    unawaited(_connectivitySubscription?.cancel());
    super.dispose();
  }

  Future<void> _triggerPanic({required bool silent}) async {
    await HapticFeedback.heavyImpact();

    final hasPermission = await LocationService().requestPermission(force: true);
    if (!hasPermission) {
      if (mounted) {
        unawaited(showDialog<void>(
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
              'Operation Rainbow requires active location permissions to route emergency responders to your position. Please enable location in device settings.',
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'OK',
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
                  'SETTINGS',
                  style: GoogleFonts.outfit(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),);
      }
      return;
    }

    unawaited(ref.read(emergencyProvider.notifier).startEmergency());
    if (silent) {
      // Silent SOS: submit a real background alert without leaving the home screen
      unawaited(() async {
        try {
          final pos = await LocationService().getCurrentPosition(force: true);
          await ref.read(alertServiceProvider).submitAlert(
                type: 'EMERGENCY - Silent SOS',
                description: 'Silent distress signal activated by user.',
                reportedBy:
                    ref.read(authProvider).user?.id ?? 'anonymous',
                latitude: pos?.latitude,
                longitude: pos?.longitude,
                priority: AlertPriority.critical,
              );
          // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
        } catch (e) {
          debugPrint('[SILENT_SOS] Alert creation failed: $e');
        }
      }());

      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'SILENT SOS ACTIVATED · SURVEILLANCE ACTIVE',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
          backgroundColor: AppColors.surfaceContainerHighest,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      if (!context.mounted) return;
      // ignore: use_build_context_synchronously
      context.go(AppRoutes.emergencyActive);
    }
  }

  String _getGreetingContext(AppLanguage lang) {
    final hour = DateTime.now().hour;
    if (hour < 5 || hour > 22) return Translations.get('late_night', lang);
    if (hour < 12) return Translations.get('good_morning', lang);
    if (hour < 17) return Translations.get('good_afternoon', lang);
    return Translations.get('good_evening', lang);
  }


  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isStaff = auth.role != UserRole.citizen;
    final userId = auth.user?.id ?? 'unknown';
    final lang = ref.watch(languageProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon:
                  const Icon(Icons.menu_rounded, color: AppColors.onBackground),
              onPressed: () {
                var state = Scaffold.maybeOf(context);
                if (state != null && !state.hasDrawer) {
                  final parent = Scaffold.maybeOf(state.context);
                  if (parent != null) state = parent;
                }
                state?.openDrawer();
              },
            ),
          ),
          // Scale to fit rather than clip. At 390px the 14px title with 3px
          // letter-spacing rendered as "OPERATION RAI…" — the app's own name,
          // truncated, on the first screen a citizen sees.
          title: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Translations.get('title', lang),
              maxLines: 1,
              softWrap: false,
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                fontSize: 14,
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
                child: PopupMenuButton<AppLanguage>(
                  padding: EdgeInsets.zero,
                  offset: const Offset(0, 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          lang.flagLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.primary,
                          size: 14,
                        ),
                      ],
                    ),
                  ),
                  onSelected: (selected) async {
                    await HapticFeedback.selectionClick();
                    await ref.read(languageProvider.notifier).setLanguage(selected);
                  },
                  itemBuilder: (context) => AppLanguage.values.map((l) {
                    return PopupMenuItem<AppLanguage>(
                      value: l,
                      child: Row(
                        children: [
                          Text(
                            l.flagLabel,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            l.label,
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.textSecondary,
              ),
              onPressed: () {
                unawaited(HapticFeedback.lightImpact());
                unawaited(context.push(AppRoutes.incidentHistory));
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            // Background ambient pulse
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
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
                  const BroadcastHud(),
                  const SizedBox(height: 12),
                  // TOP: Safety Status / Patrol Status
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: AnimatedBuilder(
                      animation: _safePulseController,
                      builder: (context, _) {
                        // Use cached _isTracking — never call a platform channel here (60fps)
                        final isTracking = _isTracking;
                        final statusColor = isTracking
                            ? AppColors.success
                            : AppColors.primary;

                            return Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(color: AppColors.outline),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(32),
                                child: BackdropFilter(
                                  filter:
                                      ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: statusColor,
                                          boxShadow: [
                                            BoxShadow(
                                              color: statusColor.withValues(
                                                alpha:
                                                    _safePulseController.value *
                                                        0.5,
                                              ),
                                              blurRadius: 12,
                                              spreadRadius:
                                                  _safePulseController.value *
                                                      4,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isTracking
                                                ? Translations.get('patrol_active', lang)
                                                : Translations.get('system_nominal', lang),
                                            style: GoogleFonts.outfit(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.primary,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            isTracking
                                                ? Translations.get('telemetry_stable', lang)
                                                : _getGreetingContext(lang),
                                            style: GoogleFonts.outfit(
                                              fontSize: 9,
                                              color: AppColors.textDim,
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

                  if (isStaff) ...[
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: InkWell(
                        onTap: () async {
                          unawaited(HapticFeedback.mediumImpact());
                          if (_isTracking) {
                            await BackgroundTrackingService().stopTracking();
                          } else {
                            await BackgroundTrackingService()
                                .startResponderTracking(userId);
                          }
                          // Refresh cached state after toggle instead of re-calling Future in build
                          unawaited(_refreshTrackingState());
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: _isTracking
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.surfaceContainer,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isTracking
                                  ? AppColors.success.withValues(alpha: 0.3)
                                  : AppColors.outline,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isTracking
                                    ? Icons.radar_rounded
                                    : Icons.radio_button_off_rounded,
                                color: _isTracking
                                    ? AppColors.success
                                    : AppColors.textDim,
                              ),
                              const SizedBox(width: 16),
                              Text(
                                _isTracking
                                    ? Translations.get('end_patrol', lang)
                                    : Translations.get('activate_patrol', lang),
                                style: GoogleFonts.outfit(
                                  color: _isTracking
                                      ? AppColors.success
                                      : AppColors.onBackground,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              const Spacer(),
                              if (_isTracking)
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.success,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedBuilder(
                              animation: _breathingController,
                              builder: (context, child) {
                                final scale =
                                    1.0 + (_breathingController.value * 0.04);
                                return GestureDetector(
                                  onTapDown: (_) => HapticFeedback.mediumImpact(),
                                  onTap: () => _triggerPanic(silent: true),
                                  onLongPress: () => _triggerPanic(silent: false),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Outer ripple
                                      Container(
                                        width: 220 * scale,
                                        height: 220 * scale,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.1 *
                                                  (1 - _breathingController.value),
                                            ),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      // Core button
                                      Transform.scale(
                                        scale: scale,
                                        child: Container(
                                          width: 170,
                                          height: 170,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFFFF1744),
                                                Color(0xFF880E4F),
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primary.withValues(
                                                  alpha: 0.2 +
                                                      (_breathingController.value *
                                                          0.3),
                                                ),
                                                blurRadius: 35,
                                                spreadRadius: 4,
                                              ),
                                            ],
                                            border: Border.all(
                                              color: Colors.white24,
                                              width: 2,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.emergency_rounded,
                                                color: Colors.white,
                                                size: 44,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                'SOS',
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 4,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                Translations.get('silent_sos', lang),
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white60,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 1,
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
                            const SizedBox(height: 24),
                            AnimatedBuilder(
                              animation: _breathingController,
                              builder: (context, child) {
                                final scale =
                                    1.0 + (_breathingController.value * 0.04);
                                return GestureDetector(
                                  onTapDown: (_) => HapticFeedback.mediumImpact(),
                                  onTap: () {
                                    unawaited(VoiceReportDialog.show(context));
                                  },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Outer ripple
                                      Container(
                                        width: 220 * scale,
                                        height: 220 * scale,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.info.withValues(
                                              alpha: 0.1 *
                                                  (1 - _breathingController.value),
                                            ),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                      // Core button
                                      Transform.scale(
                                        scale: scale,
                                        child: Container(
                                          width: 170,
                                          height: 170,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            gradient: const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Color(0xFF3F51B5),
                                                Color(0xFF00BCD4),
                                              ],
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.info.withValues(
                                                  alpha: 0.2 +
                                                      (_breathingController.value *
                                                          0.3),
                                                ),
                                                blurRadius: 35,
                                                spreadRadius: 4,
                                              ),
                                            ],
                                            border: Border.all(
                                              color: Colors.white24,
                                              width: 2,
                                            ),
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.mic_rounded,
                                                color: Colors.white,
                                                size: 44,
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                Translations.get('ai_report', lang),
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 2,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                Translations.get('speak_to_report', lang),
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white60,
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 1,
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
                          ],
                        ),
                      ),
                    ),
                  ),

                  // BOTTOM: Safe Zone & Report Action
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () {
                            unawaited(HapticFeedback.selectionClick());
                            unawaited(context.push(AppRoutes.safeZone));
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppColors.success.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.shield_rounded,
                                  size: 16,
                                  color: AppColors.success,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  Translations.get('safe_zone', lang),
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.success,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        InkWell(
                          onTap: () {
                            unawaited(HapticFeedback.selectionClick());
                            unawaited(context.push(AppRoutes.reportCategory));
                          },
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 20,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  Translations.get('report_incident', lang),
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.primary,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 12,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
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

// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/services/location_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_map.dart';
import 'package:rainbow_app/shared/widgets/safety_feedback_dialog.dart';

/// Documentation for this public member.

class EmergencyActiveScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const EmergencyActiveScreen({super.key});

  @override
  ConsumerState<EmergencyActiveScreen> createState() =>
      _EmergencyActiveScreenState();
}

class _EmergencyActiveScreenState extends ConsumerState<EmergencyActiveScreen>
    with TickerProviderStateMixin {
  Timer? _tickTimer;
  late AnimationController _cancelController;
  late AnimationController _pulseController;
  Timer? _cancelTimer;

  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _cancelController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_pulseController.repeat(reverse: true));

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) ref.read(emergencyProvider.notifier).tick();
    });

    unawaited(
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _showMap = true);
          unawaited(HapticFeedback.lightImpact());
        }
      }),
    );
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _cancelTimer?.cancel();
    _cancelController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _startCancel() {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_cancelController.forward());
    _cancelTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      unawaited(_cancelController.reverse());
      _showPinVerification();
    });
  }

  void _stopCancel() {
    _cancelTimer?.cancel();
    unawaited(_cancelController.reverse());
  }

  void _showPinVerification() {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => _TacticalPinVerification(
          onVerified: () async {
            if (!mounted) return;
            final alertId = ref.read(emergencyProvider).alertId;
            await showSafetyFeedback(context, alertId: alertId);
            if (mounted) context.go(AppRoutes.home);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emergencyState = ref.watch(emergencyProvider);
    final locAsync = ref.watch(userLocationStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Ambient Emergency Glow
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.5,
                      colors: [
                        AppColors.emergency
                            .withValues(alpha: 0.15 * _pulseController.value),
                        AppColors.background,
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                _buildHeader(emergencyState.elapsedSeconds),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        _buildStatusCard(),
                        const SizedBox(height: 24),
                        Expanded(child: _buildTacticalMap(locAsync)),
                        const SizedBox(height: 24),
                        _buildTelemetryGrid(locAsync),
                      ],
                    ),
                  ),
                ),

                // Dispatcher Chat button for citizen
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: _DispatcherChatButton(),
                ),

                _buildCancelControl(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    final timerStr =
        '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EMERGENCY ACTIVE',
                style: GoogleFonts.outfit(
                  color: AppColors.emergency,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              Text(
                'LIVE TELEMETRY',
                style: GoogleFonts.outfit(
                  color: AppColors.textDim,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.emergency.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.emergency.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.emergency,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  timerStr,
                  style: GoogleFonts.outfit(
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: AppColors.glassSurface,
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: _showMap
                ? Column(
                    key: const ValueKey('alerted'),
                    children: [
                      Text(
                        'LOCATION BROADCASTING',
                        style: GoogleFonts.outfit(
                          color: AppColors.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Operational teams are inbound to your position',
                        style: GoogleFonts.outfit(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('signal'),
                    children: [
                      Text(
                        'SIGNAL ESTABLISHED',
                        style: GoogleFonts.outfit(
                          color: AppColors.onBackground,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Establishing tactical data link...',
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
    );
  }

  Widget _buildTacticalMap(AsyncValue<Position?> locAsync) {
    return AnimatedOpacity(
      opacity: _showMap ? 1.0 : 0.0,
      duration: const Duration(seconds: 1),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: AppColors.glassBorder,
          boxShadow: [
            BoxShadow(
              color: AppColors.emergency.withValues(alpha: 0.05),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            locAsync.when(
              data: (pos) => pos != null
                  ? RainbowMap(
                      center: LatLng(pos.latitude, pos.longitude),
                      initialZoom: 17,
                      interactive: false,
                    )
                  : Container(color: AppColors.surface),
              loading: () => ColoredBox(
                color: AppColors.surface,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        color: AppColors.emergency,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'SCANNING FOR SIGNAL...',
                        style: GoogleFonts.outfit(
                          color: AppColors.emergency,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              error: (_, __) => Container(color: AppColors.surface),
            ),
            // Tactical Scanning Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.6),
                    Colors.transparent,
                    AppColors.background.withValues(alpha: 0.6),
                  ],
                ),
              ),
            ),
            // Pulse at center
            const Center(
              child: _PulseMarker(color: AppColors.emergency),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryGrid(AsyncValue<Position?> locAsync) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          _TelemetryItem(
            label: 'LATITUDE',
            value: locAsync.when(
              data: (pos) => pos?.latitude.toStringAsFixed(5) ?? '---',
              loading: () => '---',
              error: (_, __) => 'ERR',
            ),
          ),
          _TelemetryItem(
            label: 'LONGITUDE',
            value: locAsync.when(
              data: (pos) => pos?.longitude.toStringAsFixed(5) ?? '---',
              loading: () => '---',
              error: (_, __) => 'ERR',
            ),
          ),
          _TelemetryItem(
            label: 'ACCURACY',
            value: locAsync.when(
              data: (pos) => pos != null ? '${pos.accuracy.toInt()}m' : '---',
              loading: () => '---',
              error: (_, __) => 'ERR',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelControl() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onLongPressStart: (_) => _startCancel(),
        onLongPressEnd: (_) => _stopCancel(),
        onLongPressCancel: _stopCancel,
        child: AnimatedBuilder(
          animation: _cancelController,
          builder: (context, _) {
            return Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: Color.lerp(
                    AppColors.outline,
                    AppColors.emergency,
                    _cancelController.value,
                  )!,
                ),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: _cancelController.value,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.emergency.withValues(alpha: 0.2),
                              AppColors.emergency.withValues(alpha: 0.5),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.security,
                        color: _cancelController.value > 0.5
                            ? Colors.white
                            : AppColors.textDim,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _cancelController.value > 0.1
                            ? 'VERIFYING SAFETY...'
                            : 'HOLD TO CANCEL SOS',
                        style: GoogleFonts.outfit(
                          color: _cancelController.value > 0.5
                              ? Colors.white
                              : AppColors.onBackground,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 1.5,
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
    );
  }
}

class _TelemetryItem extends StatelessWidget {
  const _TelemetryItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: AppColors.textDim,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: AppColors.onBackground,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalPinVerification extends ConsumerStatefulWidget {
  const _TacticalPinVerification({required this.onVerified});
  final VoidCallback onVerified;

  @override
  ConsumerState<_TacticalPinVerification> createState() =>
      _TacticalPinVerificationState();
}

class _TacticalPinVerificationState
    extends ConsumerState<_TacticalPinVerification> {
  String pin = '';

  @override
  Widget build(BuildContext context) {
    final pinLength = dotenv.env['SAFE_PIN']?.length ?? 4;
    final horizontalMargin = pinLength > 4 ? 8.0 : 16.0;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: MediaQuery.of(context).viewInsets.bottom + 48,
        ),
        decoration: BoxDecoration(
          color: AppColors.background.withValues(alpha: 0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'SECURITY VERIFICATION',
              style: GoogleFonts.outfit(
                color: AppColors.emergency,
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enter tactical PIN to confirm safety status',
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 40),

            // PIN Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pin.length > pinLength ? pin.length : pinLength,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < pin.length
                        ? AppColors.emergency
                        : AppColors.outline,
                    boxShadow: index < pin.length
                        ? [
                            BoxShadow(
                              color: AppColors.emergency.withValues(alpha: 0.5),
                              blurRadius: 10,
                            ),
                          ]
                        : [],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),

            // Numpad
            _buildNumpad(),
          ],
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var j = 1; j <= 3; j++) _buildKey(i * 3 + j),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 80),
            _buildKey(0),
            _buildBackspace(),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(int number) {
    final pinLength = dotenv.env['SAFE_PIN']?.length ?? 4;
    return GestureDetector(
      onTap: () async {
        unawaited(HapticFeedback.lightImpact());
        final currentPin = pin + number.toString();
        
        final safePin = dotenv.env['SAFE_PIN'];
        final duressPin = dotenv.env['DURESS_PIN'];

        if (safePin == null && duressPin == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No PIN configured in environment.')),
          );
          return;
        }

        // 1. Submit immediately if it matches the correct SAFE_PIN, DURESS_PIN
        if (currentPin == safePin || currentPin == duressPin) {
          setState(() => pin = currentPin);
          final verified = await ref
              .read(emergencyProvider.notifier)
              .verifyCancellation(currentPin);
          if (!mounted) return;
          if (verified) {
            Navigator.of(context).pop();
            widget.onVerified();
          } else {
            unawaited(HapticFeedback.vibrate());
            setState(() => pin = '');
          }
          return;
        }

        // 2. Otherwise handle typing increments
        if (currentPin.length == pinLength) {
          setState(() => pin = currentPin);
          final verified = await ref
              .read(emergencyProvider.notifier)
              .verifyCancellation(currentPin);
          if (!mounted) return;
          if (verified) {
            Navigator.of(context).pop();
            widget.onVerified();
          } else {
            unawaited(HapticFeedback.vibrate());
            setState(() => pin = '');
          }
        } else if (currentPin.length < pinLength) {
          // Allow typing to continue
          setState(() => pin = currentPin);
        } else {
          // Length exceeded or wrong input path
          unawaited(HapticFeedback.vibrate());
          setState(() => pin = '');
        }
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.03),
          border: Border.all(color: AppColors.outline),
        ),
        child: Center(
          child: Text(
            number.toString(),
            style: GoogleFonts.outfit(
              color: AppColors.onBackground,
              fontSize: 32,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspace() {
    return GestureDetector(
      onTap: () {
        unawaited(HapticFeedback.lightImpact());
        if (pin.isNotEmpty) {
          setState(() => pin = pin.substring(0, pin.length - 1));
        }
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: const Center(
          child: Icon(
            Icons.backspace_outlined,
            color: AppColors.textSecondary,
            size: 28,
          ),
        ),
      ),
    );
  }
}

/// Fetches the user's most recent open alert and opens the dispatcher chat.
class _DispatcherChatButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertId = ref.watch(emergencyProvider).alertId;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: alertId == null
            ? null
            : () {
                unawaited(
                  context.push(AppRoutes.dispatcherChat, extra: alertId),
                );
              },
        icon: const Icon(Icons.headset_mic_rounded, size: 18),
        label: Text(
          alertId == null ? 'AWAITING DISPATCH LINK' : 'CONTACT HQ DISPATCHER',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.5,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: BorderSide(
            color: AppColors.accent.withValues(alpha: 0.4),
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _PulseMarker extends StatefulWidget {
  const _PulseMarker({required this.color});
  final Color color;

  @override
  State<_PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    unawaited(_controller.repeat());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 60 * _controller.value,
              height: 60 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withValues(alpha: 1 - _controller.value),
                  width: 2,
                ),
              ),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.5),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

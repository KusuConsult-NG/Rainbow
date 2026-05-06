import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../providers/emergency_provider.dart';
import '../../shared/widgets/rainbow_map.dart';
import '../../shared/widgets/safety_feedback_dialog.dart';
import '../../services/location_service.dart';
import 'package:latlong2/latlong.dart';

class EmergencyActiveScreen extends ConsumerStatefulWidget {
  const EmergencyActiveScreen({super.key});

  @override
  ConsumerState<EmergencyActiveScreen> createState() => _EmergencyActiveScreenState();
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
        vsync: this, duration: const Duration(seconds: 3));

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) ref.read(emergencyProvider.notifier).tick();
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showMap = true);
        HapticFeedback.lightImpact();
      }
    });
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
    HapticFeedback.mediumImpact();
    _cancelController.forward();
    _cancelTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      _cancelController.reverse();
      _showPinVerification();
    });
  }

  void _stopCancel() {
    _cancelTimer?.cancel();
    _cancelController.reverse();
  }

  void _showPinVerification() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => _TacticalPinVerification(
        onVerified: () {
          context.go(AppRoutes.home);
          Future.delayed(const Duration(milliseconds: 600), () {
            if (!mounted) return;
            showSafetyFeedback(context);
          });
        },
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
                        AppColors.emergency.withValues(alpha: 0.15 * _pulseController.value),
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
                    padding: const EdgeInsets.all(24.0),
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
    final timerStr = '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';

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
                  color: Colors.white24,
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
              border: Border.all(color: AppColors.emergency.withValues(alpha: 0.3)),
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
                    color: Colors.white,
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
                        'Responders are inbound to your position',
                        style: GoogleFonts.outfit(
                          color: Colors.white54,
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
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Establishing tactical data link...',
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
    );
  }

  Widget _buildTacticalMap(AsyncValue locAsync) {
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
              data: (pos) => RainbowMap(
                center: LatLng(pos.latitude, pos.longitude),
                initialZoom: 17.0,
                interactive: false,
              ),
              loading: () => Container(color: Colors.black),
              error: (_, __) => Container(color: Colors.black),
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

  Widget _buildTelemetryGrid(AsyncValue locAsync) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          _TelemetryItem(
            label: 'LATITUDE',
            value: locAsync.when(
              data: (pos) => pos.latitude.toStringAsFixed(5),
              loading: () => '---',
              error: (_, __) => 'ERR',
            ),
          ),
          _TelemetryItem(
            label: 'LONGITUDE',
            value: locAsync.when(
              data: (pos) => pos.longitude.toStringAsFixed(5),
              loading: () => '---',
              error: (_, __) => 'ERR',
            ),
          ),
          _TelemetryItem(
            label: 'ACCURACY',
            value: locAsync.when(
              data: (pos) => '${pos.accuracy.toInt()}m',
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
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: Color.lerp(
                    Colors.white.withValues(alpha: 0.1),
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
                        color: _cancelController.value > 0.5 ? Colors.white : Colors.white24,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _cancelController.value > 0.1 
                          ? 'VERIFYING SAFETY...' 
                          : 'HOLD TO CANCEL SOS',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
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
  final String label;
  final String value;

  const _TelemetryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white24,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalPinVerification extends StatefulWidget {
  final VoidCallback onVerified;

  const _TacticalPinVerification({required this.onVerified});

  @override
  State<_TacticalPinVerification> createState() => _TacticalPinVerificationState();
}

class _TacticalPinVerificationState extends State<_TacticalPinVerification> {
  String pin = '';

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 32,
            bottom: MediaQuery.of(context).viewInsets.bottom + 48,
          ),
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
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
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 40),
              
              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < pin.length ? AppColors.emergency : Colors.white10,
                    boxShadow: index < pin.length ? [
                      BoxShadow(
                        color: AppColors.emergency.withValues(alpha: 0.5),
                        blurRadius: 10,
                      )
                    ] : [],
                  ),
                )),
              ),
              const SizedBox(height: 48),

              // Numpad
              _buildNumpad(ref),
            ],
          ),
        ),
      );
    });
  }

  Widget _buildNumpad(WidgetRef ref) {
    return Column(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var j = 1; j <= 3; j++) _buildKey(i * 3 + j, ref),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const SizedBox(width: 80),
            _buildKey(0, ref),
            _buildBackspace(),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(int number, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        HapticFeedback.lightImpact();
        if (pin.length < 4) {
          setState(() => pin += number.toString());
          if (pin.length == 4) {
            final verified = await ref.read(emergencyProvider.notifier).verifyCancellation(pin);
            if (!mounted) return;
            if (verified) {
              Navigator.of(context).pop();
              widget.onVerified();
            } else {
              HapticFeedback.vibrate();
              setState(() => pin = '');
            }
          }
        }
      },
      child: Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.03),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Center(
          child: Text(
            number.toString(),
            style: GoogleFonts.outfit(
              color: Colors.white,
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
        HapticFeedback.lightImpact();
        if (pin.isNotEmpty) {
          setState(() => pin = pin.substring(0, pin.length - 1));
        }
      },
      child: Container(
        width: 80, height: 80,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: const Center(
          child: Icon(Icons.backspace_outlined, color: Colors.white54, size: 28),
        ),
      ),
    );
  }
}

class _PulseMarker extends StatefulWidget {
  final Color color;
  const _PulseMarker({required this.color});

  @override
  State<_PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
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

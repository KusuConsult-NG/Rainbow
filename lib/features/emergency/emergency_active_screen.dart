import 'dart:async';
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
  Timer? _cancelTimer;
  
  // For fading in the map
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _cancelController = AnimationController(
        vsync: this, duration: const Duration(seconds: 3));

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) ref.read(emergencyProvider.notifier).tick();
    });

    // Sequence: Show 'We see you' then slowly fade in map after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showMap = true;
        });
        HapticFeedback.lightImpact();
      }
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _cancelTimer?.cancel();
    _cancelController.dispose();
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
    String pin = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Color(0xFF140000), // very dark red
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('CANCEL SOS', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text('Enter your Secure PIN to confirm you are safe.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 32),
              
              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < pin.length ? Colors.white : Colors.white10,
                  ),
                )),
              ),
              const SizedBox(height: 48),

              // Numpad
              Wrap(
                spacing: 24,
                runSpacing: 24,
                alignment: WrapAlignment.center,
                children: List.generate(12, (index) {
                  if (index == 9) return const SizedBox(width: 72); // Empty space
                  if (index == 11) {
                    // Backspace
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (pin.isNotEmpty) setModalState(() => pin = pin.substring(0, pin.length - 1));
                      },
                      child: Container(
                         width: 72, height: 72,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
                        child: const Center(child: Icon(Icons.backspace_rounded, color: Colors.white)),
                      ),
                    );
                  }
                  final number = index == 10 ? 0 : index + 1;
                  return GestureDetector(
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      if (pin.length < 4) {
                        setModalState(() => pin += number.toString());
                        if (pin.length == 4) {
                          // Verify
                          final verified = await ref.read(emergencyProvider.notifier).verifyCancellation(pin);
                          
                          // Fix #4: check BOTH modal ctx AND outer context before using either
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop(); // Close sheet
                          
                          if (verified) {
                            // Use outer context only if it's still alive
                            if (!mounted) return;
                            context.go(AppRoutes.home);
                            Future.delayed(const Duration(milliseconds: 600), () {
                              if (!mounted) return;
                              showSafetyFeedback(context);
                            });
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Invalid PIN.'), backgroundColor: AppColors.error),
                            );
                          }
                        }
                      }
                    },
                    child: Container(
                      width: 72, height: 72,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white10),
                      child: Center(child: Text(number.toString(), style: GoogleFonts.inter(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700))),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 40),
            ],
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // fallback
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF3B0000), // intense dark red
              Color(0xFF140000), // near black red
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 2,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 1000),
                    child: _showMap
                        ? Column(
                            key: const ValueKey('after'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Location shared.',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Nearby responders alerted.',
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            key: const ValueKey('before'),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'We see you.',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Stay where you are.',
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              
              // Map section (fades in)
              Expanded(
                flex: 3,
                child: AnimatedOpacity(
                  opacity: _showMap ? 1.0 : 0.0,
                  duration: const Duration(seconds: 2),
                  curve: Curves.easeInOut,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withAlpha(20),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Stack(
                        children: [
                          // Use live GPS if available, fall back to Plateau State center
                          Consumer(builder: (context, ref, _) {
                            final locAsync = ref.watch(userLocationStreamProvider);
                            final center = locAsync.when(
                              data: (pos) => LatLng(pos.latitude, pos.longitude),
                              loading: () => const LatLng(9.9167, 8.8917),
                              error: (_, __) => const LatLng(9.9167, 8.8917),
                            );
                            return RainbowMap(
                              center: center,
                              initialZoom: 16.0,
                              interactive: false,
                            );
                          }),
                          // Overlay to make map match emotional tone
                          Container(color: Colors.black.withAlpha(120)),
                          
                          // Soft pulsing current user dot
                          Center(
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFF5252),
                                border: Border.all(color: Colors.white, width: 4),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF5252).withAlpha(100),
                                    blurRadius: 20,
                                    spreadRadius: 8,
                                  )
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Cancel button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: GestureDetector(
                  onLongPressStart: (_) => _startCancel(),
                  onLongPressEnd: (_) => _stopCancel(),
                  onLongPressCancel: _stopCancel,
                  child: AnimatedBuilder(
                    animation: _cancelController,
                    builder: (context, _) {
                      return Container(
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(10),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(color: Colors.white.withAlpha(30)),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          children: [
                            FractionallySizedBox(
                              widthFactor: _cancelController.value,
                              child: Container(color: Colors.white24),
                            ),
                            Center(
                              child: Text(
                                'Hold here if you are safe',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  letterSpacing: 0.5,
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
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

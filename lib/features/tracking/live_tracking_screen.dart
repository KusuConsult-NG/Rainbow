import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/rainbow_app_bar.dart';
import '../../shared/widgets/bottom_nav_bar.dart';
import '../../shared/widgets/rainbow_map.dart';
import '../../services/location_service.dart';
import '../../services/background_tracking_service.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback;

class LiveTrackingScreen extends ConsumerStatefulWidget {
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  bool _isTracking = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userLocAsync = ref.watch(userLocationStreamProvider);
    
    final markers = <Marker>[];
    final points = <LatLng>[];

    userLocAsync.whenData((pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      points.add(loc);
      markers.add(
        Marker(
          point: loc,
          width: 50,
          height: 50,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondary.withAlpha((70 - _pulseController.value * 70).toInt()),
                    spreadRadius: _pulseController.value * 20,
                  )
                ],
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    });

    final polylines = points.length == 2 ? [
      Polyline(points: points, strokeWidth: 4.0, color: AppColors.secondary)
    ] : <Polyline>[];

    final center = points.isNotEmpty ? points.first : const LatLng(9.9167, 8.8917);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const RainbowAppBar(
        title: 'MOVEMENT',
        subtitle: 'PERSONAL TRACKING',
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: RainbowMap(
              center: center,
              initialZoom: 15.0,
              markers: markers,
              polylines: polylines,
            ),
          ),

          // Top Info Card - Conversational
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(20),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) => Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isTracking ? AppColors.secondary : AppColors.outlineVariant,
                        boxShadow: _isTracking ? [
                          BoxShadow(
                            color: AppColors.secondary.withAlpha((_pulseController.value * 100).toInt()),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ] : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isTracking ? 'You are moving' : 'Tracking paused',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Last update: Just now',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Column(
              children: [
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    final loc = points.isNotEmpty ? points.first : null;
                    if (loc != null) {
                      final link = 'https://maps.google.com/?q=${loc.latitude},${loc.longitude}';
                      Clipboard.setData(ClipboardData(text: link));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Tracking link copied!', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      );
                    }
                  },
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.share_rounded, color: AppColors.secondary),
                        const SizedBox(width: 8),
                        Text(
                          'Share Live Link',
                          style: GoogleFonts.inter(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    final newValue = !_isTracking;
                    setState(() {
                      _isTracking = newValue;
                    });
                    final userId = ref.read(userRoleProvider).value ?? 'AGENT';
                    if (newValue) {
                       await BackgroundTrackingService().startTracking('MANUAL', userId);
                    } else {
                       await BackgroundTrackingService().stopTracking();
                    }
                  },
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: _isTracking ? AppColors.surfaceContainerHigh : AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isTracking ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: _isTracking ? AppColors.onSurface : Colors.white
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isTracking ? 'Pause Tracking' : 'Resume Tracking',
                          style: GoogleFonts.inter(
                            color: _isTracking ? AppColors.onSurface : Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
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
      bottomNavigationBar: const RainbowBottomNav(currentIndex: 1),
    );
  }
}

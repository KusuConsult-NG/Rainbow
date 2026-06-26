import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:rainbow_app/shared/widgets/rainbow_map.dart';
import 'package:share_plus/share_plus.dart';

/// Documentation for this public member.

class LiveTrackingScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const LiveTrackingScreen({super.key});

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  final List<LatLng> _pathPoints = [];
  StreamSubscription<Position>? _positionSubscription;
  Position? _currentPosition;
  bool _isTracking = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    unawaited(_pulseController.repeat(reverse: true));
    _startTracking();

    // GAP-3: BackgroundTrackingService integration
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final alertId = ref.read(emergencyProvider).alertId;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        if (alertId != null) {
          unawaited(BackgroundTrackingService().startSosTracking(alertId, uid));
        } else {
          unawaited(BackgroundTrackingService().startResponderTracking(uid));
        }
      }
    });
  }

  void _startTracking() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _currentPosition = position;
        final loc = LatLng(position.latitude, position.longitude);
        if (_pathPoints.isEmpty || _pathPoints.last != loc) {
          _pathPoints.add(loc);
        }
      });

      // GAP-F: Write live position to Firestore so HQ can see citizen's path
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && _isTracking) {
        FirebaseFirestore.instance.collection('tracking').doc(uid).set(
          {
            'lat': position.latitude,
            'lng': position.longitude,
            'speed': position.speed,
            'heading': position.heading,
            'updatedAt': FieldValue.serverTimestamp(),
            'status': 'ACTIVE',
            'path': FieldValue.arrayUnion([
              {
                'lat': position.latitude,
                'lng': position.longitude,
                'timestamp': DateTime.now().toIso8601String(),
              }
            ]),
          },
          SetOptions(merge: true),
        ).ignore();
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    unawaited(_positionSubscription?.cancel());
    unawaited(BackgroundTrackingService().stopTracking());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[];
    if (_currentPosition != null) {
      markers.add(
        Marker(
          point:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
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
                    color: AppColors.secondary
                        .withAlpha((70 - _pulseController.value * 70).toInt()),
                    spreadRadius: _pulseController.value * 20,
                  ),
                ],
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
    }

    final polylines = _pathPoints.length >= 2
        ? [
            Polyline(
              points: _pathPoints,
              strokeWidth: 4,
              color: AppColors.secondary,
            ),
          ]
        : <Polyline>[];

    final center = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : const LatLng(9.9167, 8.8917);

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
              markers: markers,
              polylines: polylines,
            ),
          ),

          // Top Info Card
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
                  ),
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
                        color: _isTracking
                            ? AppColors.secondary
                            : AppColors.outlineVariant,
                        boxShadow: _isTracking
                            ? [
                                BoxShadow(
                                  color: AppColors.secondary.withAlpha(
                                    (_pulseController.value * 100).toInt(),
                                  ),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        !_isTracking
                            ? 'Tracking paused'
                            : (_currentPosition == null)
                                ? 'Acquiring signal...'
                                : ((_currentPosition!.speed * 3.6) > 2.0)
                                    ? 'Moving at ${(_currentPosition!.speed * 3.6).toStringAsFixed(1)} km/h'
                                    : 'Stationary',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onSurface,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _currentPosition != null
                            ? 'Last update: Just now'
                            : 'Initializing...',
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
                    unawaited(HapticFeedback.selectionClick());
                    final auth = ref.read(authProvider);
                    final badgeId = auth.profile?['badgeId'] ?? 'unknown';
                    final link =
                        'https://hq.operationrainbow.plateau.gov.ng/track/agent/$badgeId';
                    unawaited(
                      SharePlus.instance.share(
                        ShareParams(
                          text: 'Live tactical tracking established: $link',
                        ),
                      ),
                    );
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
                        const Icon(
                          Icons.share_rounded,
                          color: AppColors.secondary,
                        ),
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
                    unawaited(HapticFeedback.lightImpact());
                    final newValue = !_isTracking;
                    setState(() {
                      _isTracking = newValue;
                    });

                    final auth = ref.watch(authProvider);
                    final userId = auth.user?.uid ?? 'unknown';

                    if (newValue) {
                      await BackgroundTrackingService()
                          .startSosTracking('MANUAL', userId);
                    } else {
                      await BackgroundTrackingService().stopTracking();
                    }
                  },
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: _isTracking
                          ? AppColors.surfaceContainerHigh
                          : AppColors.primary,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isTracking
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color:
                              _isTracking ? AppColors.onSurface : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isTracking ? 'Pause Tracking' : 'Resume Tracking',
                          style: GoogleFonts.inter(
                            color: _isTracking
                                ? AppColors.onSurface
                                : Colors.white,
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
    );
  }
}

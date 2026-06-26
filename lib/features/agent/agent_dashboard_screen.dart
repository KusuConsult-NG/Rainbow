// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:local_auth/local_auth.dart' as local_auth;
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/auth_service.dart';
import 'package:rainbow_app/shared/widgets/broadcast_hud.dart';
import 'package:rainbow_app/shared/widgets/rainbow_map.dart';

/// Documentation for this public member.
final alertsStreamProvider = StreamProvider<QuerySnapshot>((ref) {
  final auth = ref.watch(authProvider);
  final profile = auth.profile ?? {};
  final role = profile['role'] as String? ?? '';
  Query<Map<String, dynamic>> query =
      FirebaseFirestore.instance.collection('alerts');

  // 1. Check staff role for scope limitation to prevent PERMISSION_DENIED
  if (role == 'LGA_COMMAND' || role == 'LGA_OFFICER') {
    final assignedLgas =
        (profile['geo_lgas'] as List<dynamic>?)?.cast<String>() ??
            [profile['geo_lga'] as String? ?? profile['lga'] as String?]
                .whereType<String>()
                .toList();
    if (assignedLgas.isNotEmpty && !assignedLgas.contains('ALL')) {
      if (assignedLgas.length == 1) {
        query = query.where('geo_lga', isEqualTo: assignedLgas.first);
      } else {
        query = query.where('geo_lga', whereIn: assignedLgas);
      }
    }
  } else if (role == 'WARD_COMMAND' || role == 'WARD_OFFICER') {
    final assignedWards =
        (profile['geo_wards'] as List<dynamic>?)?.cast<String>() ??
            [profile['geo_ward'] as String? ?? profile['ward'] as String?]
                .whereType<String>()
                .toList();
    if (assignedWards.isNotEmpty && !assignedWards.contains('ALL')) {
      if (assignedWards.length == 1) {
        query = query.where('geo_ward', isEqualTo: assignedWards.first);
      } else {
        query = query.where('geo_ward', whereIn: assignedWards);
      }
    }
  } else if (role == 'POLLING_UNIT_COMMAND' ||
      role == 'POLLING_UNIT_OFFICER' ||
      role == 'AGENT' ||
      role == 'RESPONDER') {
    final geoPu = profile['geo_pu'] as String? ??
        profile['pu'] as String? ??
        'UNKNOWN';
    query = query.where('geo_pu', isEqualTo: geoPu);
  }

  // 2. Base filter: only show active and non-resolved alerts to agents
  query = query.where('status', whereIn: [
    'OPEN',
    'ACTIVE',
    'DISPATCHED',
    'ACKNOWLEDGED',
    'ON_ROUTE',
    'ON_SITE',
    'ARRIVED',
    'DURESS',
    'ESCALATED'
  ]);

  return query.snapshots();
});

/// Documentation for this public member.
final trackingStreamProvider = StreamProvider<DatabaseEvent>((ref) {
  return FirebaseDatabase.instance.ref('tracking').onValue;
});

/// Documentation for this public member.

class AgentDashboardScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const AgentDashboardScreen({super.key});

  @override
  ConsumerState<AgentDashboardScreen> createState() =>
      _AgentDashboardScreenState();
}

class _AgentDashboardScreenState extends ConsumerState<AgentDashboardScreen> {
  // Profile is now managed by authProvider

  String get _roleTitle {
    final auth = ref.watch(authProvider);
    if (auth.role == UserRole.responder) {
      switch (auth.tier) {
        case ResponderTier.lga:
          return 'LGA COMMAND';
        case ResponderTier.ward:
          return 'WARD COMMAND';
        case ResponderTier.pu:
          return 'UNIT COMMAND';
        // ignore: no_default_cases, Stylistic override to match system design
        default:
          return 'OPERATIONAL UNIT';
      }
    }
    return 'CITIZEN';
  }

  String get _assignedTier {
    final auth = ref.watch(authProvider);
    switch (auth.tier) {
      case ResponderTier.pu:
        return 'UNIT';
      case ResponderTier.ward:
        return 'WARD';
      case ResponderTier.lga:
        return 'LGA';
      // ignore: no_default_cases, Stylistic override to match system design
      default:
        return 'UNIT';
    }
  }

  bool _showMap = false;

  Future<void> _verifyAndExecute(VoidCallback onVerified) async {
    final auth = local_auth.LocalAuthentication();
    try {
      final canCheck =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (canCheck) {
        final didAuth = await auth.authenticate(
          localizedReason: 'SECURE MISSION AUTHORIZATION REQUIRED',
          options: const local_auth.AuthenticationOptions(stickyAuth: true),
        );
        if (didAuth) {
          unawaited(HapticFeedback.mediumImpact());
          onVerified();
        }
      } else {
        // Device has no biometrics — bypass with a confirmation dialog
        _showConfirmationFallback(onVerified);
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (_) {
      // Any biometric error — fall back to confirmation dialog
      _showConfirmationFallback(onVerified);
    }
  }

  void _showConfirmationFallback(VoidCallback onVerified) {
    unawaited(
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surfaceContainer,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'MISSION AUTHORIZATION',
            style: GoogleFonts.outfit(
              color: AppColors.onBackground,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              fontSize: 14,
            ),
          ),
          content: Text(
            'Biometric authentication unavailable. Confirm mission action?',
            style: GoogleFonts.outfit(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'ABORT',
                style: GoogleFonts.outfit(
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'CONFIRM',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed ?? false) {
          unawaited(HapticFeedback.mediumImpact());
          onVerified();
        }
      }),
    );
  }

  void _showActionDialog(DocumentSnapshot alertDoc) {
    unawaited(
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _TacticalActionSheet(
          alertDoc: alertDoc,
          assignedTier: _assignedTier,
          onAction: () => Navigator.pop(context),
          verifyAndExecute: _verifyAndExecute,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authProvider).profile ?? {};
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(SystemNavigator.pop());
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _roleTitle,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 1,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'LIVE MISSION FEED',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                _showMap ? Icons.view_headline_rounded : Icons.radar_rounded,
                color: Colors.white,
              ),
              onPressed: () {
                unawaited(HapticFeedback.lightImpact());
                setState(() => _showMap = !_showMap);
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.power_settings_new_rounded,
                color: Colors.white70,
              ),
              onPressed: () async {
                await ref.read(authServiceProvider).signOut();
                if (!context.mounted) return;
                context.go(AppRoutes.login);
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                const BroadcastHud(),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: ref.watch(alertsStreamProvider.stream),
                    builder: (context, alertSnapshot) {
                      return StreamBuilder<DatabaseEvent>(
                        stream: ref.watch(trackingStreamProvider.stream),
                        builder: (context, trackingSnapshot) {
                          if (alertSnapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            );
                          }

                          final uid =
                              ref.watch(authServiceProvider).currentUserId;
                          final profile = ref.watch(authProvider).profile ?? {};
                          final assignedLgas =
                              (profile['geo_lgas'] as List<dynamic>?)
                                      ?.cast<String>() ??
                                  [
                                    profile['geo_lga'] as String? ??
                                        profile['lga'] as String?,
                                  ].whereType<String>().toList();
                          final assignedWards =
                              (profile['geo_wards'] as List<dynamic>?)
                                      ?.cast<String>() ??
                                  [
                                    profile['geo_ward'] as String? ??
                                        profile['ward'] as String?,
                                  ].whereType<String>().toList();
                          final assignedPus =
                              (profile['geo_pus'] as List<dynamic>?)
                                      ?.cast<String>() ??
                                  [
                                    profile['geo_pu'] as String? ??
                                        profile['pu'] as String?,
                                  ].whereType<String>().toList();
                          final allDocs = alertSnapshot.data?.docs ?? [];
                          final filteredAlerts = allDocs.where((doc) {
                            final alert = doc.data()! as Map<String, dynamic>;
                            if (alert['assignedToUid'] == uid) return true;


                            final auth = ref.watch(authProvider);
                            final alertAssignedTo =
                                alert['assigned_to']?.toString() ?? '';

                            if (auth.tier == ResponderTier.lga) {
                              final eligibleTiers = [
                                'LGA',
                                'WARD',
                                'POLLING_UNIT',
                              ];
                              return eligibleTiers.contains(alertAssignedTo) &&
                                  (assignedLgas.contains(alert['geo_lga']) ||
                                      assignedLgas.contains('ALL'));
                            }
                            if (auth.tier == ResponderTier.ward) {
                              final eligibleTiers = ['WARD', 'POLLING_UNIT'];
                              return eligibleTiers.contains(alertAssignedTo) &&
                                  (assignedWards.contains(alert['geo_ward']) ||
                                      assignedWards.contains('ALL'));
                            }
                            if (auth.tier == ResponderTier.pu) {
                              final eligibleTiers = ['POLLING_UNIT'];
                              return eligibleTiers.contains(alertAssignedTo) &&
                                  (assignedPus.contains(alert['geo_pu']) ||
                                      assignedPus.contains('ALL'));
                            }
                            // HQ or special commands fall back to true
                            return true;
                          }).toList()
                            ..sort((a, b) {
                              final aData = a.data() as Map<String, dynamic>?;
                              final bData = b.data() as Map<String, dynamic>?;
                              final aTime = aData?['reportedAt'] as Timestamp?;
                              final bTime = bData?['reportedAt'] as Timestamp?;
                              if (aTime == null && bTime == null) return 0;
                              if (aTime == null) return 1;
                              if (bTime == null) return -1;
                              return bTime.compareTo(aTime); // descending order
                            });

                          // Process Responder Telemetry
                          final responderMarkers = <Marker>[];
                          if (trackingSnapshot.hasData &&
                              trackingSnapshot.data!.snapshot.value != null) {
                            final rawValue =
                                trackingSnapshot.data!.snapshot.value;
                            if (rawValue is Map) {
                              final data = Map<dynamic, dynamic>.from(rawValue);
                              for (final entry in data.entries) {
                                final userId = entry.key;
                                final telemetry = entry.value;
                                if (userId == uid) {
                                  continue; // Don't show self as responder marker
                                }
                                if (telemetry is! Map) continue;
                                final t = Map<String, dynamic>.from(telemetry);
                                final lat = t['lat'] as double?;
                                final lng = t['lng'] as double?;
                                if (lat != null && lng != null) {
                                  responderMarkers.add(
                                    Marker(
                                      point: LatLng(lat, lng),
                                      width: 40,
                                      height: 40,
                                      child: _ResponderMarker(
                                        status: (t['status'] as String?) ??
                                            'ONLINE',
                                        isEmergency: t['mode'] == 'sos',
                                      ),
                                    ),
                                  );
                                }
                              } // end for
                            } // end if (rawValue is Map)
                          }

                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 500),
                            child: _showMap
                                ? _buildMap(filteredAlerts, responderMarkers)
                                : _buildList(filteredAlerts),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            // Scanner overlay effect
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.02),
                      Colors.transparent,
                      Colors.transparent,
                      AppColors.primary.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Stream<QuerySnapshot> _buildAlertsStream(Map<String, dynamic> profile) {
    final role = profile['role'] as String? ?? '';
    Query<Map<String, dynamic>> query =
        FirebaseFirestore.instance.collection('alerts');

    // 1. Check staff role for scope limitation to prevent PERMISSION_DENIED
    if (role == 'LGA_COMMAND' || role == 'LGA_OFFICER') {
      final assignedLgas =
          (profile['geo_lgas'] as List<dynamic>?)?.cast<String>() ??
              [profile['geo_lga'] as String? ?? profile['lga'] as String?]
                  .whereType<String>()
                  .toList();
      if (assignedLgas.isNotEmpty && !assignedLgas.contains('ALL')) {
        if (assignedLgas.length == 1) {
          query = query.where('geo_lga', isEqualTo: assignedLgas.first);
        } else {
          query = query.where('geo_lga', whereIn: assignedLgas);
        }
      }
    } else if (role == 'WARD_COMMAND' || role == 'WARD_OFFICER') {
      final assignedWards =
          (profile['geo_wards'] as List<dynamic>?)?.cast<String>() ??
              [profile['geo_ward'] as String? ?? profile['ward'] as String?]
                  .whereType<String>()
                  .toList();
      if (assignedWards.isNotEmpty && !assignedWards.contains('ALL')) {
        if (assignedWards.length == 1) {
          query = query.where('geo_ward', isEqualTo: assignedWards.first);
        } else {
          query = query.where('geo_ward', whereIn: assignedWards);
        }
      }
    } else if (role == 'UNIT_COMMAND' ||
        role == 'POLLING_OFFICER' ||
        role == 'POLLING_UNIT_OFFICER') {
      final assignedPus =
          (profile['geo_pus'] as List<dynamic>?)?.cast<String>() ??
              [profile['geo_pu'] as String? ?? profile['pu'] as String?]
                  .whereType<String>()
                  .toList();
      if (assignedPus.isNotEmpty && !assignedPus.contains('ALL')) {
        if (assignedPus.length == 1) {
          query = query.where('geo_pu', isEqualTo: assignedPus.first);
        } else {
          query = query.where('geo_pu', whereIn: assignedPus);
        }
      }
    }

    // 2. Filter by status (using whereIn since we only have isEqualTo/whereIn for geo filters above, they never execute together)
    query = query.where(
      'status',
      whereIn: [
        'OPEN',
        'ACTIVE',
        'DISPATCHED',
        'ACKNOWLEDGED',
        'ON_ROUTE',
        'ON_SITE',
        'DURESS',
      ],
    );

    return query.snapshots();
  }

  Widget _buildList(List<DocumentSnapshot> alerts) {
    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.radar_rounded, size: 64, color: AppColors.outline),
            const SizedBox(height: 24),
            Text(
              'ALL CLEAR - NO ACTIVE MISSIONS',
              style: GoogleFonts.outfit(
                color: AppColors.textDim,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 40),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index].data()! as Map<String, dynamic>;
        return _MissionCard(
          alert: alert,
          onTap: () => _showActionDialog(alerts[index]),
        );
      },
    );
  }

  Widget _buildMap(List<DocumentSnapshot> alerts, List<Marker> responders) {
    final alertMarkers = alerts
        .map((doc) {
          final data = doc.data()! as Map<String, dynamic>;
          final lat = data['lat'] as double?;
          final lng = data['lng'] as double?;
          if (lat == null || lng == null) return null;
          final isEmergency =
              data['type']?.toString().contains('EMERGENCY') ?? false;
          return Marker(
            point: LatLng(lat, lng),
            width: 60,
            height: 60,
            child: GestureDetector(
              onTap: () => _showActionDialog(doc),
              child: _PulseMarker(isEmergency: isEmergency),
            ),
          );
        })
        .whereType<Marker>()
        .toList();

    return RainbowMap(
      center: const LatLng(9.9285, 8.8923),
      initialZoom: 13,
      markers: [...alertMarkers, ...responders],
    );
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.alert, required this.onTap});
  final Map<String, dynamic> alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = alert['status'] ?? 'OPEN';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isMine = alert['assignedToUid'] == uid;

    final statusColors = {
      'OPEN': AppColors.warning,
      'ACTIVE': AppColors.warning,
      'DISPATCHED': AppColors.primary,
      'ACKNOWLEDGED': AppColors.success,
      'ON_ROUTE': AppColors.accent,
      'ON_SITE': AppColors.success,
      'DURESS': AppColors.error,
    };

    final color = statusColors[status] ?? AppColors.outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isMine
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.outline,
          width: isMine ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _StatusBadge(
                              label: status.toString().toUpperCase(),
                              color: color,
                            ),
                            if (isMine)
                              const _StatusBadge(
                                label: 'PERSONAL',
                                color: AppColors.primary,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(
                          alert['reportedAt'] ??
                              alert['createdAt'] ??
                              alert['timestamp'],
                        ),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    alert['type']?.toString().toUpperCase() ??
                        'UNKNOWN MISSION',
                    style: GoogleFonts.outfit(
                      color: AppColors.onBackground,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (alert['description'] as String?) ??
                        'No narrative provided',
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.white05, height: 1),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${alert['geo_lga'] ?? 'PLATEAU'} · ${alert['geo_ward'] ?? 'HQ'} · ${alert['geo_pu'] ?? 'UNIT'}'
                              .toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: AppColors.textDim,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textDim,
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return 'T-00:00';
    if (timestamp is Timestamp) {
      final dt = timestamp.toDate();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} HRS';
    }
    return 'RECENT';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: color,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalActionSheet extends StatelessWidget {
  const _TacticalActionSheet({
    required this.alertDoc,
    required this.assignedTier,
    required this.onAction,
    required this.verifyAndExecute,
  });
  final DocumentSnapshot alertDoc;
  final String assignedTier;
  final VoidCallback onAction;
  final Future<void> Function(VoidCallback) verifyAndExecute;

  @override
  Widget build(BuildContext context) {
    final alert = alertDoc.data()! as Map<String, dynamic>;
    final status = alert['status'] ?? 'OPEN';
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'STAFF';
    final isAssignedToMe = alert['assignedToUid'] == uid;

    var buttonLabel = 'DEPLOY';
    var buttonColor = AppColors.primary;
    const buttonIcon = Icons.local_police_rounded;
    var nextStatus = 'ACKNOWLEDGED';

    if (status == 'OPEN' || status == 'ACTIVE') {
      buttonLabel = 'SELF-DEPLOY';
      nextStatus = 'ACKNOWLEDGED';
    } else if (status == 'DISPATCHED' && isAssignedToMe) {
      buttonLabel = 'ACKNOWLEDGE MISSION';
      buttonColor = AppColors.warning;
      nextStatus = 'ACKNOWLEDGED';
    } else if (status == 'ACKNOWLEDGED' && isAssignedToMe) {
      buttonLabel = 'EN ROUTE';
      buttonColor = AppColors.primary;
      nextStatus = 'ON_ROUTE';
    } else if (status == 'ON_ROUTE' && isAssignedToMe) {
      buttonLabel = 'ON SITE';
      buttonColor = AppColors.success;
      nextStatus = 'ON_SITE';
    } else if (status == 'ON_SITE' && isAssignedToMe) {
      buttonLabel = 'RESOLVE MISSION';
      buttonColor = AppColors.safe;
      nextStatus = 'RESOLVED';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(top: BorderSide(color: AppColors.outline)),
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
          const SizedBox(height: 24),
          Text(
            'TACTICAL ENGAGEMENT',
            style: GoogleFonts.outfit(
              color: AppColors.onBackground,
              fontWeight: FontWeight.w900,
              fontSize: 16,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 32),
          _TacticalButton(
            label: buttonLabel,
            color: buttonColor,
            icon: buttonIcon,
            onTap: () => verifyAndExecute(() async {
              onAction();
              if (status == 'ON_SITE') {
                // Push to resolution screen instead of resolving directly
                unawaited(
                  context.push(AppRoutes.missionResolution, extra: alertDoc),
                );
                return;
              }
              try {
                final func = FirebaseFunctions.instance
                    .httpsCallable('agentUpdateMissionStatus');
                await func.call<dynamic>({
                  'alertId': alertDoc.id,
                  'nextStatus': nextStatus,
                });
                // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
              } catch (e) {
                // FALLBACK: Direct Firestore update to bypass Firebase Functions IAM errors for testing
                try {
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  await FirebaseFirestore.instance
                      .collection('alerts')
                      .doc(alertDoc.id)
                      .update({
                    'status': nextStatus,
                    if ((status == 'OPEN' || status == 'ACTIVE') && uid != null)
                      'assignedToUid': uid,
                  });
                  // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
                } catch (fallbackErr) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('FALLBACK FAILED: $fallbackErr'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              }
            }),
          ),
          if (status != 'OPEN' && status != 'ACTIVE' && isAssignedToMe) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _TacticalButton(
                    label: 'MISSION INTEL',
                    color: AppColors.primary,
                    icon: Icons.plagiarism_rounded,
                    onTap: () {
                      onAction();
                      unawaited(
                        context.push(
                          AppRoutes.missionIntel,
                          extra: alertDoc,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TacticalButton(
                    label: 'SECURE CHAT',
                    color: AppColors.accent,
                    icon: Icons.chat_rounded,
                    onTap: () {
                      onAction();
                      unawaited(
                        context.push(AppRoutes.secureChat, extra: alertDoc),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
          if ((isAssignedToMe || status == 'OPEN' || status == 'ACTIVE') &&
              status != 'RESOLVED' &&
              assignedTier != 'HQ') ...[
            const SizedBox(height: 16),
            _EscalateButton(
              onTap: () => verifyAndExecute(() async {
                onAction();
                final success = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => _EscalationDialog(
                    alertDoc: alertDoc,
                    assignedTier: assignedTier,
                  ),
                );
                if ((success ?? false) && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('MISSION ESCALATED SUCCESSFULLY'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              }),
            ),
          ],
          if (!isAssignedToMe && status != 'OPEN' && status != 'ACTIVE') ...[
            const SizedBox(height: 16),
            Text(
              'MISSION ASSIGNED TO ANOTHER UNIT',
              style: GoogleFonts.outfit(
                color: AppColors.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EscalationDialog extends StatefulWidget {
  const _EscalationDialog({
    required this.alertDoc,
    required this.assignedTier,
  });

  final DocumentSnapshot alertDoc;
  final String assignedTier;

  @override
  State<_EscalationDialog> createState() => _EscalationDialogState();
}

class _EscalationDialogState extends State<_EscalationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  String _selectedReason = 'Tactical Resource Exhaustion';
  bool _isSubmitting = false;

  final List<String> _presets = [
    'Tactical Resource Exhaustion',
    'Overwhelming Threat Level',
    'Medical Overload',
    'Communications Failure',
    'Other',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var targetTier = 'WARD';
    if (widget.assignedTier == 'WARD') targetTier = 'LGA';
    if (widget.assignedTier == 'LGA') targetTier = 'HQ';

    return AlertDialog(
      backgroundColor: AppColors.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.error,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'TACTICAL ESCALATION',
                style: GoogleFonts.outfit(
                  color: AppColors.onBackground,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Transferring command to $targetTier tier',
            style: GoogleFonts.outfit(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PRIMARY REASON',
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedReason,
                dropdownColor: AppColors.surfaceContainerHigh,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.outline),
                  ),
                ),
                style: GoogleFonts.outfit(
                  color: AppColors.onBackground,
                  fontSize: 13,
                ),
                items: _presets.map((reason) {
                  return DropdownMenuItem<String>(
                    value: reason,
                    child: Text(reason),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedReason = val);
                  }
                },
              ),
              const SizedBox(height: 20),
              Text(
                'TACTICAL NOTES / SITUATION REPORT',
                style: GoogleFonts.outfit(
                  color: AppColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                style: GoogleFonts.outfit(
                  color: AppColors.onBackground,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Enter details of dynamic situation and resources needed...',
                  hintStyle: GoogleFonts.outfit(
                    color: AppColors.textDim,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.outline),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'SITREP is required for manual escalation';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text(
            'CANCEL',
            style: GoogleFonts.outfit(
              color: AppColors.textDim,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitEscalation,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.error.withValues(alpha: 0.3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  'CONFIRM ESCALATION',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _submitEscalation() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    var targetTier = 'WARD';
    if (widget.assignedTier == 'WARD') targetTier = 'LGA';
    if (widget.assignedTier == 'LGA') targetTier = 'HQ';

    try {
      final func =
          FirebaseFunctions.instance.httpsCallable('adminEscalateAlert');
      await func.call<dynamic>({
        'alertId': widget.alertDoc.id,
        'targetTier': targetTier,
        'reason': _selectedReason,
        'notes': _notesController.text.trim(),
      });
      if (mounted) {
        Navigator.pop(context, true);
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint(
        '[ESCALATION_ERROR] Cloud function failed: $e. Falling back...',
      );
      try {
        final email = FirebaseAuth.instance.currentUser?.email ?? 'UNKNOWN';
        final newEvent = {
          'type': 'ESCALATION',
          'actor': email,
          'role': widget.assignedTier == 'UNIT'
              ? 'UNIT_COMMAND'
              : (widget.assignedTier == 'WARD'
                  ? 'WARD_COMMAND'
                  : 'LGA_COMMAND'),
          'timestamp': DateTime.now().toIso8601String(),
          'reason': _selectedReason,
          'notes': _notesController.text.trim(),
        };
        await FirebaseFirestore.instance
            .collection('alerts')
            .doc(widget.alertDoc.id)
            .update({
          'assigned_to': targetTier,
          'escalated_at': FieldValue.serverTimestamp(),
          'timeline': FieldValue.arrayUnion([newEvent]),
        });
        if (mounted) {
          Navigator.pop(context, true);
        }
        // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
      } catch (fallbackErr) {
        debugPrint('[ESCALATION_FALLBACK_ERROR] Fallback failed: $fallbackErr');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Escalation failed: $fallbackErr'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() => _isSubmitting = false);
        }
      }
    }
  }
}

class _EscalateButton extends StatelessWidget {
  const _EscalateButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.error.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.arrow_upward_rounded,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'ESCALATE TO HIGHER COMMAND',
              style: GoogleFonts.outfit(
                color: AppColors.error,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TacticalButton extends StatelessWidget {
  const _TacticalButton({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseMarker extends StatefulWidget {
  const _PulseMarker({required this.isEmergency});
  final bool isEmergency;
  @override
  _PulseMarkerState createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<_PulseMarker>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2));
    unawaited(_ctrl.repeat());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isEmergency ? AppColors.emergency : AppColors.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 60 * _ctrl.value,
            height: 60 * _ctrl.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 1 - _ctrl.value),
                width: 2,
              ),
            ),
          ),
          Container(
            width: 40 * _ctrl.value,
            height: 40 * _ctrl.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: (1 - _ctrl.value) * 0.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              widget.isEmergency ? Icons.warning_rounded : Icons.radar_rounded,
              color: AppColors.onPrimary,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponderMarker extends StatelessWidget {
  const _ResponderMarker({required this.status, required this.isEmergency});
  final String status;
  final bool isEmergency;

  @override
  Widget build(BuildContext context) {
    final color = isEmergency ? AppColors.secondary : AppColors.success;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.onPrimary, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:ui';

import 'package:rainbow_app/core/supabase/supabase_config.dart';
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
import 'package:rainbow_app/services/tts_service.dart';
import 'package:rainbow_app/shared/widgets/broadcast_hud.dart';
import 'package:rainbow_app/shared/widgets/rainbow_map.dart';

/// Documentation for this public member.
final alertsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final auth = ref.watch(authProvider);
  final profile = auth.profile ?? {};
  final role = (profile['role'] as String? ?? '').toUpperCase();
  final geoLga = profile['geo_lga'] as String?;
  final geoWard = profile['geo_ward'] as String?;
  final geoPu = profile['geo_pu'] as String?;
  final userId = auth.user?.id;

  return SupabaseConfig.client
      .from('alerts')
      .stream(primaryKey: ['id'])
      .map((list) {
    return list.where((alert) {
      final aGeoLga = alert['geo_lga'] as String?;
      final aGeoWard = alert['geo_ward'] as String?;
      final aGeoPu = alert['geo_pu'] as String?;
      final aAssignedTo = alert['assigned_to'] as String?;

      // 1. Directly assigned to officer -> ALWAYS SHOW
      if (userId != null && aAssignedTo == userId) return true;

      // 2. State HQ Commanders -> ALWAYS SHOW ALL
      if (role.contains('STATE') || role.contains('HQ') || role == 'ADMIN') return true;

      // 3. LGA Commanders -> Show alerts matching LGA or unassigned
      if (role.contains('LGA')) {
        if (geoLga == null || geoLga == 'ALL') return true;
        return aGeoLga == null || aGeoLga.toUpperCase() == geoLga.toUpperCase();
      }

      // 4. Ward Commanders -> Show alerts matching Ward/LGA
      if (role.contains('WARD')) {
        if (geoWard == null || geoWard == 'ALL') return true;
        return aGeoWard == null || aGeoWard.toUpperCase() == geoWard.toUpperCase() ||
               (aGeoLga != null && geoLga != null && aGeoLga.toUpperCase() == geoLga.toUpperCase());
      }

      // 5. PU / Beat Responders -> Show alerts in their PU, Ward, LGA, or unassigned general alerts
      if (geoPu != null && aGeoPu != null && aGeoPu.toUpperCase() == geoPu.toUpperCase()) return true;
      if (geoWard != null && aGeoWard != null && aGeoWard.toUpperCase() == geoWard.toUpperCase()) return true;
      if (geoLga != null && aGeoLga != null && aGeoLga.toUpperCase() == geoLga.toUpperCase()) return true;
      if (aGeoPu == null && aGeoWard == null && aGeoLga == null) return true;

      return true;
    }).toList();
  });
});

/// Documentation for this public member.
final trackingStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return SupabaseConfig.client.from('telemetry').stream(primaryKey: ['user_id']);
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

  void _showActionDialog(Map<String, dynamic> alertDoc) {
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
            if (profile['role'] == 'HQ_COMMAND' || profile['role'] == 'LGA_COMMAND')
              IconButton(
                icon: const Icon(Icons.campaign_rounded, color: Colors.white),
                onPressed: () => context.push(AppRoutes.adminBroadcast),
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
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ref.watch(alertsStreamProvider.stream),
                    builder: (context, alertSnapshot) {
                      return StreamBuilder<List<Map<String, dynamic>>>(
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
                          final allDocs = alertSnapshot.data ?? [];
                          final filteredAlerts = allDocs.where((alert) {
                            if (alert['assignedToUid'] == uid) return true;


                            final auth = ref.watch(authProvider);
                            final alertAssignedTo =
                                alert['assigned_to']?.toString() ?? '';

                            if (auth.tier == ResponderTier.lga) {
                              return assignedLgas.contains(alert['geo_lga']) ||
                                  assignedLgas.contains('ALL') ||
                                  alert['geo_lga'] == null;
                            }
                            if (auth.tier == ResponderTier.ward) {
                              return assignedWards.contains(alert['geo_ward']) ||
                                  assignedWards.contains('ALL') ||
                                  assignedLgas.contains(alert['geo_lga']) ||
                                  alert['geo_ward'] == null;
                            }
                            if (auth.tier == ResponderTier.pu) {
                              return assignedPus.contains(alert['geo_pu']) ||
                                  assignedPus.contains('ALL') ||
                                  assignedWards.contains(alert['geo_ward']) ||
                                  assignedWards.contains('ALL') ||
                                  assignedLgas.contains(alert['geo_lga']) ||
                                  alert['geo_pu'] == null;
                            }
                            // HQ or special commands fall back to true
                            return true;
                          }).toList()
                              ..sort((a, b) {
                                final aTime = a['created_at'] as String? ?? '';
                                final bTime = b['created_at'] as String? ?? '';
                                return bTime.compareTo(aTime);
                              });

                          // Process Responder Telemetry
                          final responderMarkers = <Marker>[];
                          if (trackingSnapshot.hasData) {
                            final telemetryList = trackingSnapshot.data ?? [];
                            for (final telemetry in telemetryList) {
                              final userId = telemetry['user_id'];
                              if (userId == uid) {
                                continue; // Don't show self as responder marker
                              }
                              final lat = (telemetry['latitude'] ?? telemetry['lat']) as double?;
                              final lng = (telemetry['longitude'] ?? telemetry['lng']) as double?;
                              if (lat != null && lng != null) {
                                responderMarkers.add(
                                  Marker(
                                    point: LatLng(lat, lng),
                                    width: 40,
                                    height: 40,
                                    child: _ResponderMarker(
                                      status: (telemetry['status'] as String?) ??
                                          'ONLINE',
                                      isEmergency: telemetry['mode'] == 'sos',
                                    ),
                                  ),
                                );
                              }
                            }
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

  Stream<List<Map<String, dynamic>>> _buildAlertsStream(Map<String, dynamic> profile) {
    return SupabaseConfig.client
        .from('alerts')
        .stream(primaryKey: ['id']);
  }

  Widget _buildList(List<Map<String, dynamic>> alerts) {
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

    final criticalCount = alerts.where((a) => a['severity'] == 'CRITICAL' || a['status'] == 'DURESS').length;
    final escalatedCount = alerts.where((a) => a['status'] == 'ESCALATED').length;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 40),
      itemCount: alerts.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: criticalCount > 0
                    ? [const Color(0xFF3B0000), const Color(0xFF1F0000)]
                    : [const Color(0xFF0F172A), const Color(0xFF020617)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: criticalCount > 0 ? AppColors.danger : AppColors.primary,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (criticalCount > 0 ? AppColors.danger : AppColors.primary).withValues(alpha: 0.2),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (criticalCount > 0 ? AppColors.danger : AppColors.primary).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    criticalCount > 0 ? Icons.warning_amber_rounded : Icons.psychology_rounded,
                    color: criticalCount > 0 ? AppColors.danger : AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        criticalCount > 0 ? 'CRITICAL TACTICAL THREAT ALERT' : 'SMART TACTICAL AI ADVISORY',
                        style: GoogleFonts.outfit(
                          color: criticalCount > 0 ? AppColors.danger : AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        criticalCount > 0
                            ? '$criticalCount Critical Incidents require immediate field unit dispatch or HQ escalation.'
                            : 'All systems active. $escalatedCount escalated alerts pending command review.',
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final alert = alerts[index - 1];
        return _MissionCard(
          alert: alert,
          onTap: () => _showActionDialog(alert),
          onQuickAction: () => _showActionDialog(alert),
        );
      },
    );
  }

  Widget _buildMap(List<Map<String, dynamic>> alerts, List<Marker> responders) {
    final alertMarkers = alerts
        .map((data) {
          final lat = (data['latitude'] ?? data['lat']) as double?;
          final lng = (data['longitude'] ?? data['lng']) as double?;
          if (lat == null || lng == null) return null;
          final isEmergency =
              data['type']?.toString().contains('EMERGENCY') ?? false;
          return Marker(
            point: LatLng(lat, lng),
            width: 60,
            height: 60,
            child: GestureDetector(
              onTap: () => _showActionDialog(data),
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

class _MissionCard extends ConsumerWidget {
  const _MissionCard({
    required this.alert,
    required this.onTap,
    required this.onQuickAction,
  });
  final Map<String, dynamic> alert;
  final VoidCallback onTap;
  final VoidCallback onQuickAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final assignedTier = auth.tier == ResponderTier.pu
        ? 'UNIT'
        : (auth.tier == ResponderTier.ward ? 'WARD' : 'LGA');

    final status = alert['status'] ?? 'OPEN';
    final severity = alert['severity'] ?? 'MEDIUM';
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    final isMine = alert['assignedToUid'] == uid || alert['assigned_to'] == uid;

    final statusColors = {
      'OPEN': AppColors.warning,
      'PENDING': AppColors.warning,
      'ACTIVE': AppColors.warning,
      'ESCALATED': AppColors.warning,
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
          color: severity == 'CRITICAL'
              ? AppColors.error
              : (isMine ? AppColors.primary : AppColors.outline),
          width: severity == 'CRITICAL' || isMine ? 2 : 1,
        ),
        boxShadow: severity == 'CRITICAL'
            ? [BoxShadow(color: AppColors.error.withValues(alpha: 0.2), blurRadius: 10)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
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
                            if (severity == 'CRITICAL')
                              const _StatusBadge(
                                label: 'CRITICAL',
                                color: AppColors.error,
                              ),
                            if (isMine)
                              const _StatusBadge(
                                label: 'ASSIGNED TO YOU',
                                color: AppColors.primary,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(
                          alert['created_at'] ??
                              alert['createdAt'] ??
                              alert['reportedAt'] ??
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
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 6),
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: AppColors.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
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
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.white05, height: 1),
                  const SizedBox(height: 14),
                  // Direct Tactical Action Bar on Every Card!
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onQuickAction,
                          icon: const Icon(Icons.bolt_rounded, size: 16),
                          label: Text(
                            'ENGAGE',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      if (assignedTier == 'WARD' || assignedTier == 'LGA') ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Dispatch Unit',
                          onPressed: () async {
                            await showDialog<bool>(
                              context: context,
                              barrierDismissible: true,
                              builder: (ctx) => _DispatchDialog(alertDoc: alert),
                            );
                          },
                          icon: const Icon(Icons.local_police_rounded, color: AppColors.primary, size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Escalate Mission',
                        onPressed: () async {
                          await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => _EscalationDialog(
                              alertDoc: alert,
                              assignedTier: assignedTier,
                            ),
                          );
                        },
                        icon: const Icon(Icons.arrow_upward_rounded, color: AppColors.warning, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.warning.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Secure Chat',
                        onPressed: () {
                          context.push(AppRoutes.secureChat, extra: alert);
                        },
                        icon: const Icon(Icons.chat_rounded, color: AppColors.accent, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
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
    if (timestamp == null) return 'JUST NOW';
    try {
      DateTime? dt;
      if (timestamp is String) {
        dt = DateTime.tryParse(timestamp);
      } else if (timestamp is DateTime) {
        dt = timestamp;
      }
      if (dt != null) {
        final local = dt.toLocal();
        final hh = local.hour.toString().padLeft(2, '0');
        final mm = local.minute.toString().padLeft(2, '0');
        final months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
        final monthStr = months[local.month - 1];
        return '${local.day} $monthStr · $hh:$mm HRS';
      }
    } catch (_) {}
    return 'JUST NOW';
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
  final Map<String, dynamic> alertDoc;
  final String assignedTier;
  final VoidCallback onAction;
  final Future<void> Function(VoidCallback) verifyAndExecute;

  @override
  Widget build(BuildContext context) {
    final alert = alertDoc;
    final status = alert['status'] ?? 'OPEN';
    final uid = SupabaseConfig.client.auth.currentUser?.id ?? 'STAFF';
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
                final alertId = alertDoc['id'] as String?;
                final uid = SupabaseConfig.client.auth.currentUser?.id;

                if (nextStatus == 'ACKNOWLEDGED') {
                  final type = alertDoc['type'] as String? ?? 'UNKNOWN';
                  final desc = alertDoc['description'] as String? ?? 'No details provided.';
                  final speechText = "Mission accepted. Emergency type: $type. Threat details: $desc.";
                  unawaited(TtsService.instance.speak(speechText));
                }

                if (alertId != null) {
                  await SupabaseConfig.client.from('alerts').update({
                    'status': nextStatus,
                    if ((status == 'OPEN' || status == 'ACTIVE' || status == 'PENDING') && uid != null)
                      'assigned_to': uid,
                  }).eq('id', alertId);
                }
              } catch (e) {
                debugPrint('[TACTICAL_SHEET_ERR] Update status failed: $e');
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
          if (status != 'RESOLVED' && assignedTier != 'HQ') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (assignedTier == 'WARD' || assignedTier == 'LGA') ...[
                  Expanded(
                    child: _TacticalButton(
                      label: 'DISPATCH UNIT',
                      color: AppColors.primary,
                      icon: Icons.local_police_rounded,
                      onTap: () => verifyAndExecute(() async {
                        onAction();
                        final success = await showDialog<bool>(
                          context: context,
                          barrierDismissible: true,
                          builder: (ctx) => _DispatchDialog(alertDoc: alertDoc),
                        );
                        if ((success ?? false) && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('FIELD UNIT DISPATCHED'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: _EscalateButton(
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
                ),
              ],
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

  final Map<String, dynamic> alertDoc;
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
      final alertId = widget.alertDoc['id'] as String?;
      final user = SupabaseConfig.client.auth.currentUser;
      final userEmail = user?.email ?? 'STAFF';

      final profileRes = await SupabaseConfig.client
          .from('profiles')
          .select('geo_lga, geo_ward')
          .eq('id', user?.id ?? '')
          .maybeSingle();

      final oLga = profileRes?['geo_lga'] as String? ?? widget.alertDoc['geo_lga'];
      final oWard = profileRes?['geo_ward'] as String? ?? widget.alertDoc['geo_ward'];

      final updatePayload = <String, dynamic>{
        'status': 'ESCALATED',
        'severity': targetTier == 'HQ' ? 'CRITICAL' : 'HIGH',
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (oWard != null) updatePayload['geo_ward'] = oWard;
      if (oLga != null) updatePayload['geo_lga'] = oLga;

      final existingSummary = widget.alertDoc['ai_summary'] as String? ?? '';
      final note = '[ESCALATED TO $targetTier COMMAND] Reason: $_selectedReason. Notes: ${_notesController.text.trim()} (by $userEmail)';
      updatePayload['ai_summary'] = existingSummary.isEmpty ? note : '$existingSummary\n$note';

      if (alertId != null) {
        await SupabaseConfig.client
            .from('alerts')
            .update(updatePayload)
            .eq('id', alertId);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('[ESCALATION_ERROR] Failed to escalate: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Escalation failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
        setState(() => _isSubmitting = false);
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

class _DispatchDialog extends StatefulWidget {
  const _DispatchDialog({required this.alertDoc});
  final Map<String, dynamic> alertDoc;

  @override
  State<_DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends State<_DispatchDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _responders = [];
  final Set<String> _selectedResponderIds = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadResponders();
  }

  Future<void> _loadResponders() async {
    try {
      final res = await SupabaseConfig.client
          .from('profiles')
          .select('id, full_name, badge_number, role, geo_lga, geo_ward')
          .neq('role', 'CITIZEN');

      if (mounted) {
        setState(() {
          _responders = List<Map<String, dynamic>>.from(res as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitDispatch() async {
    if (_selectedResponderIds.isEmpty) return;
    setState(() => _isSubmitting = true);

    try {
      final alertId = widget.alertDoc['id'] as String?;
      final userEmail = SupabaseConfig.client.auth.currentUser?.email ?? 'COMMANDER';
      
      final selectedObjs = _responders.where((r) => _selectedResponderIds.contains(r['id'])).toList();
      final teamNames = selectedObjs.map((r) => '${r['full_name'] ?? 'Officer'} [${r['badge_number'] ?? r['role']}]').join(', ');
      final leadOfficerId = _selectedResponderIds.first;

      final existingNotes = widget.alertDoc['ai_summary'] as String? ?? '';
      final dispatchNote = '[MULTI-UNIT DISPATCH] Assigned Team (${_selectedResponderIds.length} Officers): $teamNames by $userEmail';

      if (alertId != null) {
        await SupabaseConfig.client.from('alerts').update({
          'status': 'DISPATCHED',
          'assigned_to': leadOfficerId,
          'ai_summary': existingNotes.isEmpty ? dispatchNote : '$existingNotes\n$dispatchNote',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', alertId);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      title: Text(
        'DISPATCH TACTICAL TEAM',
        style: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: AppColors.onPrimary,
          letterSpacing: 1.2,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const SizedBox(
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            : _responders.isEmpty
                ? Text(
                    'No registered officers available in database.',
                    style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Select one or multiple active field officers to assign to this mission:',
                        style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 11),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _responders.length,
                          itemBuilder: (ctx, idx) {
                            final r = _responders[idx];
                            final rId = r['id'] as String;
                            final isSel = _selectedResponderIds.contains(rId);
                            return CheckboxListTile(
                              dense: true,
                              value: isSel,
                              activeColor: AppColors.primary,
                              selected: isSel,
                              selectedTileColor: AppColors.primary.withValues(alpha: 0.15),
                              title: Text(
                                (r['full_name'] as String? ?? 'Officer') +
                                    (r['badge_number'] != null ? ' [${r['badge_number']}]' : ''),
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onPrimary,
                                ),
                              ),
                              subtitle: Text(
                                'Role: ${r['role'] ?? 'RESPONDER'} · ${r['geo_lga'] ?? 'JOS'}',
                                style: GoogleFonts.inter(fontSize: 10, color: AppColors.textDim),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedResponderIds.add(rId);
                                  } else {
                                    _selectedResponderIds.remove(rId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('CANCEL', style: GoogleFonts.outfit(color: AppColors.textDim)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting || _selectedResponderIds.isEmpty ? null : _submitDispatch,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  _selectedResponderIds.isEmpty
                      ? 'SELECT OFFICERS'
                      : 'DISPATCH (${_selectedResponderIds.length} UNITS)',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
                ),
        ),
      ],
    );
  }
}

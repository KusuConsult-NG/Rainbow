// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:local_auth/local_auth.dart' as local_auth;
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/alerts_feed.dart';
import 'package:rainbow_app/features/agent/alert_row.dart';
import 'package:rainbow_app/features/agent/responder_tier.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/auth_service.dart';
import 'package:rainbow_app/services/tts_service.dart';
import 'package:rainbow_app/shared/widgets/broadcast_hud.dart';
import 'package:rainbow_app/shared/widgets/rainbow_map.dart';

/// The responder's mission feed, with its own liveness attached.
///
/// This used to be a bare `.stream()` whose failures were indistinguishable
/// from "nothing is happening" — see `resilientAlertsFeed` for why that was a
/// safety problem rather than a cosmetic one.
final alertsStreamProvider = StreamProvider<AlertsFeed>((ref) {
  final auth = ref.watch(authProvider);
  final profile = auth.profile ?? {};
  final role = (profile['role'] as String? ?? '').toUpperCase();
  final geoLga = profile['geo_lga'] as String?;
  final geoWard = profile['geo_ward'] as String?;
  final geoPu = profile['geo_pu'] as String?;
  final userId = auth.user?.id;

  return supabaseAlertsFeed(SupabaseConfig.client).map((feed) {
    return feed.copyWith(rows: feed.rows.where((alert) {
      final aGeoLga = alert['geo_lga'] as String?;
      final aGeoWard = alert['geo_ward'] as String?;
      final aGeoPu = alert['geo_pu'] as String?;
      final aAssignedTo = alert['assigned_to'] as String?;
      final aAssignedResponders = (alert['assigned_responders'] as List<dynamic>?)?.cast<String>() ?? [];

      // 1. Directly assigned to officer or multi-unit squad -> ALWAYS SHOW
      if (userId != null && (aAssignedTo == userId || aAssignedResponders.contains(userId))) return true;
      if (aAssignedTo == 'HQ' || aAssignedTo == 'LGA' || aAssignedTo == 'WARD') {
        if (role.contains(aAssignedTo!) || role.contains('HQ') || role == 'ADMIN') return true;
      }

      // 2. State HQ Commanders -> ALWAYS SHOW ALL
      if (role.contains('STATE') || role.contains('HQ') || role == 'ADMIN') return true;

      // 3. LGA Commanders -> Show alerts matching LGA, unassigned, or escalated to LGA
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

      // No matching rule — don't show this alert to avoid delivering all
      // statewide data to every field device. The build-level filteredAlerts
      // handles any edge cases for assigned-to-me alerts.
      return false;
    }).toList(),);
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
        case ResponderTier.hq:
          return 'HQ COMMAND';
        // ignore: no_default_cases, Stylistic override to match system design
        default:
          return 'OPERATIONAL UNIT';
      }
    }
    return 'CITIZEN';
  }

  String get _assignedTier => assignedTierLabel(ref.watch(authProvider).tier);

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
    // The app bar advertised "LIVE MISSION FEED" with a lit indicator dot
    // unconditionally, which put a liveness claim directly above a feed that
    // may not be live. Read the real state and label it accordingly.
    final feedLiveness = ref.watch(alertsStreamProvider).valueOrNull?.liveness ??
        FeedLiveness.connecting;
    final feedIsLive = feedLiveness == FeedLiveness.live;
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
                                    tooltip: 'Open the command menu',
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
              // Scale to fit rather than clip: with four action icons in this
              // bar the fixed 18px title rendered as "OPERATION..." on an
              // ordinary phone.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _roleTitle,
                  maxLines: 1,
                  softWrap: false,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: feedIsLive
                          ? Colors.white
                          : AppColors.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        feedIsLive
                            ? 'LIVE MISSION FEED'
                            : feedLiveness == FeedLiveness.connecting
                                ? 'CONNECTING...'
                                : 'FEED NOT LIVE',
                        maxLines: 1,
                        softWrap: false,
                        style: GoogleFonts.outfit(
                          color: feedIsLive
                              ? Colors.white.withValues(alpha: 0.8)
                              : AppColors.warning,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                TtsService.instance.outputMode == AudioOutputMode.speaker
                    ? Icons.volume_up_rounded
                    : Icons.phone_in_talk_rounded,
                color: TtsService.instance.outputMode == AudioOutputMode.speaker
                    ? AppColors.success
                    : AppColors.warning,
              ),
              tooltip: TtsService.instance.outputMode == AudioOutputMode.speaker
                  ? 'AUDIO: LOUDSPEAKER'
                  : 'AUDIO: EARPIECE',
              onPressed: () async {
                await TtsService.instance.toggleAudioOutputMode();
                // The old `if (mounted) setState(...)` guarded only the
                // setState; the snackbar below used `context` unguarded after
                // the same await, so an unmount mid-toggle threw.
                //
                // Both checks are needed and they answer different questions:
                // `mounted` is the State's (setState needs it), `context.mounted`
                // is this builder context's (ScaffoldMessenger.of needs that one).
                if (!mounted || !context.mounted) return;
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 2),
                    backgroundColor: const Color(0xFF0F172A),
                    content: Text(
                      'TACTICAL AUDIO MODE: ${TtsService.instance.outputMode == AudioOutputMode.speaker ? "LOUDSPEAKER 🔊" : "STEALTH EARPIECE 🎧"}',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Switch between the map and the incident list',
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
                tooltip: 'Send a command broadcast',
                icon: const Icon(Icons.campaign_rounded, color: Colors.white),
                onPressed: () => context.push(AppRoutes.adminBroadcast),
              ),
            IconButton(
              tooltip: 'Sign out',
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
                Expanded(child: _buildMissionFeed()),
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


  /// The mission feed pane: alerts, responder telemetry, and the map/list
  /// switch.
  ///
  /// This watches the providers directly as `AsyncValue`s. It used to nest two
  /// `StreamBuilder`s over `provider.stream`, which riverpod deprecates and
  /// removes in 3.0.
  ///
  /// The mapping below is deliberately explicit rather than a bare `.value`,
  /// because the two APIs disagree about errors: `StreamBuilder` DROPS the last
  /// data when an error arrives, while `AsyncValue` RETAINS it. Inheriting
  /// riverpod's behaviour unexamined would leave the last known rows on screen
  /// still labelled `live` after the feed had died — the pane would assert a
  /// liveness it no longer has. On error this keeps the old contract: no rows,
  /// and say so.
  Widget _buildMissionFeed() {
    final alertsAsync = ref.watch(alertsStreamProvider);
    final trackingAsync = ref.watch(trackingStreamProvider);

    // Nothing has arrived yet — the old `ConnectionState.waiting` branch.
    if (alertsAsync.isLoading && !alertsAsync.hasValue) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    // A stream error must never fall through to an empty list: empty renders
    // as ALL CLEAR, and "the feed broke" is not "there are no incidents".
    final feed = switch (alertsAsync) {
      AsyncError(:final error) => AlertsFeed(
          rows: const [],
          liveness: FeedLiveness.degraded,
          error: error.toString(),
        ),
      AsyncData(:final value) => value,
      // A refresh in flight keeps the rows it already had.
      AsyncValue(:final value?) => value,
      _ => AlertsFeed.initial,
    };

    // Same rule for telemetry: only settled data counts as positions we are
    // willing to draw a responder at.
    final telemetryList = switch (trackingAsync) {
      AsyncData(:final value) => value,
      _ => const <Map<String, dynamic>>[],
    };

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
    final allDocs = feed.rows;
    final filteredAlerts = allDocs.where((alert) {
      // `uid` is null whenever the session cannot be read — AuthService
      // .currentUserId catches and returns null. Without this guard the
      // comparison becomes `null == null` for every alert that carries no
      // assignee, which returns true and waves the row past ALL tier scoping
      // below. A transient auth read failure would show every responder every
      // alert in the state. You cannot be assigned something when we do not
      // know who you are.
      if (alertIsAssignedTo(alert, uid)) return true;


      final auth = ref.watch(authProvider);

      // OWNER TIER AND EVERYONE ABOVE.
      //
      // Before this the filter was geography alone, and every branch of it
      // ended in an `alert['geo_*'] == null` fail-open. Since nothing
      // populated the geography, that fallback was the ONLY path that ever
      // ran: every alert was visible to every responder at every tier, and
      // the chain's ownership meant nothing on screen.
      //
      // Geography still scopes WHERE an officer looks; the tier now scopes
      // WHAT they are shown of it.
      if (!tierCanSee(
        viewerTier: assignedTierLabel(auth.tier),
        alertTier: alert['assigned_tier'] as String?,
      )) {
        return false;
      }

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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _showMap
          ? _buildMap(filteredAlerts, responderMarkers)
          : _buildList(filteredAlerts, feed),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> alerts, AlertsFeed feed) {
    if (alerts.isEmpty) {
      // "ALL CLEAR" is a claim about the world, and it may only be made when
      // the feed is actually live. When it is not, say so — a responder acts
      // very differently on "nothing is happening" than on "I am not being
      // told what is happening".
      final live = feed.liveness == FeedLiveness.live;
      final connecting = feed.liveness == FeedLiveness.connecting;

      final (icon, colour, headline, detail) = live
          ? (Icons.radar_rounded, AppColors.outline,
              'ALL CLEAR - NO ACTIVE MISSIONS', null)
          : connecting
              ? (Icons.radar_rounded, AppColors.outline,
                  'CONNECTING TO MISSION FEED', null)
              : (
                  Icons.cloud_off_rounded,
                  AppColors.warning,
                  'MISSION FEED NOT LIVE',
                  'Cannot confirm all clear. Retrying, and falling back to '
                      'periodic refresh — use radio to verify status.',
                );

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: colour),
              const SizedBox(height: 24),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: live || connecting ? AppColors.textDim : AppColors.warning,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  fontSize: 12,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 12),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppColors.textDim,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final criticalCount = alerts.where((a) => a['severity'] == 'CRITICAL' || a['status'] == 'DURESS').length;
    final escalatedCount = alerts.where((a) => a['status'] == 'ESCALATED').length;
    // A populated but stale list is the more dangerous of the two degraded
    // cases: it looks authoritative. Say plainly that it may be out of date.
    final stale = feed.liveness == FeedLiveness.degraded;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 120, 16, 40),
      itemCount: alerts.length + (stale ? 2 : 1),
      itemBuilder: (context, rawIndex) {
        if (stale && rawIndex == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.warning, width: 1.2),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_off_rounded,
                    size: 18, color: AppColors.warning,),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'FEED NOT LIVE - list may be out of date, refreshing periodically',
                    style: GoogleFonts.inter(
                      color: AppColors.warning,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final index = stale ? rawIndex - 1 : rawIndex;
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
                        // "All systems active" is a claim about the system,
                        // not about the alert count — and it must not be made
                        // while the feed this panel summarises is degraded.
                        // It sat directly beneath the FEED NOT LIVE banner and
                        // flatly contradicted it.
                        criticalCount > 0
                            ? '$criticalCount Critical Incidents require immediate field unit dispatch or HQ escalation.'
                            : stale
                                ? 'Feed is not live; this summary may be incomplete. $escalatedCount escalated alerts in the last known state.'
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

    // CENTRE ON WHAT THE MAP IS DRAWING, not on Jos.
    //
    // This was `const LatLng(9.9285, 8.8923)` at zoom 13 — street level, pinned
    // to Jos. An officer in Wase or Shendam opened their tactical map on a city
    // 150km away with their own incidents off-screen, and had to pan to find the
    // emergency they were being dispatched to. The map was drawing markers it
    // was not looking at.
    //
    // This is NOT the C-5 mistake and must not be confused with it: a viewport
    // centre is where the camera starts, never a position attached to a report.
    // An alert with no fix still has no coordinates and is still absent from
    // this map — it belongs in HQ's unlocated-alerts panel, not at a guessed
    // point on a responder's screen.
    final plotted = <LatLng>[
      for (final data in alerts)
        if ((data['latitude'] ?? data['lat']) is double &&
            (data['longitude'] ?? data['lng']) is double)
          LatLng(
            (data['latitude'] ?? data['lat']) as double,
            (data['longitude'] ?? data['lng']) as double,
          ),
    ];

    return RainbowMap(
      // The mean of the incidents on screen. With one incident that is the
      // incident; with several it is between them, which is the view a
      // dispatcher wants.
      center: plotted.isEmpty
          // Nothing to look at: the centre of Plateau State at a zoom that shows
          // the state, so the map says "no located incidents" rather than
          // "no incidents in this street".
          ? const LatLng(9.2182, 9.5179)
          : LatLng(
              plotted.map((p) => p.latitude).reduce((a, b) => a + b) /
                  plotted.length,
              plotted.map((p) => p.longitude).reduce((a, b) => a + b) /
                  plotted.length,
            ),
      initialZoom: plotted.isEmpty
          ? 8
          : plotted.length == 1
              ? 14
              : 10,
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
    final assignedTier = assignedTierLabel(auth.tier);

    final status = alert['status'] ?? 'OPEN';
    final severity = alert['severity'] ?? 'MEDIUM';
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    // Same null trap as the tier filter: with no session, `null == null` marks
    // every unassigned alert as this officer's own and highlights the lot.
    final isMine = uid != null &&
        alertIsAssignedTo(alert, uid);

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
                          // `created_at` is the column, is NOT NULL, and has a
                          // default. The three fallbacks that used to follow it
                          // — createdAt, reportedAt, timestamp — name nothing
                          // this table has, so they were unreachable code that
                          // read as robustness.
                          alert['created_at'],
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
                  // Media evidence thumbnails — Phase 7
                  Builder(builder: (context) {
                    final rawMediaUrls = alert['media_urls'] as List<dynamic>?;
                    final mediaUrls = rawMediaUrls?.cast<String>() ?? [];
                    if (mediaUrls.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          'EVIDENCE (${mediaUrls.length} FILE${mediaUrls.length > 1 ? 'S' : ''})',
                          style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textDim, letterSpacing: 1),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: mediaUrls.length,
                            itemBuilder: (ctx, i) {
                              final url = mediaUrls[i];
                              final urlLower = url.toLowerCase();
                              final isVideo = urlLower.contains('/video/') || urlLower.endsWith('.mp4') || urlLower.endsWith('.mov');
                              final isAudio = urlLower.endsWith('.m4a') || urlLower.endsWith('.mp3') || urlLower.endsWith('.wav');
                              return GestureDetector(
                                onTap: () => showDialog<void>(context: ctx, builder: (_) => Dialog(
                                  backgroundColor: Colors.black,
                                  child: isVideo
                                      ? const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 64))
                                      : isAudio
                                          ? const Center(child: Icon(Icons.audiotrack, color: Colors.white, size: 64))
                                          : InteractiveViewer(child: Image.network(url)),
                                ),),
                                child: Container(
                                  width: 80,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.outline)),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: isVideo
                                        ? const Center(child: Icon(Icons.play_circle_outline, color: AppColors.primary, size: 32))
                                        : isAudio
                                            ? const Center(child: Icon(Icons.audiotrack, color: AppColors.primary, size: 32))
                                            : Image.network(url, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: AppColors.textDim)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },),
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
                      // HQ IS THE TIER THAT MOST NEEDS THIS.
                      //
                      // This read `assignedTier == 'WARD' || 'LGA'`, so the one
                      // rung with no dispatch control was HQ — the rung whose
                      // whole purpose is to override when the chain below it is
                      // not responding. An incident that climbed all the way up
                      // because nobody answered arrived at the only desk that
                      // could not send anyone to it.
                      //
                      // A polling-unit officer is still excluded, deliberately:
                      // they ARE the field unit, and ENGAGE self-deploys them.
                      if (canDispatchFrom(assignedTier)) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Dispatch Unit',
                          onPressed: () async {
                            await showDialog<bool>(
                              context: context,
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
                      // No up-arrow at HQ: there is nothing above it, and the
                      // dialog behind this button would have offered to escalate
                      // HQ to HQ. `escalationTargetFor` is the single answer to
                      // "is there a rung above me", so the button and the dialog
                      // cannot disagree.
                      if (escalationTargetFor(assignedTier) != null) ...[
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
                      ],
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Secure Chat',
                        onPressed: () {
                          unawaited(context.push(AppRoutes.secureChat, extra: alert));
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
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    final isAssignedToMe = alertIsAssignedTo(alert, uid);

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
                  final speechText = 'Mission accepted. Emergency type: $type. Threat details: $desc.';
                  unawaited(TtsService.instance.speak(speechText));
                }

                if (alertId != null) {
                  await SupabaseConfig.client.from('alerts').update({
                    'status': nextStatus,
                    if ((status == 'OPEN' || status == 'ACTIVE' || status == 'PENDING') && uid != null)
                      'assigned_to': uid,
                    // STOP THE ESCALATION CLOCK.
                    //
                    // `escalate_overdue_alerts()` climbs any alert whose tier
                    // has held it past the configured timeout AND whose
                    // `acknowledged_at` is null. Nothing in either app ever
                    // wrote `acknowledged_at`, so that guard could not fire:
                    // an officer who accepted a mission and set out had it
                    // escalated out from under them two minutes later, and the
                    // tier above was told nobody had responded.
                    //
                    // Status alone cannot carry this. The job cannot key off
                    // 'ACKNOWLEDGED' because an alert legitimately moves on to
                    // ON_ROUTE and ON_SITE, and those must not restart the
                    // clock either. A timestamp that is set once and stays set
                    // is the whole point of the column.
                    if (nextStatus == 'ACKNOWLEDGED' && uid != null) ...{
                      'acknowledged_at': DateTime.now().toIso8601String(),
                      'acknowledged_by': uid,
                    },
                    'updated_at': DateTime.now().toIso8601String(),
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
          // `assignedTier != 'HQ'` guarded this whole row, so HQ lost DISPATCH
          // UNIT along with the escalate button it genuinely has no use for.
          // Split the two: escalation is gated on there being a rung above,
          // dispatch on the tier being one that commands field units.
          if (status != 'RESOLVED' &&
              (canDispatchFrom(assignedTier) ||
                  escalationTargetFor(assignedTier) != null)) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (canDispatchFrom(assignedTier)) ...[
                  Expanded(
                    child: _TacticalButton(
                      label: 'DISPATCH UNIT',
                      color: AppColors.primary,
                      icon: Icons.local_police_rounded,
                      onTap: () => verifyAndExecute(() async {
                        onAction();
                        final success = await showDialog<bool>(
                          context: context,
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
                if (escalationTargetFor(assignedTier) != null)
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
  Map<String, dynamic>? _targetCommander; // resolved officer to escalate to
  List<Map<String, dynamic>> _availableCommanders = [];
  bool _loadingCommanders = true;

  final List<String> _presets = [
    'Tactical Resource Exhaustion',
    'Overwhelming Threat Level',
    'Medical Overload',
    'Communications Failure',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_loadTargetCommanders());
  }

  Future<void> _loadTargetCommanders() async {
    final targetTier = escalationTargetFor(widget.assignedTier) ?? 'HQ';

    // Map tier to role string
    final roleMap = {'WARD': 'WARD_COMMAND', 'LGA': 'LGA_COMMAND', 'HQ': 'HQ_COMMAND'};
    final targetRole = roleMap[targetTier] ?? 'HQ_COMMAND';

    try {
      // Get the alert's geo_lga to find commanders in the right area
      final alertLga = widget.alertDoc['geo_lga'] as String?;
      var query = SupabaseConfig.client
          .from('profiles')
          .select('id, full_name, role, geo_lga, geo_ward')
          .eq('role', targetRole);

      // For ward/LGA tier, narrow to same LGA
      if (alertLga != null && targetTier != 'HQ') {
        query = query.eq('geo_lga', alertLga);
      }

      final res = await query.limit(20);
      final commanders = List<Map<String, dynamic>>.from(res as List);
      if (mounted) {
        setState(() {
          _availableCommanders = commanders;
          _targetCommander = commanders.isNotEmpty ? commanders.first : null;
          _loadingCommanders = false;
        });
      }
    } catch (e) {
      debugPrint('[ESCALATION_LOAD_ERR] $e');
      if (mounted) setState(() => _loadingCommanders = false);
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetTier = escalationTargetFor(widget.assignedTier) ?? 'HQ';

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
              if (_loadingCommanders)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: LinearProgressIndicator(),
                )
              else if (_availableCommanders.isNotEmpty) ...[
                Text('ESCALATE TO', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                const SizedBox(height: 8),
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: _targetCommander,
                  dropdownColor: AppColors.surfaceContainerHigh,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.outline)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.outline)),
                  ),
                  style: GoogleFonts.outfit(color: AppColors.onBackground, fontSize: 13),
                  items: _availableCommanders.map((c) {
                    final name = c['full_name'] as String? ?? 'Officer';
                    final lga = c['geo_lga'] as String? ?? '';
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: c,
                      child: Text('$name${lga.isNotEmpty ? ' ($lga)' : ''}'),
                    );
                  }).toList(),
                  onChanged: (val) { if (val != null) setState(() => _targetCommander = val); },
                ),
                const SizedBox(height: 16),
              ],
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

    final targetTier = escalationTargetFor(widget.assignedTier) ?? 'HQ';

    try {
      final alertId = widget.alertDoc['id'] as String?;
      final user = SupabaseConfig.client.auth.currentUser;
      final userEmail = user?.email ?? 'STAFF';

      // Resolve the target: use selected commander UUID, fall back to tier string
      final targetCommanderId = _targetCommander?['id'] as String?;
      final targetCommanderName = _targetCommander?['full_name'] as String? ?? targetTier;

      // Build structured escalation log entry
      final escalationEntry = {
        'from_tier': widget.assignedTier,
        'to_tier': targetTier,
        'to_officer_id': targetCommanderId,
        'to_officer_name': targetCommanderName,
        'reason': _selectedReason,
        'notes': _notesController.text.trim(),
        'by_email': userEmail,
        'by_id': user?.id,
        'at': DateTime.now().toIso8601String(),
      };

      // Read existing escalation_log
      final existing = await SupabaseConfig.client
          .from('alerts')
          .select('escalation_log, ai_summary')
          .eq('id', alertId ?? '')
          .maybeSingle();

      final existingLog = (existing?['escalation_log'] as List<dynamic>?) ?? [];
      final newLog = [...existingLog, escalationEntry];

      final existingSummary = existing?['ai_summary'] as String? ?? '';
      final note = '[ESCALATED TO $targetTier — $targetCommanderName] Reason: $_selectedReason. ${_notesController.text.trim()} (by $userEmail)';

      final updatePayload = <String, dynamic>{
        'status': 'ESCALATED',
        'severity': targetTier == 'HQ' ? 'CRITICAL' : 'HIGH',
        // `assigned_to` is a uuid column. This used to send
        // `targetCommanderId ?? targetTier`, so with no specific commander
        // chosen it wrote 'LGA' to it — PostgreSQL rejects that, and because
        // this is one UPDATE the whole escalation went down with it: status,
        // severity, the log and the audit note. Null when nobody specific is
        // taking it; the tier below says who owns it.
        'assigned_to': targetCommanderId,
        // The tier now has its own column. It was written to
        // `escalated_to_agency`, which is what the agency portal filters on —
        // so an internal escalation to LGA sat in the same field as a handover
        // to the police, and neither read cleanly.
        'assigned_tier': targetTier,
        // RESTART THE CLOCK FOR THE TIER TAKING IT.
        //
        // The timeout is measured from `tier_assigned_at`, and this UPDATE did
        // not touch it — so an alert handed up to the WARD carried the
        // timestamp from when it was first inserted at the POLLING UNIT. The
        // WARD's five-minute window was already spent before the WARD saw it,
        // and the next run of `escalate_overdue_alerts()` moved it straight on
        // to the LGA, then to HQ. A single manual escalation of an alert more
        // than ten minutes old landed at HQ within two minutes of cron,
        // skipping every rung it was supposed to climb.
        //
        // `acknowledged_*` clears for the same reason: the officer who
        // acknowledged it at the tier below is not the officer who has it now,
        // and leaving their acknowledgement in place freezes the clock
        // permanently at the new tier — the alert would then never escalate
        // again, no matter how long HQ's predecessors sat on it.
        'tier_assigned_at': DateTime.now().toIso8601String(),
        'acknowledged_at': null,
        'acknowledged_by': null,
        'escalation_log': newLog,
        'ai_summary': existingSummary.isEmpty ? note : '$existingSummary\n$note',
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (alertId != null) {
        await SupabaseConfig.client
            .from('alerts')
            .update(updatePayload)
            .eq('id', alertId);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('[ESCALATION_ERROR] Failed to escalate: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Escalation failed: $e'), backgroundColor: AppColors.error),
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
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'ESCALATE TO HIGHER COMMAND',
                  style: GoogleFonts.outfit(
                    color: AppColors.error,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
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
    _ctrl.repeat();
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
    unawaited(_loadResponders());
  }

  Future<void> _loadResponders() async {
    try {
      final res = await SupabaseConfig.client
          .from('profiles')
          .select('id, full_name, badge_number, role, geo_lga, geo_ward');

      final rawList = List<Map<String, dynamic>>.from(res as List);
      final filtered = rawList.where((r) {
        final role = (r['role'] as String? ?? '').toUpperCase();
        return role != 'CITIZEN' && role.isNotEmpty;
      }).toList();

      if (mounted) {
        setState(() {
          _responders = filtered;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[DISPATCH_LOAD_ERR] Failed to fetch responder profiles: $e');
      if (mounted) {
        setState(() {
          _responders = [];
          _isLoading = false;
        });
      }
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
          'assigned_responders': _selectedResponderIds.toList(),
          'ai_summary': existingNotes.isEmpty ? dispatchNote : '$existingNotes\n$dispatchNote',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', alertId);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dispatch failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      title: Text(
        'DISPATCH TACTICAL TEAM',
        style: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          color: Colors.white,
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
                    style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Select active field officers to assign to this mission squad:',
                        style: GoogleFonts.inter(color: const Color(0xFFE2E8F0), fontSize: 11),
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
                              selectedTileColor: AppColors.primary.withValues(alpha: 0.25),
                              title: Text(
                                (r['full_name'] as String? ?? 'Officer') +
                                    (r['badge_number'] != null ? ' [${r['badge_number']}]' : ''),
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                'Role: ${r['role'] ?? 'RESPONDER'} · ${r['geo_lga'] ?? 'JOS'}',
                                style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                              ),
                              onChanged: (val) {
                                setState(() {
                                  if (val ?? false) {
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

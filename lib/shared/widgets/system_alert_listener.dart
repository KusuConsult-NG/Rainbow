import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/broadcast_targeting.dart';
import 'package:rainbow_app/services/user_service.dart';

/// Documentation for this public member.
final systemAlertsStreamProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return SupabaseConfig.client
      .from('system_alerts')
      .stream(primaryKey: ['id']).eq('is_active', true);
});

/// Documentation for this public member.

class SystemAlertListener extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const SystemAlertListener({required this.child, super.key});

  /// Documentation for this public member.
  final Widget child;

  @override
  ConsumerState<SystemAlertListener> createState() =>
      _SystemAlertListenerState();
}

class _SystemAlertListenerState extends ConsumerState<SystemAlertListener> {
  final Set<String> _dismissedAlerts = {};

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(userProfileProvider).value;
    final systemAlertsAsync = ref.watch(systemAlertsStreamProvider);

    return Stack(
      children: [
        widget.child,
        systemAlertsAsync.when(
          data: (allAlerts) {
            if (allAlerts.isEmpty) return const SizedBox.shrink();

            final userRole = userProfile?['role'] as String? ?? 'CITIZEN';

            // WHO THIS BANNER IS FOR — decided by the same function the HUD
            // uses.
            //
            // This had its own filter, and it read `target_type` and
            // `target_value`. The HQ console writes neither: it writes
            // `target_audience` plus `target_lga` / `target_ward` /
            // `target_pu`.
            // So `targetType` fell to its 'ALL' default on every advisory the
            // console has ever sent, the next line returned true, and this
            // banner — which wraps EVERY screen in the app — showed every
            // advisory to every user. An alert composed for citizens in one
            // ward went to every responder in Plateau.
            //
            // It also read `geo_lgas` and `geo_wards`, plural, which no
            // migration defines, so those lists were always empty: the two
            // branches below them could only ever have refused.
            //
            // That is the defect `broadcast_targeting.dart` was written to fix.
            // The fix landed in `broadcastProvider`, which feeds BroadcastHud,
            // and this second reader was missed — so the app had one surface
            // that honoured the targeting and one that ignored it, from the
            // same table. `broadcastReaches` also drops an EXPIRED advisory,
            // which
            // this never did: the stream only filters `is_active`.
            final recipient = BroadcastRecipient(
              // Everything that is not a citizen account is a responder, the
              // same rule `resolveRole` applies in auth_provider.dart.
              isResponder: userRole != 'CITIZEN' && userRole != 'USER',
              geoLga: userProfile?['geo_lga'] as String?,
              geoWard: userProfile?['geo_ward'] as String?,
              geoPu: userProfile?['geo_pu'] as String?,
            );

            final relevantAlerts = allAlerts.where((doc) {
              final alertId = doc['id'] as String;

              // Dismissed first. This check used to be the LAST line, after the
              // early returns for HQ and for target 'ALL' — so a statewide
              // advisory, the commonest kind, could never be dismissed: the
              // button recorded the id and the banner came straight back. The
              // control sweep found it doing nothing.
              if (_dismissedAlerts.contains(alertId)) return false;

              // HQ sees every advisory, including ones addressed elsewhere:
              // they are the desk that sent them and the desk that withdraws
              // them.
              if (userRole == 'HQ_OFFICER') return true;

              return broadcastReaches(doc, recipient);
            }).toList();

            if (relevantAlerts.isEmpty) return const SizedBox.shrink();

            final firstDoc = relevantAlerts.first;
            final alertId = firstDoc['id'] as String;
            final severity =
                (firstDoc['severity'] as String? ?? 'INFO').toUpperCase();
            final message = firstDoc['message']?.toString() ??
                'Operational Advisory Active';

            var bgColor = AppColors.info;
            var icon = Icons.info_outline_rounded;

            if (severity == 'CRITICAL') {
              bgColor = AppColors.danger;
              icon = Icons.warning_amber_rounded;
            } else if (severity == 'HIGH') {
              bgColor = AppColors.warning;
              icon = Icons.security_rounded;
            }

            return Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 16,
              right: 16,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: bgColor.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(icon, color: Colors.white, size: 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'SYSTEM ADVISORY: $severity',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.7),
                                letterSpacing: 1.5,
                              ),
                            ),
                            Text(
                              message.toUpperCase(),
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: Colors.white,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Dismiss this alert',
                        onPressed: () {
                          if (mounted) {
                            setState(() {
                              _dismissedAlerts.add(alertId);
                            });
                          }
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/user_service.dart';

/// Documentation for this public member.
final systemAlertsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return SupabaseConfig.client
      .from('system_alerts')
      .stream(primaryKey: ['id'])
      .eq('is_active', true);
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
            final assignedLgas =
                List<String>.from((userProfile?['geo_lgas'] as List?) ?? []);
            final assignedWards =
                List<String>.from((userProfile?['geo_wards'] as List?) ?? []);

            final relevantAlerts = allAlerts.where((doc) {
              final targetType = doc['target_type'] as String? ?? 'ALL';
              final targetValue = doc['target_value'] as String? ?? '';
              final alertId = doc['id'] as String;

              if (userRole == 'HQ_OFFICER' || targetType == 'ALL') return true;

              if (targetType == 'LGA') {
                return assignedLgas.contains(targetValue);
              }
              if (targetType == 'WARD') {
                return assignedWards.contains(targetValue);
              }

              return mounted && !_dismissedAlerts.contains(alertId);
            }).toList();

            if (relevantAlerts.isEmpty) return const SizedBox.shrink();

            final firstDoc = relevantAlerts.first;
            final alertId = firstDoc['id'] as String;
            final severity =
                (firstDoc['severity'] as String? ?? 'INFO').toUpperCase();
            final message =
                firstDoc['message']?.toString() ?? 'Operational Advisory Active';

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

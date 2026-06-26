// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// GAP-G fix: accepts an optional alertId and writes the citizen's
/// post-incident feedback back to the alert document.
Future<void> showSafetyFeedback(
  BuildContext context, {
  String? alertId,
}) async {
  await HapticFeedback.lightImpact();
  if (!context.mounted) return;
  return showDialog(
    context: context,
    builder: (ctx) => _SafetyFeedbackDialog(alertId: alertId),
  );
}

class _SafetyFeedbackDialog extends StatefulWidget {
  const _SafetyFeedbackDialog({this.alertId});
  final String? alertId;

  @override
  State<_SafetyFeedbackDialog> createState() => _SafetyFeedbackDialogState();
}

class _SafetyFeedbackDialogState extends State<_SafetyFeedbackDialog> {
  bool _saving = false;

  Future<void> _submitFeedback(String status) async {
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;

      // Write to the alert doc if we have an ID
      if (widget.alertId != null) {
        if (widget.alertId!.startsWith('OFFLINE_')) {
          // It's offline, so update the offline queue
          final prefs = await SharedPreferences.getInstance();
          final offlineQueue =
              prefs.getStringList('offline_alerts_queue') ?? <String>[];
          final updatedQueue = <String>[];
          var foundInQueue = false;
          for (final jsonStr in offlineQueue) {
            try {
              final alertData = jsonDecode(jsonStr) as Map<String, dynamic>;
              if (alertData['local_id'] == widget.alertId) {
                alertData['citizenFeedback'] = status;
                alertData['feedbackAt'] = DateTime.now().toIso8601String();
                alertData['feedbackUid'] = uid;
                foundInQueue = true;
              }
              updatedQueue.add(jsonEncode(alertData));
              // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
            } catch (_) {
              updatedQueue.add(jsonStr);
            }
          }
          await prefs.setStringList('offline_alerts_queue', updatedQueue);

          // If it was already synced and removed from the queue, update it in Firestore
          if (!foundInQueue) {
            final snap = await FirebaseFirestore.instance
                .collection('alerts')
                .where('local_id', isEqualTo: widget.alertId)
                .limit(1)
                .get();
            if (snap.docs.isNotEmpty) {
              await snap.docs.first.reference.update({
                'citizenFeedback': status,
                'feedbackAt': FieldValue.serverTimestamp(),
                'feedbackUid': uid,
              });
            }
          }
        } else {
          await FirebaseFirestore.instance
              .collection('alerts')
              .doc(widget.alertId)
              .update({
            'citizenFeedback': status,
            'feedbackAt': FieldValue.serverTimestamp(),
            'feedbackUid': uid,
          });
        }
      }

      // Also write to user profile for quick HQ lookup
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {
            'lastFeedback': status,
            'lastFeedbackAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[SYS_WARN] Safety feedback write failed: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: Colors.white.withAlpha(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.favorite_rounded,
              color: AppColors.primary,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Are you safe now?',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'We noticed an emergency was triggered recently. '
              'Your status update will be transmitted to HQ.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            if (_saving)
              const CircularProgressIndicator(color: AppColors.primary)
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            unawaited(HapticFeedback.selectionClick());
                            unawaited(_submitFeedback('NEED_HELP'));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                'No, need help',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            unawaited(HapticFeedback.heavyImpact());
                            unawaited(_submitFeedback('SAFE'));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.success.withAlpha(100),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                "Yes, I'm safe",
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Third option: injured
                  GestureDetector(
                    onTap: () {
                      unawaited(HapticFeedback.heavyImpact());
                      unawaited(_submitFeedback('INJURED'));
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Injured — need medical support',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/router/safe_pop.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

class MissionResolutionScreen extends ConsumerStatefulWidget {
  const MissionResolutionScreen({required this.alertData, super.key});

  final Map<String, dynamic> alertData;

  @override
  ConsumerState<MissionResolutionScreen> createState() =>
      _MissionResolutionScreenState();
}

class _MissionResolutionScreenState
    extends ConsumerState<MissionResolutionScreen> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitResolution() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final alertId = widget.alertData['id'] as String;
      final user = SupabaseConfig.client.auth.currentUser;
      final email = user?.email ?? 'OFFICER';

      // The debrief goes in its OWN column.
      //
      // It used to be appended to `ai_summary` as '[RESOLVED DEBRIEF] ...', which
      // made that column carry three unrelated kinds of content — AI triage
      // notes, the [AI CLASSIFICATION APPLIED] lines, and human debriefs — so
      // "what did the responder say happened", the question an inquiry asks,
      // needed string-parsing to answer.
      //
      // Worse, the append read `widget.alertData['ai_summary']`: the copy loaded
      // when this screen OPENED. Anything written to it since — a classification
      // applied by HQ while the officer was typing — was erased by submitting the
      // debrief. Not a race; a guaranteed overwrite, the same shape as the
      // media_urls defect. Writing to its own column removes the read entirely.
      await SupabaseConfig.client.from('alerts').update({
        'status': 'RESOLVED',
        'resolved_by': email,
        'resolved_at': DateTime.now().toIso8601String(),
        'debrief': text,
        'debrief_by': user?.id,
        'debrief_at': DateTime.now().toIso8601String(),
      }).eq('id', alertId);

      if (!mounted) return;
      // The debrief is already SAVED at this point, so a throw here would
      // leave the officer looking at a form that appears to have failed.
      context.popOrGo(AppRoutes.agentDashboard);
      // ignore: avoid_catches_without_on_clauses, any failure is the same answer
      // to the officer: it did not save, do not walk away.
    } catch (e) {
      debugPrint('[RESOLUTION_ERR] Resolution update failed: $e');
      // TOLD, not just logged. This only debugPrinted, so a refused write left
      // the officer looking at the same form with no explanation — and an officer
      // who believes their debrief is filed does not write it again.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'NOT SAVED. Your debrief is still here — check your connection and '
              'submit again.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'MISSION DEBRIEF & RESOLUTION',
        subtitle: 'CLOSING OPERATIONAL REPORT',
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESOLUTION NOTES & AFTER-ACTION DEBRIEF',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textDim,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 5,
              style: GoogleFonts.inter(color: AppColors.onBackground),
              decoration: InputDecoration(
                hintText: 'Enter after-action tactical notes...',
                hintStyle: GoogleFonts.inter(color: AppColors.textDim),
                filled: true,
                fillColor: AppColors.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitResolution,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isSubmitting ? 'TRANSMITTING...' : 'MARK MISSION AS RESOLVED',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
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

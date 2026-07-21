// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
      await SupabaseConfig.client.from('alerts').update({
        'status': 'RESOLVED',
        'citizen_feedback': text,
      }).eq('id', alertId);

      if (!mounted) return;
      context.pop();
    } catch (e) {
      debugPrint('[RESOLUTION_ERR] Resolution update failed: $e');
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

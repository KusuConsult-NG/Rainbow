// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

class UninstallRequestScreen extends ConsumerStatefulWidget {
  const UninstallRequestScreen({super.key});

  @override
  ConsumerState<UninstallRequestScreen> createState() =>
      _UninstallRequestScreenState();
}

class _UninstallRequestScreenState
    extends ConsumerState<UninstallRequestScreen> {
  /// This screen's text in the chosen language.
  String _t(String key) => Translations.get(key, ref.read(languageProvider));

  final _remarksCtrl = TextEditingController();
  bool _isSubmitting = false;
  String _reason = 'TRANSFER';

  @override
  void dispose() {
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    setState(() => _isSubmitting = true);
    final reason = _reason;
    final remarks = _remarksCtrl.text;
    
    try {
      final user = ref.read(authProvider).user;
      final userId = user?.id;
      if (userId == null) throw Exception('No authenticated user');

      await SupabaseConfig.client.from('uninstall_requests').insert({
        'user_id': userId,
        'reason': reason,
        'remarks': remarks,
      });

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('uninst_submitted')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      // It said "recorded locally ... HQ will review upon connectivity".
      // Nothing is stored on the phone and nothing retries, so the request
      // was simply lost while the officer believed it was pending.
      debugPrint('[UNINSTALL_REQ] not sent: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('uninst_not_sent')),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Redraw when the language changes; _t reads it.
    ref.watch(languageProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: _t('uninst_title'),
        subtitle: _t('uninst_subtitle'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('uninst_category'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textDim,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              dropdownColor: AppColors.surfaceContainer,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
              ),
              style: const TextStyle(color: AppColors.onBackground),
              // The values are what is stored; only the labels are translated.
              items: [
                DropdownMenuItem(value: 'TRANSFER', child: Text(_t('uninst_transfer'))),
                DropdownMenuItem(value: 'RETIREMENT', child: Text(_t('uninst_retirement'))),
                DropdownMenuItem(value: 'PHONE_CHANGE', child: Text(_t('uninst_phone_change'))),
                DropdownMenuItem(value: 'MISCONDUCT', child: Text(_t('uninst_misconduct'))),
                DropdownMenuItem(value: 'OTHER', child: Text(_t('uninst_other'))),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _reason = val);
              },
            ),
            const SizedBox(height: 16),
            Text(
              _t('uninst_reason'),
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textDim,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remarksCtrl,
              maxLines: 4,
              style: GoogleFonts.inter(color: AppColors.onBackground),
              decoration: InputDecoration(
                hintText: _t('uninst_reason_hint'),
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
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _isSubmitting ? _t('uninst_sending') : _t('uninst_submit'),
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

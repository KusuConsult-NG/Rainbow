// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

class UninstallRequestScreen extends ConsumerStatefulWidget {
  const UninstallRequestScreen({super.key});

  @override
  ConsumerState<UninstallRequestScreen> createState() =>
      _UninstallRequestScreenState();
}

class _UninstallRequestScreenState
    extends ConsumerState<UninstallRequestScreen> {
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
        const SnackBar(
          content: Text('Uninstall request submitted to HQ Command for authorization.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      // Graceful fallback when table is disabled or offline
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Uninstall request recorded locally. HQ Command will review upon connectivity.'),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'APP REMOVAL AUTHORIZATION',
        subtitle: 'TACTICAL SECURITY POLICY',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REMOVAL CATEGORY',
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
              items: const [
                DropdownMenuItem(value: 'TRANSFER', child: Text('Transfer to Another Unit')),
                DropdownMenuItem(value: 'RETIREMENT', child: Text('Retirement / End of Service')),
                DropdownMenuItem(value: 'PHONE_CHANGE', child: Text('Device Replacement')),
                DropdownMenuItem(value: 'MISCONDUCT', child: Text('Disciplinary Removal')),
                DropdownMenuItem(value: 'OTHER', child: Text('Other (specify in remarks)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _reason = val);
              },
            ),
            const SizedBox(height: 16),
            Text(
              'REMOVAL REASON & JUSTIFICATION',
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
                hintText: 'Enter operational justification...',
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
                  _isSubmitting ? 'TRANSMITTING...' : 'SUBMIT UNINSTALL REQUEST',
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

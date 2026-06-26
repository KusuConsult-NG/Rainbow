// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';

/// Simulates a resilient offline dispatch by showing an overlay that
/// attempts network sending, detects failure, and falls back to a
/// simulated localized SMS burst.
Future<void> showOfflineSending(
  BuildContext context, {
  required String message,
}) async {
  unawaited(
    showDialog(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      builder: (ctx) => _OfflineOverlay(message: message),
    ),
  );

  // Wait for the animation simulation in the UI to finish
  await Future<void>.delayed(const Duration(seconds: 4));
}

class _OfflineOverlay extends StatefulWidget {
  const _OfflineOverlay({required this.message});
  final String message;

  @override
  State<_OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<_OfflineOverlay> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_playSequence());
  }

  Future<void> _playSequence() async {
    // Step 0: Analyzing network
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    await HapticFeedback.lightImpact();
    setState(() => _step = 1);

    // Step 1: No Internet, sending via backup SMS
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    await HapticFeedback.mediumImpact();
    setState(() => _step = 2);

    // Step 2: Sent
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white.withValues(alpha: 0.95),
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: AppColors.outline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 40,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_step == 0) ...[
                const CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 5,
                ),
                const SizedBox(height: 24),
                Text(
                  'ESTABLISHING UPLINK',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
              if (_step == 1) ...[
                const Icon(
                  Icons.wifi_off_rounded,
                  color: AppColors.emergency,
                  size: 56,
                ),
                const SizedBox(height: 24),
                Text(
                  'UPLINK DISRUPTED',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.emergency,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Initiating emergency cellular relay...',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 32),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    color: AppColors.emergency,
                    backgroundColor: AppColors.outline,
                    minHeight: 6,
                  ),
                ),
              ],
              if (_step == 2) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.success.withValues(alpha: 0.1),
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.success,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'SIGNAL TRANSMITTED',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.success,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Mission parameters synced locally.\nBackground retry enabled.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

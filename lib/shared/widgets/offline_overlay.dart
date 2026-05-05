import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';

/// Simulates a resilient offline dispatch by showing an overlay that 
/// attempts network sending, detects failure, and falls back to a 
/// simulated localized SMS burst.
Future<void> showOfflineSending(BuildContext context, {required String message}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    useSafeArea: false,
    builder: (ctx) => _OfflineOverlay(message: message),
  );
  
  // Wait for the animation simulation in the UI to finish
  await Future.delayed(const Duration(seconds: 4));
}

class _OfflineOverlay extends StatefulWidget {
  final String message;
  const _OfflineOverlay({required this.message});

  @override
  State<_OfflineOverlay> createState() => _OfflineOverlayState();
}

class _OfflineOverlayState extends State<_OfflineOverlay> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _playSequence();
  }

  void _playSequence() async {
    // Step 0: Analyzing network
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _step = 1);
    
    // Step 1: No Internet, sending via backup SMS
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() => _step = 2);

    // Step 2: Sent
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withAlpha(200),
      body: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(100),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_step == 0) ...[
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 24),
                Text(
                  "Sending Secure Alert...",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
              if (_step == 1) ...[
                const Icon(Icons.wifi_off_rounded, color: AppColors.secondary, size: 48),
                const SizedBox(height: 16),
                Text(
                  "No Internet Connection",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.secondary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Rerouting through cellular backup...",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                const LinearProgressIndicator(color: AppColors.secondary, backgroundColor: AppColors.surfaceContainerHigh),
              ],
              if (_step == 2) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF4CAF50),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  "Message Sent",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF2E7D32),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "We'll keep trying to sync coordinates in the background.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
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

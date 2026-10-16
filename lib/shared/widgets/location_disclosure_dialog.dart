// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders a highly polished, premium, brand-compliant prominent location disclosure
/// and consent dialog matching Plateau Eye's design aesthetic.
/// Satisfies the Google Play User Data Policy by explicitly explaining:
/// 1. Data Type: Fine & coarse location data.
/// 2. Mode: In the background (even when the app is closed or not in use).
/// 3. Usage: Tracking during active SOS alerts to dispatch physical rescue teams.
/// 4. Control: Explicit Agree & Decline buttons.
class LocationDisclosureDialog extends StatefulWidget {
  /// Documentation for this public member.
  const LocationDisclosureDialog({super.key});

  /// Displays the prominent location disclosure modal dialog.
  /// Returns `true` if the user gave explicit consent, `false` if they declined.
  static Future<bool> show(BuildContext context) async {
    await HapticFeedback.mediumImpact();
    if (!context.mounted) return false;

    final consented = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      routeSettings: const RouteSettings(name: 'location_disclosure'),
      builder: (context) => const LocationDisclosureDialog(),
    );

    return consented ?? false;
  }

  @override
  State<LocationDisclosureDialog> createState() =>
      _LocationDisclosureDialogState();
}

class _LocationDisclosureDialogState extends State<LocationDisclosureDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    unawaited(_pulseController.repeat(reverse: true));
    _pulseAnimation = Tween<double>(begin: 1, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleConsent(bool accepted) async {
    await HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('location_disclosure_accepted', accepted);
    if (mounted) {
      Navigator.of(context).pop(accepted);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.88,
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.15),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: ListView(
                shrinkWrap: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                children: [
                  // Beautiful pulsed radar/location icon
                  Center(
                    child: ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.08),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.my_location_rounded,
                          color: AppColors.primary,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Header
                  Text(
                    'LOCATION BEACON DATA POLICY',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Prominent Disclosure & Clearance',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: AppColors.onBackground,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Core policy content card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('1. DATA ACCESSED & COLLECTED'),
                        const SizedBox(height: 6),
                        _buildSectionBody(
                            'Plateau Eye accesses, monitors, and collects your precise, continuous GPS '
                            'and cellular location coordinates (both fine and coarse data).'),
                        const SizedBox(height: 16),
                        _buildSectionHeader('2. BACKGROUND TELEMETRY MODE'),
                        const SizedBox(height: 6),
                        _buildSectionBody(
                            'This data is actively monitored and uploaded **even when the app is closed, '
                            'minimized, or not currently in active use**.'),
                        const SizedBox(height: 16),
                        _buildSectionHeader('3. EMERGENCY OPERATIONAL PURPOSE'),
                        const SizedBox(height: 6),
                        _buildSectionBody(
                            'Your location telemetry is requested exclusively to monitor coordinate changes '
                            'during an active SOS emergency alert. This enables the rescue command center (HQ) '
                            'to track your real-time path and dispatch emergency responders to your exact '
                            'physical coordinates.'),
                        const SizedBox(height: 16),
                        _buildSectionHeader('4. DATA SECURITY & PRIVACY'),
                        const SizedBox(height: 6),
                        _buildSectionBody(
                            'Your geospatial tracks are fully encrypted in transit and at rest. The telemetry is '
                            'strictly confidential, never shared with third parties, and never used for marketing '
                            'or advertising.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Explanatory warning note
                  Text(
                    'Safety Warning: Declining will disable background location telemetry, preventing rescue command from tracing your position if you trigger a silent SOS alert.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: AppColors.textDim,
                      fontSize: 11,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Buttons Row
                  Row(
                    children: [
                      // Decline button
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _handleConsent(false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.outline),
                            ),
                            child: Center(
                              child: Text(
                                'DECLINE',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Agree button
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _handleConsent(true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                'AGREE & CONTINUE',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  fontSize: 13,
                                  letterSpacing: 1.5,
                                ),
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
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 11,
        color: AppColors.primary,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildSectionBody(String text) {
    return Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 12,
        color: AppColors.textPrimary,
        height: 1.45,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

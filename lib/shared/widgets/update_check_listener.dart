import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Root-level listener that automatically checks for available app updates on startup
/// and triggers a custom modal block/prompt as necessary.
class UpdateCheckListener extends ConsumerStatefulWidget {

  /// Creates a new update checker listener.
  const UpdateCheckListener({required this.child, super.key});
  /// The child widget (typically the router navigator wrapper)
  final Widget child;

  @override
  ConsumerState<UpdateCheckListener> createState() => _UpdateCheckListenerState();
}

class _UpdateCheckListenerState extends ConsumerState<UpdateCheckListener> {
  bool _hasChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runUpdateCheck());
    });
  }

  Future<void> _runUpdateCheck() async {
    if (_hasChecked) return;
    _hasChecked = true;

    // Slight delay to allow full navigator state layout to settle
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final updateService = ref.read(updateServiceProvider);
    final updateInfo = await updateService.checkForUpdates();

    if (!mounted) return;

    if (updateInfo.hasUpdate) {
      _showUpdateDialog(updateInfo);
    }
  }

  void _showUpdateDialog(UpdateInfo updateInfo) {
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: !updateInfo.isForceUpdate,
      builder: (context) {
        return PopScope(
          canPop: !updateInfo.isForceUpdate,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF1E1E2F),
                    Color(0xFF151522),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: updateInfo.isForceUpdate
                      ? AppColors.danger.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon container
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: updateInfo.isForceUpdate
                          ? AppColors.danger.withValues(alpha: 0.1)
                          : AppColors.info.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      updateInfo.isForceUpdate
                          ? Icons.system_update_rounded
                          : Icons.rocket_launch_rounded,
                      color: updateInfo.isForceUpdate
                          ? AppColors.danger
                          : AppColors.info,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Title
                  Text(
                    updateInfo.isForceUpdate ? 'Critical Update Required' : 'New Update Available',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Description
                  Text(
                    updateInfo.isForceUpdate
                        ? 'A mandatory security update (version ${updateInfo.latestVersion}) is required to connect to emergency dispatch servers.'
                        : 'A new version (${updateInfo.latestVersion}) of Operation Rainbow is ready. Update now to access the latest features and bug fixes.',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  // Action buttons
                  Column(
                    children: [
                      // Update Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: updateInfo.isForceUpdate
                                ? AppColors.danger
                                : AppColors.info,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            final uri = Uri.parse(updateInfo.updateUrl);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Text(
                            'Update Now',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                      if (!updateInfo.isForceUpdate) ...[
                        const SizedBox(height: 12),
                        // Later Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Later',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

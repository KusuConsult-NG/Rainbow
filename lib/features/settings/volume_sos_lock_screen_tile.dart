/// Settings: making Volume Down ×3 work with the phone locked (Android).
///
/// Shown under the Volume Down ×3 switch while that switch is on. It says
/// whether the accessibility service is on, and if not, explains it BEFORE
/// sending the person to Android's settings. That explanation is the
/// "prominent disclosure" Google Play requires for an accessibility service:
/// what it does, what it does not read, and that nothing leaves the phone but
/// the SOS. See VolumeSosAccessibilityService.kt.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/sos/volume_sos.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

class VolumeSosLockScreenTile extends ConsumerStatefulWidget {
  const VolumeSosLockScreenTile({super.key});

  @override
  ConsumerState<VolumeSosLockScreenTile> createState() => _VolumeSosLockScreenTileState();
}

class _VolumeSosLockScreenTileState extends ConsumerState<VolumeSosLockScreenTile>
    with WidgetsBindingObserver {
  /// Null until the first answer.
  bool? _serviceOn;

  String _t(String key) => Translations.get(key, ref.read(languageProvider));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's settings: say what they did there.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final on = await ref.read(volumeSosLockScreenProvider).isServiceEnabled();
    if (mounted) setState(() => _serviceOn = on);
  }

  Future<void> _setUp() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text(_t('vsos_disclosure_title'),
            style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Text(_t('vsos_disclosure_body'),
              style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('vsos_disclosure_cancel'), style: const TextStyle(color: AppColors.textDim)),
          ),
          ElevatedButton(
            key: const ValueKey('volume_sos_open_accessibility'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('vsos_disclosure_open')),
          ),
        ],
      ),
    );
    if (go != true) return;
    await ref.read(volumeSosLockScreenProvider).openSettings();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(languageProvider);
    final lockScreen = ref.watch(volumeSosLockScreenProvider);
    if (!lockScreen.supported || !ref.watch(volumeSosEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final on = _serviceOn;
    if (on == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('volume_sos_lock_screen'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(on ? Icons.lock_outline : Icons.lock_open_outlined,
                  size: 18, color: on ? AppColors.success : AppColors.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t(on ? 'vsos_lock_on' : 'vsos_lock_off'),
                  style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          if (!on) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton(
                  key: const ValueKey('volume_sos_set_up_locked'),
                  onPressed: _setUp,
                  child: Text(_t('vsos_lock_setup')),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _refresh,
                  child: Text(_t('vsos_lock_check_again')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

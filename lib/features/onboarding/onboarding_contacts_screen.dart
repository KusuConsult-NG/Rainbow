import 'dart:async';

// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/router/safe_pop.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/features/settings/settings_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

class OnboardingContactsScreen extends ConsumerStatefulWidget {
  const OnboardingContactsScreen({super.key});

  @override
  ConsumerState<OnboardingContactsScreen> createState() =>
      _OnboardingContactsScreenState();
}

class _OnboardingContactsScreenState
    extends ConsumerState<OnboardingContactsScreen> {
  /// This screen's text in the chosen language.
  String _t(String key) => Translations.get(key, ref.read(languageProvider));

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Redraw when the language changes; _t reads it.
    ref.watch(languageProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('onb_contacts_title'),
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t('onb_contacts_subtitle'),
                style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameCtrl,
                style: GoogleFonts.inter(color: AppColors.onBackground),
                decoration: InputDecoration(
                  labelText: _t('onb_contacts_name'),
                  labelStyle: GoogleFonts.inter(color: AppColors.textDim),
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phoneCtrl,
                style: GoogleFonts.inter(color: AppColors.onBackground),
                decoration: InputDecoration(
                  labelText: _t('onb_contacts_phone'),
                  labelStyle: GoogleFonts.inter(color: AppColors.textDim),
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final name = _nameCtrl.text.trim();
                    final phone = _phoneCtrl.text.trim();
                    if (name.isNotEmpty && phone.isNotEmpty) {
                      final user = ref.read(authProvider).user;
                      if (user != null) {
                        try {
                          // ADDED to the list, as text. This replaced the whole
                          // list with one {name, phone} map, so saving a
                          // second contact deleted the first, and Settings
                          // showed the map's raw text.
                          final existing = ((ref.read(authProvider).profile?['emergency_contacts']
                                      as List<dynamic>?) ??
                                  const [])
                              .map(emergencyContactLabel)
                              .where((c) => c.isNotEmpty)
                              .toList();
                          final entry = emergencyContactLabel({'name': name, 'phone': phone});
                          if (!existing.contains(entry)) existing.add(entry);
                          await SupabaseConfig.client
                              .from('profiles')
                              .update({'emergency_contacts': existing})
                              .eq('id', user.id);
                          unawaited(ref.read(authProvider.notifier).refreshProfile());
                        } catch (e) {
                          // This was unguarded, so a failed write looked
                          // exactly like a successful one: the screen moved on
                          // and the person believed someone would be called
                          // for them. Say so, and stay.
                          debugPrint('[ONBOARD_CONTACTS_ERR] $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _t('onb_contacts_not_saved'),
                                ),
                                backgroundColor: AppColors.danger,
                              ),
                            );
                          }
                          return;
                        }
                      }
                    }
                    // context.mounted, not the State's mounted: this is a
                    // builder's context and the two can disagree.
                    //
                    // This no longer drives onboarding. Emergency contacts are
                    // not in this app's scope — it holds a phone number and
                    // nothing else — so the screen is optional and reachable
                    // from Settings, and saving returns there instead of
                    // pushing the next wizard step.
                    if (context.mounted) {
                      context.popOrGo(AppRoutes.settings);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    // It proceeds to the emergency PIN step, not the map.
                    _t('onb_contacts_save'),
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
      ),
    );
  }
}

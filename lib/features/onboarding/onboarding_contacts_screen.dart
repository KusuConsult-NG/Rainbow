// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/router/safe_pop.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

class OnboardingContactsScreen extends ConsumerStatefulWidget {
  const OnboardingContactsScreen({super.key});

  @override
  ConsumerState<OnboardingContactsScreen> createState() =>
      _OnboardingContactsScreenState();
}

class _OnboardingContactsScreenState
    extends ConsumerState<OnboardingContactsScreen> {
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
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'EMERGENCY CONTACTS',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add trusted contacts to be notified during SOS emergencies',
                style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameCtrl,
                style: GoogleFonts.inter(color: AppColors.onBackground),
                decoration: InputDecoration(
                  labelText: 'Contact Name',
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
                  labelText: 'Contact Phone Number',
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
                          await SupabaseConfig.client
                              .from('profiles')
                              .update({
                                'emergency_contacts': [
                                  {'name': name, 'phone': phone},
                                ],
                              })
                              .eq('id', user.id);
                        } catch (e) {
                          // This was unguarded, so a failed write looked
                          // exactly like a successful one: the screen moved on
                          // and the person believed someone would be called
                          // for them. Say so, and stay.
                          debugPrint('[ONBOARD_CONTACTS_ERR] $e');
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'YOUR CONTACT DID NOT SAVE. CHECK YOUR '
                                  'CONNECTION AND TRY AGAIN.',
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
                    'SAVE & CONTINUE',
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

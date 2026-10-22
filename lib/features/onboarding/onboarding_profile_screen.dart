// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/auth/phone_number.dart';
import 'package:rainbow_app/core/constants/tactical_mapping.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/router/safe_pop.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

class OnboardingProfileScreen extends ConsumerStatefulWidget {
  const OnboardingProfileScreen({super.key});

  @override
  ConsumerState<OnboardingProfileScreen> createState() =>
      _OnboardingProfileScreenState();
}

/// Where a citizen's account stops being anonymous.
///
/// Three things were wrong with this screen, and the first one meant the whole
/// first-run flow never finished.
///
/// **Nothing marked onboarding as done.** `AuthNotifier.setOnboarded` had no
/// call sites anywhere in the app, and nothing wrote `profiles.profile_complete
/// = true`. The router reads `prefs('hasOnboarded') ?? profile_complete`, so on
/// the NEXT launch both were false and the citizen was walked through the
/// entire wizard again. Every launch. Forever.
///
/// **It asked for the phone number again.** The account was created BY a phone
/// number the person had just proved they hold, by reading back a code sent to
/// it. This box then overwrote `profiles.phone` — a UNIQUE column, and the
/// number HQ rings back — with whatever was typed, unverified. Typing someone
/// else's number was enough to put it on your own profile; typing a number
/// already registered raised a unique violation that the catch below swallowed
/// into a debugPrint, so the button simply did nothing, twice, with no message.
///
/// **A failure was invisible.** Same catch: no message, no retry, and
/// `_isSaving` left true on the early return, so the button said SAVING… for
/// the rest of the session.
class _OnboardingProfileScreenState
    extends ConsumerState<OnboardingProfileScreen> {
  final _nameController = TextEditingController();
  String? _error;

  TacticalJurisdiction? _selectedLga;
  TacticalWard? _selectedWard;
  String? _selectedPu;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// The number this account was created with, shown but not editable.
  ///
  /// It is the identity: changing it here would not change which account you
  /// are signed in to, only which number HQ would ring. Changing the number on
  /// an account has to mean proving the new one, which is the sign-in flow, not
  /// a text box on a registration form.
  String get _verifiedPhone {
    final user = ref.read(authProvider).user;
    final phone = user?.phone;
    if (phone == null || phone.isEmpty) return 'Not recorded';
    final e164 = phone.startsWith('+') ? phone : '+$phone';
    return displayNigerianPhone(e164);
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter the name HQ should use for you.');
      return;
    }

    final user = ref.read(authProvider).user;
    if (user == null) {
      // Was an early `return` with _isSaving already true, so the button read
      // SAVING… for the rest of the session and did nothing.
      setState(() => _error = 'You are not signed in. Sign in and try again.');
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await SupabaseConfig.client.from('profiles').upsert({
        'id': user.id,
        'full_name': name,
        // `phone` is NOT written here. It is set from the verified number when
        // the account is created, and this form has no way to verify one.
        'geo_lga': _selectedLga?.name,
        'geo_ward': _selectedWard?.name,
        'geo_pu': _selectedPu,
        // The half of "onboarding is finished" that survives a reinstall.
        'profile_complete': true,
      });

      // NOT `setOnboarded(true)` any more.
      //
      // This screen used to be step 2 of 3 and the thing that completed setup,
      // which made a name, an NIN, a gender and an LGA compulsory before
      // anybody could reach the SOS button. None of that is this app's to
      // hold: the phone number is the only identity, and it arrives with the
      // sign-in. The PIN screen completes setup now.
      //
      // The screen is kept and reachable from Settings, because a person who
      // WANTS to give a name so a responder can address them should be able
      // to. `profile_complete` above still records that they did.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved.')),
      );
      context.popOrGo(AppRoutes.settings);
    } catch (e) {
      debugPrint('[PROFILE_ERR] could not save the profile: $e');
      if (!mounted) return;
      setState(
        () => _error =
            'That did not save. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PROFILE REGISTRATION',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter citizen details for emergency dispatch registration',
                style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 13),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                style: GoogleFonts.inter(color: AppColors.onBackground),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: GoogleFonts.inter(color: AppColors.textDim),
                  filled: true,
                  fillColor: AppColors.surfaceContainer,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // The verified number, stated rather than asked for again.
              Container(
                key: const ValueKey('verified_phone'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      size: 18,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'VERIFIED NUMBER',
                            style: GoogleFonts.outfit(
                              color: AppColors.textDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            _verifiedPhone,
                            style: GoogleFonts.inter(
                              color: AppColors.onBackground,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  key: const ValueKey('profile_error'),
                  style: GoogleFonts.inter(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _isSaving ? 'SAVING...' : 'COMPLETE REGISTRATION',
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

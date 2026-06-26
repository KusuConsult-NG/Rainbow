// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/features/onboarding/onboarding_permissions_screen.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

/// Documentation for this public member.

class OnboardingContactsScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const OnboardingContactsScreen({super.key});

  @override
  ConsumerState<OnboardingContactsScreen> createState() =>
      _OnboardingContactsScreenState();
}

class _OnboardingContactsScreenState
    extends ConsumerState<OnboardingContactsScreen> {
  final List<Map<String, TextEditingController>> _contacts = [];

  @override
  void initState() {
    super.initState();
    _addContact(); // Start with 1 contact
  }

  void _addContact() {
    if (_contacts.length >= 5) return;
    setState(() {
      _contacts.add({
        'name': TextEditingController(),
        'phone': TextEditingController(),
      });
    });
  }

  void _removeContact(int index) {
    setState(() {
      _contacts[index]['name']?.dispose();
      _contacts[index]['phone']?.dispose();
      _contacts.removeAt(index);
    });
  }

  @override
  void dispose() {
    for (final c in _contacts) {
      c['name']?.dispose();
      c['phone']?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          children: [
            const OnboardingHeader(step: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  Text(
                    'COMMS PROTOCOL',
                    style: GoogleFonts.outfit(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Designate trusted contacts for automated emergency signaling.',
                    style: GoogleFonts.outfit(
                      color: AppColors.textDim,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Tactical Banner
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hub_rounded,
                          color: AppColors.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Contacts will receive high-priority alerts via encrypted SMS and satellite relay.',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  ...List.generate(
                    _contacts.length,
                    (i) => _TacticalContactCard(
                      index: i,
                      nameCtrl: _contacts[i]['name'] ?? TextEditingController(),
                      phoneCtrl:
                          _contacts[i]['phone'] ?? TextEditingController(),
                      onRemove:
                          _contacts.length > 1 ? () => _removeContact(i) : null,
                    ),
                  ),

                  if (_contacts.length < 5) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _addContact,
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.add_link_rounded,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'ADD AUXILIARY CONTACT',
                              style: GoogleFonts.outfit(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 120),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: OnboardingBottomNav(
        onBack: () => context.go(AppRoutes.onboardingProfile),
        onNext: _isInitializing ? null : _initializeSystem,
        nextLabel: _isInitializing ? 'INITIALIZING...' : 'INITIALIZE SYSTEM',
      ),
    );
  }

  bool _isInitializing = false;

  Future<void> _initializeSystem() async {
    final validContacts = _contacts
        .where(
          (c) =>
              (c['name']?.text.isNotEmpty ?? false) &&
              (c['phone']?.text.isNotEmpty ?? false),
        )
        .map(
          (c) => {
            'name': c['name']?.text.trim() ?? '',
            'phone': c['phone']?.text.trim() ?? '',
          },
        )
        .toList();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    setState(() => _isInitializing = true);
    try {
      if (validContacts.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        final existing = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('emergency_contacts')
            .get();
        for (final doc in existing.docs) {
          batch.delete(doc.reference);
        }
        for (var i = 0; i < validContacts.length; i++) {
          final ref = FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('emergency_contacts')
              .doc('contact_$i');
          batch.set(ref, {
            ...validContacts[i],
            'relation': i == 0 ? 'Primary' : 'Contact ${i + 1}',
            'index': i,
          });
        }
        await batch.commit();
      }

      await ref.read(authProvider.notifier).setOnboarded(true);

      if (!mounted) return;
      context.go(AppRoutes.home);
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[COMMS_FATAL] System initialization failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('CONTACT SYNC DELAYED'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }
}

class _TacticalContactCard extends StatelessWidget {
  const _TacticalContactCard({
    required this.index,
    required this.nameCtrl,
    required this.phoneCtrl,
    this.onRemove,
  });
  final int index;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'PRIORITY 0${index + 1}',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline_rounded,
                    color: AppColors.textDim,
                    size: 20,
                  ),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 20),
          _Field(
            controller: nameCtrl,
            hint: 'Contact Full Name',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: phoneCtrl,
            hint: '+234 ...',
            icon: Icons.phone_enabled_rounded,
            type: TextInputType.phone,
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.type = TextInputType.text,
  });
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType type;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: type,
      style: GoogleFonts.outfit(
        color: AppColors.onBackground,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: AppColors.primary,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: AppColors.textDim, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
        filled: true,
        fillColor: AppColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }
}

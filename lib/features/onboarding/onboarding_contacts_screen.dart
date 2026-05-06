import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import 'onboarding_permissions_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';


class OnboardingContactsScreen extends StatefulWidget {
  const OnboardingContactsScreen({super.key});

  @override
  State<OnboardingContactsScreen> createState() => _OnboardingContactsScreenState();
}

class _OnboardingContactsScreenState extends State<OnboardingContactsScreen> {
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
      body: Column(
        children: [
          const OnboardingHeader(step: 3),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const SizedBox(height: 32),
                Text(
                  'COMMS PROTOCOL',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Designate trusted contacts for automated emergency signaling.',
                  style: GoogleFonts.outfit(
                    color: Colors.white38,
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
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hub_rounded, color: AppColors.primary, size: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Contacts will receive high-priority alerts via encrypted SMS and satellite relay.',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                ...List.generate(_contacts.length, (i) => _TacticalContactCard(
                  index: i,
                  nameCtrl: _contacts[i]['name'] ?? TextEditingController(),
                  phoneCtrl: _contacts[i]['phone'] ?? TextEditingController(),
                  onRemove: _contacts.length > 1 ? () => _removeContact(i) : null,
                )),

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
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_link_rounded, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Text(
                            'ADD AUXILIARY CONTACT',
                            style: GoogleFonts.outfit(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 2.0,
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
      bottomNavigationBar: OnboardingBottomNav(
        onBack: () => context.go(AppRoutes.onboardingProfile),
        onNext: () async {
          final validContacts = _contacts
              .where((c) =>
                  (c['name']?.text.isNotEmpty ?? false) &&
                  (c['phone']?.text.isNotEmpty ?? false))
              .map((c) => {
                    'name': c['name']?.text.trim() ?? '',
                    'phone': c['phone']?.text.trim() ?? '',
                  })
              .toList();

          final uid = FirebaseAuth.instance.currentUser?.uid;
          if (uid != null && validContacts.isNotEmpty) {
            try {
              final batch = FirebaseFirestore.instance.batch();
              final existing = await FirebaseFirestore.instance
                  .collection('users').doc(uid)
                  .collection('emergency_contacts')
                  .get();
              for (final doc in existing.docs) {
                batch.delete(doc.reference);
              }
              for (int i = 0; i < validContacts.length; i++) {
                final ref = FirebaseFirestore.instance
                    .collection('users').doc(uid)
                    .collection('emergency_contacts')
                    .doc('contact_$i');
                batch.set(ref, {
                  ...validContacts[i],
                  'relation': i == 0 ? 'Primary' : 'Contact ${i + 1}',
                  'index': i,
                });
              }

              await batch.commit();
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('CONTACT SYNC DELAYED'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('hasOnboarded', true);

          if (context.mounted) {
            context.go(AppRoutes.home);
          }
        },
        nextLabel: 'INITIALIZE SYSTEM',
      ),
    );
  }
}

class _TacticalContactCard extends StatelessWidget {
  final int index;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback? onRemove;

  const _TacticalContactCard({
    required this.index,
    required this.nameCtrl,
    required this.phoneCtrl,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.white24, size: 20),
                  onPressed: onRemove,
                ),
            ],
          ),
          const SizedBox(height: 20),
          _Field(controller: nameCtrl, hint: 'Contact Full Name', icon: Icons.person_rounded),
          const SizedBox(height: 12),
          _Field(controller: phoneCtrl, hint: '+234 ...', icon: Icons.phone_enabled_rounded, type: TextInputType.phone),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType type;

  const _Field({required this.controller, required this.hint, required this.icon, this.type = TextInputType.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        keyboardType: type,
        style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.outfit(color: Colors.white12, fontSize: 13),
          prefixIcon: Icon(icon, color: Colors.white24, size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

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
                const SizedBox(height: 20),
                Text('Emergency Contacts', style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: -0.8)),
                const SizedBox(height: 4),
                Text('These people will be alerted immediately and receive your live location during an emergency.', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 13, height: 1.5)),
                const SizedBox(height: 20),

                // Info banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withAlpha(15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.secondary.withAlpha(50)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.secondary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Add up to 5 trusted contacts. They\'ll receive SMS, WhatsApp and calls when you trigger an alert.', style: GoogleFonts.inter(fontSize: 12, color: AppColors.secondary, height: 1.4))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Contact cards
                // Fix #8: use ?. instead of ! — keys always exist (built locally)
                // but defensive access avoids any future refactor crash
                ...List.generate(_contacts.length, (i) => _ContactCard(
                  index: i,
                  nameCtrl: _contacts[i]['name'] ?? TextEditingController(),
                  phoneCtrl: _contacts[i]['phone'] ?? TextEditingController(),
                  onRemove: _contacts.length > 1 ? () => _removeContact(i) : null,
                )),

                // Add button
                if (_contacts.length < 5) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _addContact,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.primary.withAlpha(80), width: 2, style: BorderStyle.solid),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_circle_rounded, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Text('ADD ANOTHER CONTACT', style: GoogleFonts.inter(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1.0)),
                      ]),
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '${_contacts.length} / 5 contacts added',
                    style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: OnboardingBottomNav(
        onBack: () => context.go(AppRoutes.onboardingProfile),
        onNext: () async {
          // Prepare valid contacts
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
              // Use sub-collection so profile_screen can stream directly
              final batch = FirebaseFirestore.instance.batch();
              // Clear existing contacts first
              final existing = await FirebaseFirestore.instance
                  .collection('users').doc(uid)
                  .collection('emergency_contacts')
                  .get();
              for (final doc in existing.docs) {
                batch.delete(doc.reference);
              }
              // Write new contacts
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
              debugPrint('[SYS_ERR] Failed to save contacts: $e');
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Warning: Contacts could not be saved. Check your connection.'),
                  backgroundColor: Colors.orange,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('hasOnboarded', true);

          if (!context.mounted) return;
          context.go(AppRoutes.home);
        },
        nextLabel: 'FINISH SETUP',
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final int index;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final VoidCallback? onRemove;

  const _ContactCard({required this.index, required this.nameCtrl, required this.phoneCtrl, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 12)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary.withAlpha(20)),
              child: Center(child: Text('${index + 1}', style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 13))),
            ),
            const SizedBox(width: 10),
            Text('Contact ${index + 1}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15)),
            const Spacer(),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                onPressed: onRemove,
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Full Name',
              hintStyle: GoogleFonts.inter(color: AppColors.outline),
              prefixIcon: const Icon(Icons.person_outline_rounded, color: AppColors.outline, size: 18),
              filled: true, fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '+234 800 000 0000',
              hintStyle: GoogleFonts.inter(color: AppColors.outline),
              prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.outline, size: 18),
              filled: true, fillColor: AppColors.surfaceContainerLow,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import 'onboarding_permissions_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';


class OnboardingProfileScreen extends ConsumerStatefulWidget {
  const OnboardingProfileScreen({super.key});

  @override
  ConsumerState<OnboardingProfileScreen> createState() => _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState extends ConsumerState<OnboardingProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  File? _avatarFile;
  bool _isUploading = false;
  
  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _avatarFile = File(pickedFile.path);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const OnboardingHeader(step: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const SizedBox(height: 20),
                Text('Your Profile', style: GoogleFonts.inter(fontWeight: FontWeight.w900, fontSize: 28, letterSpacing: -0.8)),
                const SizedBox(height: 4),
                Text('This helps responders identify you quickly during emergencies.', style: GoogleFonts.inter(color: AppColors.onSurfaceVariant, fontSize: 13, height: 1.5)),
                const SizedBox(height: 24),

                // Avatar picker
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.surfaceContainerHigh,
                            border: Border.all(color: AppColors.primary.withAlpha(80), width: 3),
                            image: _avatarFile != null 
                              ? DecorationImage(image: FileImage(_avatarFile!), fit: BoxFit.cover)
                              : null,
                          ),
                          child: _avatarFile == null ? const Icon(Icons.person_rounded, size: 56, color: AppColors.outline) : null,
                        ),
                        Positioned(
                          bottom: 0, right: 0,
                          child: Container(
                            width: 32, height: 32,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                            child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const _FormLabel('Full Name'),
                _TextField(controller: _nameController, hint: 'John Adamu', icon: Icons.person_outline_rounded),
                const SizedBox(height: 16),

                const _FormLabel('Phone Number'),
                _TextField(controller: _phoneController, hint: '+234 800 000 0000', icon: Icons.phone_outlined, type: TextInputType.phone),
                const SizedBox(height: 16),

                const _FormLabel('Home Address'),
                _TextField(controller: _addressController, hint: 'No. 12, Jos Street, Plateau State', icon: Icons.home_outlined),
                const SizedBox(height: 16),


                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: OnboardingBottomNav(
        onBack: () => context.go(AppRoutes.onboardingPermissions),
        onNext: _isUploading ? null : () async {
          final user = FirebaseAuth.instance.currentUser;
          if (user == null) return;
          
          if (_nameController.text.trim().isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please enter your full name'), backgroundColor: Colors.red),
            );
            return;
          }

          setState(() => _isUploading = true);
          try {
            String? avatarUrl;
            if (_avatarFile != null) {
              final storageRef = FirebaseStorage.instance.ref().child('avatars/${user.uid}.jpg');
              await storageRef.putFile(_avatarFile!);
              avatarUrl = await storageRef.getDownloadURL();
              await user.updatePhotoURL(avatarUrl);
            }

            await user.updateDisplayName(_nameController.text.trim());
            await user.reload();

            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'name': _nameController.text.trim(),
              'phone': _phoneController.text.trim().isEmpty
                  ? (user.phoneNumber ?? '')
                  : _phoneController.text.trim(),
              'address': _addressController.text.trim(),
              if (avatarUrl != null) 'avatar': avatarUrl,
              'role': 'CITIZEN',
              'roleLabel': 'Citizen',
              'uid': user.uid,
              'profileComplete': true,
            }, SetOptions(merge: true));
          } catch (e) {
            debugPrint('[SYS_ERR] Profile save failed: $e');
            if (mounted) {
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: Colors.red),
              );
            }
          }
          if (mounted) {
            setState(() => _isUploading = false);
            // ignore: use_build_context_synchronously
            context.go(AppRoutes.onboardingContacts);
          }
        },
        nextLabel: _isUploading ? 'SAVING PROFILE...' : 'NEXT: EMERGENCY CONTACTS',
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  final String label;
  const _FormLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.onSurfaceVariant, letterSpacing: 0.5)),
  );
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType type;
  const _TextField({required this.controller, required this.hint, required this.icon, this.type = TextInputType.text});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: type,
    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: AppColors.outline, fontSize: 14),
      prefixIcon: Icon(icon, color: AppColors.outline, size: 20),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}

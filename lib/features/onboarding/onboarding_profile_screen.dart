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
  final _geoLgaController = TextEditingController(text: 'Jos North');
  final _geoWardController = TextEditingController(text: 'Tudun Wada');
  final _geoPuController = TextEditingController(text: 'Unit 004');
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
    _geoLgaController.dispose();
    _geoWardController.dispose();
    _geoPuController.dispose();
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
                const SizedBox(height: 32),
                Text(
                  'IDENTITY & LOCATION',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 28,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Map your identity to your local polling unit for rapid tactical response.',
                  style: GoogleFonts.outfit(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 40),

                // Tactical Avatar Picker
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.02),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.05),
                                blurRadius: 20,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                          child: ClipOval(
                            child: _avatarFile != null 
                              ? Image.file(_avatarFile!, fit: BoxFit.cover)
                              : Center(
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 64,
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                          ),
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.background, width: 3),
                            ),
                            child: const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                _TacticalField(
                  label: 'FULL NAME',
                  controller: _nameController,
                  hint: 'Enter identification name',
                  icon: Icons.badge_rounded,
                ),
                const SizedBox(height: 24),

                _TacticalField(
                  label: 'PHONE NUMBER',
                  controller: _phoneController,
                  hint: '+234 000 000 0000',
                  icon: Icons.phone_android_rounded,
                  type: TextInputType.phone,
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: _TacticalField(
                        label: 'LGA',
                        controller: _geoLgaController,
                        hint: 'e.g. Jos North',
                        icon: Icons.map_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TacticalField(
                        label: 'WARD',
                        controller: _geoWardController,
                        hint: 'e.g. Tudun Wada',
                        icon: Icons.layers_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _TacticalField(
                  label: 'POLLING UNIT',
                  controller: _geoPuController,
                  hint: 'Enter your polling unit name',
                  icon: Icons.how_to_reg_rounded,
                ),
                const SizedBox(height: 24),

                _TacticalField(
                  label: 'RESIDENTIAL ADDRESS',
                  controller: _addressController,
                  hint: 'Home tactical location',
                  icon: Icons.location_city_rounded,
                ),
                
                const SizedBox(height: 120),
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
              const SnackBar(
                content: Text('IDENTIFICATION REQUIRED'),
                backgroundColor: AppColors.emergency,
              ),
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
              'geo_lga': _geoLgaController.text.trim(),
              'geo_ward': _geoWardController.text.trim(),
              'geo_pu': _geoPuController.text.trim(),
              if (avatarUrl != null) 'avatar': avatarUrl,
              'role': 'CITIZEN',
              'roleLabel': 'Citizen',
              'uid': user.uid,
              'profileComplete': true,
            }, SetOptions(merge: true));
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('TRANSMISSION ERROR: $e'),
                  backgroundColor: AppColors.emergency,
                ),
              );
            }
          }
          if (context.mounted) {
            setState(() => _isUploading = false);
            context.go(AppRoutes.onboardingContacts);
          }
        },
        nextLabel: _isUploading ? 'SYNCHRONIZING...' : 'ESTABLISH COMMS LINK',
      ),
    );
  }
}

class _TacticalField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType type;

  const _TacticalField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.type = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white24,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 2.0,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: type,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: Colors.white12, fontSize: 14),
              prefixIcon: Icon(icon, color: AppColors.primary.withValues(alpha: 0.4), size: 20),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          ),
        ),
      ],
    );
  }
}

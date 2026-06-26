// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rainbow_app/core/constants/tactical_mapping.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/features/onboarding/onboarding_permissions_screen.dart';

/// Documentation for this public member.

class OnboardingProfileScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const OnboardingProfileScreen({super.key});

  @override
  ConsumerState<OnboardingProfileScreen> createState() =>
      _OnboardingProfileScreenState();
}

class _OnboardingProfileScreenState
    extends ConsumerState<OnboardingProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  TacticalJurisdiction? _selectedLga;
  TacticalWard? _selectedWard;
  TacticalWard? _selectedSiecWard;
  String? _selectedPu;

  File? _avatarFile;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Default to Jos North, with safe fallback if ID ever changes
    _selectedLga = plateauTacticalMap
            .firstWhereOrNull((lga) => lga.id == 'LGA_JOS_NORTH') ??
        (plateauTacticalMap.isNotEmpty ? plateauTacticalMap.first : null);
    _selectedWard = (_selectedLga?.wards.isNotEmpty ?? false)
        ? _selectedLga!.wards.first
        : null;
    _selectedSiecWard = (_selectedLga?.siecWards.isNotEmpty ?? false)
        ? _selectedLga!.siecWards.first
        : null;
    _selectedPu = (_selectedWard?.pollingUnits.isNotEmpty ?? false)
        ? _selectedWard!.pollingUnits.first
        : null;
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final pickedFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
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
      body: SafeArea(
        child: ListView(
          children: [
            const OnboardingHeader(step: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  Text(
                    'IDENTITY & LOCATION',
                    style: GoogleFonts.outfit(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Map your identity to your local polling unit for rapid tactical response.',
                    style: GoogleFonts.outfit(
                      color: AppColors.textSecondary,
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
                              color: AppColors.surfaceContainer,
                              border: Border.all(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.05),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _avatarFile != null
                                  ? Image.file(_avatarFile!, fit: BoxFit.cover)
                                  : const Center(
                                      child: Icon(
                                        Icons.person_rounded,
                                        size: 64,
                                        color: AppColors.textDim,
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
                                border: Border.all(
                                  color: AppColors.background,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
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

                  // LGA Selector
                  _TacticalDropdown(
                    label: 'LOCAL GOVERNMENT AREA (LGA)',
                    value: _selectedLga?.name ?? '',
                    items: plateauTacticalMap.map((lga) => lga.name).toList(),
                    icon: Icons.map_rounded,
                    onChanged: (val) {
                      setState(() {
                        _selectedLga = plateauTacticalMap
                                .firstWhereOrNull((lga) => lga.name == val) ??
                            _selectedLga;
                        _selectedWard =
                            (_selectedLga?.wards.isNotEmpty ?? false)
                                ? _selectedLga!.wards.first
                                : null;
                        _selectedSiecWard =
                            (_selectedLga?.activeSiecWards.isNotEmpty ?? false)
                                ? _selectedLga!.activeSiecWards.first
                                : null;
                        _selectedPu =
                            (_selectedWard?.pollingUnits.isNotEmpty ?? false)
                                ? _selectedWard!.pollingUnits.first
                                : null;
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _TacticalDropdown(
                          label: 'FEDERAL WARD (INEC)',
                          value: _selectedWard?.name ?? '',
                          items:
                              _selectedLga?.wards.map((w) => w.name).toList() ??
                                  [],
                          icon: Icons.how_to_vote_rounded,
                          onChanged: (val) {
                            setState(() {
                              _selectedWard = _selectedLga?.wards
                                      .firstWhereOrNull((w) => w.name == val) ??
                                  _selectedWard;
                              _selectedPu =
                                  (_selectedWard?.pollingUnits.isNotEmpty ??
                                          false)
                                      ? _selectedWard!.pollingUnits.first
                                      : null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TacticalDropdown(
                          label: 'STATE WARD (SIEC)',
                          value: _selectedSiecWard?.name ?? '',
                          items: (_selectedLga?.activeSiecWards.isNotEmpty ??
                                  false)
                              ? _selectedLga!.activeSiecWards
                                  .map((w) => w.name)
                                  .toList()
                              : ['N/A'],
                          icon: Icons.layers_rounded,
                          onChanged: (val) {
                            if (val == 'N/A') return;
                            setState(() {
                              _selectedSiecWard = _selectedLga?.activeSiecWards
                                      .firstWhereOrNull((w) => w.name == val) ??
                                  _selectedSiecWard;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _TacticalDropdown(
                          label: 'POLLING UNIT (PU)',
                          value: _selectedPu ?? '',
                          items: _selectedWard?.pollingUnits ?? [],
                          icon: Icons.how_to_reg_rounded,
                          onChanged: (val) => setState(() => _selectedPu = val),
                        ),
                      ),
                    ],
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
      ),
      bottomNavigationBar: OnboardingBottomNav(
        onBack: () => context.go(AppRoutes.onboardingPermissions),
        onNext: _isUploading ? null : _submitProfile,
        nextLabel: _isUploading ? 'SYNCHRONIZING...' : 'ESTABLISH COMMS LINK',
      ),
    );
  }

  Future<void> _submitProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) context.go(AppRoutes.login);
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
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
        final storageRef =
            FirebaseStorage.instance.ref().child('avatars/${user.uid}.jpg');
        await storageRef.putFile(_avatarFile!);
        avatarUrl = await storageRef.getDownloadURL();
        await user.updatePhotoURL(avatarUrl);
      }

      await user.updateDisplayName(name);
      await user.reload();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'name': name,
          'displayName': name,
          'phone': _phoneController.text.trim().isEmpty
              ? (user.phoneNumber ?? '')
              : _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'geo_lgas': [_selectedLga?.name ?? ''],
          'geo_wards': [_selectedWard?.name ?? ''],
          'geo_pus': [_selectedPu ?? ''],
          'geo_lga': _selectedLga?.name ?? '', // Legacy support
          'geo_ward': _selectedWard?.name,
          'geo_siec_ward': _selectedSiecWard?.name,
          'geo_pu': _selectedPu ?? '',
          if (avatarUrl != null) 'avatar': avatarUrl,
          if (avatarUrl != null) 'avatarUrl': avatarUrl,
          'role': 'USER',
          'roleLabel': 'User',
          'isStaff': false,
          'uid': user.uid,
          'profileComplete': true,
          'lastActive': FieldValue.serverTimestamp(),
          'active': true,
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      context.go(AppRoutes.onboardingContacts);
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[PROFILE_FATAL] Transmission failure: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('TRANSMISSION ERROR: $e'),
            backgroundColor: AppColors.emergency,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}

class _TacticalField extends StatelessWidget {
  const _TacticalField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.type = TextInputType.text,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType type;
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
              color: AppColors.textDim,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: type,
          style: GoogleFonts.outfit(
            color: AppColors.onBackground,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.outfit(
              color: AppColors.textDim,
              fontSize: 14,
            ),
            prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
            filled: true,
            fillColor: AppColors.surfaceContainer,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.all(20),
          ),
        ),
      ],
    );
  }
}

class _TacticalDropdown extends StatelessWidget {
  const _TacticalDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.icon,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final IconData icon;
  final ValueChanged<String?> onChanged;

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
              color: AppColors.textDim,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: AppColors.surface,
            ),
            child: DropdownButtonFormField<String>(
              initialValue: items.contains(value) ? value : items.first,
              onChanged: onChanged,
              isExpanded: true,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.textDim,
              ),
              style: GoogleFonts.outfit(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                prefixIcon:
                    Icon(icon, color: AppColors.textSecondary, size: 20),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                fillColor: Colors.transparent,
              ),
              items: items.map((item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child:
                      Text(item.toUpperCase(), overflow: TextOverflow.ellipsis),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

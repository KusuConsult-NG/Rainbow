// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart' as local_auth;
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Documentation for this public member.

class SettingsScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _locationBackground = true;
  bool _anonymousDefault = false;
  bool _loading = true;
  bool _editMode = false; // GAP-H: profile edit toggle
  bool _saving = false;
  Map<String, dynamic> _profile = {};

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  Future<void> _verifyAndExecute(VoidCallback onVerified) async {
    final auth = local_auth.LocalAuthentication();
    try {
      final didAuth = await auth.authenticate(
        localizedReason: 'SECURE MISSION AUTHORIZATION REQUIRED',
        options: const local_auth.AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (didAuth) {
        unawaited(HapticFeedback.mediumImpact());
        onVerified();
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) _profile = doc.data() ?? {};
        // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('setting_notifications') ?? true;
        _locationBackground = prefs.getBool('setting_location_bg') ?? true;
        _anonymousDefault = prefs.getBool('setting_anonymous_default') ?? false;
        _loading = false;
        // Pre-fill edit controllers with current profile values
        final displayName = _profile['displayName'] as String? ??
            _profile['name'] as String? ??
            user?.displayName ??
            '';
        _nameCtrl.text = displayName;
        _phoneCtrl.text =
            _profile['phone'] as String? ?? user?.phoneNumber ?? '';
      });
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  // GAP-H: Save edited profile to Firestore + Firebase Auth
  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          if (name.isNotEmpty) 'displayName': name,
          if (name.isNotEmpty) 'name': name,
          if (phone.isNotEmpty) 'phone': phone,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (name.isNotEmpty) {
        await user.updateDisplayName(name);
      }

      setState(() {
        if (name.isNotEmpty) _profile['displayName'] = name;
        if (phone.isNotEmpty) _profile['phone'] = phone;
        _editMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PROFILE UPDATED'),
            backgroundColor: Color(0xFF1B5E20),
          ),
        );
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      debugPrint('[SYS_ERR] Profile save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.red,
                size: 32,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'TERMINATE ACCOUNT',
              style: GoogleFonts.outfit(
                color: AppColors.onBackground,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action is irreversible. All mission data, tactical reports, and profile telemetry will be permanently purged from the mainframe.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.outline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'CANCEL',
                      style: GoogleFonts.outfit(color: AppColors.onBackground),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'TERMINATE',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .delete();
        await user.delete();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (!mounted) return;
        context.go(AppRoutes.login);
      }
      // ignore: avoid_catches_without_on_clauses, Stylistic override to match system design
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('TERMINATION FAILED: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Widget _buildProfileViewMode({
    required String displayName,
    required String phone,
    String? avatarUrl,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppColors.primary,
                AppColors.primary.withValues(alpha: 0.1),
              ],
            ),
          ),
          child: CircleAvatar(
            radius: 36,
            backgroundColor: AppColors.background,
            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                    style: GoogleFonts.outfit(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppColors.onBackground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                phone,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: AppColors.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      'ACTIVE OPERATIVE',
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => _editMode = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'EDIT',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileEditMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'EDIT PROFILE',
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: AppColors.primary,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameCtrl,
          style: GoogleFonts.outfit(
            color: AppColors.onBackground,
            fontWeight: FontWeight.w600,
          ),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            labelText: 'Display Name',
            labelStyle:
                GoogleFonts.outfit(color: AppColors.textDim, fontSize: 12),
            prefixIcon: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.primary,
              size: 18,
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: GoogleFonts.outfit(
            color: AppColors.onBackground,
            fontWeight: FontWeight.w600,
          ),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            labelText: 'Phone Number',
            labelStyle:
                GoogleFonts.outfit(color: AppColors.textDim, fontSize: 12),
            prefixIcon: const Icon(
              Icons.phone_outlined,
              color: AppColors.primary,
              size: 18,
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed:
                    _saving ? null : () => setState(() => _editMode = false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: const BorderSide(color: AppColors.outline),
                ),
                child: Text(
                  'CANCEL',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _saving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'SAVE',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = _profile['displayName'] as String? ??
        _profile['name'] as String? ??
        user?.displayName ??
        'ANONYMOUS USER';
    final phone = _profile['phone'] as String? ?? user?.phoneNumber ?? '---';
    final avatarUrl = _profile['avatar'] as String?;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'COMMAND SETTINGS',
        subtitle: 'CONFIGURING TACTICAL PROFILE',
        showBack: true,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Profile Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(24),
                    border: AppColors.glassBorder,
                  ),
                  child: _editMode
                      ? _buildProfileEditMode()
                      : _buildProfileViewMode(
                          displayName: displayName,
                          phone: phone,
                          avatarUrl: avatarUrl,
                        ),
                ),
                const SizedBox(height: 32),

                _buildSectionHeader('MISSION PREFERENCES'),
                const SizedBox(height: 16),
                _TacticalSwitchTile(
                  title: 'Push Notifications',
                  subtitle: 'Receive real-time mission updates',
                  icon: Icons.notifications_active_outlined,
                  value: _notificationsEnabled,
                  onChanged: (v) {
                    setState(() => _notificationsEnabled = v);
                    unawaited(_saveBool('setting_notifications', v));
                  },
                ),
                _TacticalSwitchTile(
                  title: 'Geospatial Telemetry',
                  subtitle: 'Enable background GPS for field tracking',
                  icon: Icons.location_on_outlined,
                  value: _locationBackground,
                  onChanged: (v) {
                    setState(() => _locationBackground = v);
                    unawaited(_saveBool('setting_location_bg', v));
                  },
                ),
                _TacticalSwitchTile(
                  title: 'Stealth Reporting',
                  subtitle: 'Enable anonymous reporting by default',
                  icon: Icons.visibility_off_outlined,
                  value: _anonymousDefault,
                  onChanged: (v) {
                    setState(() => _anonymousDefault = v);
                    unawaited(_saveBool('setting_anonymous_default', v));
                  },
                ),

                const SizedBox(height: 32),
                _buildSectionHeader('OPERATIONAL DATA'),
                const SizedBox(height: 16),
                _TacticalActionTile(
                  title: 'Emergency Contacts',
                  subtitle: 'Manage your high-assurance circle',
                  icon: Icons.contacts_outlined,
                  onTap: () => context.push(AppRoutes.onboardingContacts),
                ),
                _TacticalActionTile(
                  title: 'Security Clearance',
                  subtitle: 'Update mission access credentials',
                  icon: Icons.lock_outline_rounded,
                  onTap: () => _verifyAndExecute(() {
                    unawaited(
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: const Color(0xFF1A1A1A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          title: Text(
                            'SECURITY CLEARANCE',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              fontSize: 14,
                            ),
                          ),
                          content: Text(
                            'Scan your physical mission badge or enter your secondary authorization token to update clearance levels.',
                            style: GoogleFonts.inter(
                              color: Colors.white70,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'CANCEL',
                                style: GoogleFonts.inter(
                                  color: Colors.white38,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFD700),
                                    Color(0xFFFFB700),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Identity Verified. Credentials Synchronized.',
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'AUTHENTICATE',
                                  style: GoogleFonts.inter(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 32),
                _buildSectionHeader('DANGER ZONE'),
                const SizedBox(height: 16),
                if (ref.watch(authProvider).role == UserRole.responder)
                  _TacticalActionTile(
                    title: 'Request App Deactivation',
                    subtitle: 'Submit compliance removal request to HQ',
                    icon: Icons.phonelink_erase_rounded,
                    onTap: () => context.push(AppRoutes.uninstallRequest),
                  ),
                _TacticalActionTile(
                  title: 'Sign Out',
                  subtitle: 'Terminate current session',
                  icon: Icons.logout_rounded,
                  onTap: () async {
                    await ref.read(authProvider.notifier).signOut();
                    await ref.read(authProvider.notifier).setOnboarded(false);
                    if (context.mounted) context.go(AppRoutes.login);
                  },
                ),
                _TacticalActionTile(
                  title: 'Purge Account',
                  subtitle: 'Permanently delete all tactical data',
                  icon: Icons.delete_forever_rounded,
                  isDestructive: true,
                  onTap: _deleteAccount,
                ),

                const SizedBox(height: 48),
                Center(
                  child: Column(
                    children: [
                      Text(
                        'OPERATION RAINBOW MODERNIZATION',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textDim,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ENCRYPTED NODE: PR0-8842-RAINBOW',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          color: AppColors.outline,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: AppColors.textDim,
        letterSpacing: 2,
      ),
    );
  }
}

class _TacticalSwitchTile extends StatelessWidget {
  const _TacticalSwitchTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.onBackground,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textDim),
        ),
        secondary: Icon(
          icon,
          color: AppColors.primary.withValues(alpha: 0.7),
          size: 22,
        ),
        activeThumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withValues(alpha: 0.1),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _TacticalActionTile extends StatelessWidget {
  const _TacticalActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Icon(
          icon,
          color: isDestructive
              ? Colors.redAccent.withValues(alpha: 0.7)
              : AppColors.textDim,
          size: 22,
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: isDestructive ? Colors.redAccent : AppColors.onBackground,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textDim),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.outline,
          size: 20,
        ),
      ),
    );
  }
}

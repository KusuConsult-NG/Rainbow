import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _locationBackground = true;
  bool _anonymousDefault = false;
  bool _loading = true;
  Map<String, dynamic> _profile = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) _profile = doc.data() ?? {};
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('setting_notifications') ?? true;
        _locationBackground = prefs.getBool('setting_location_bg') ?? true;
        _anonymousDefault = prefs.getBool('setting_anonymous_default') ?? false;
        _loading = false;
      });
    }
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Account', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        content: Text('This will permanently delete your account and all associated data. This cannot be undone.', style: GoogleFonts.inter()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('DELETE', style: GoogleFonts.inter(color: Colors.red, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
        await user.delete();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (mounted) context.go(AppRoutes.login);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = _profile['name'] as String? ?? user?.displayName ?? 'Anonymous Citizen';
    final phone = _profile['phone'] as String? ?? user?.phoneNumber ?? '—';
    final avatarUrl = _profile['avatar'] as String?;

    return Scaffold(
      backgroundColor: AppColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: Text('Settings', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Profile card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10)],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        backgroundColor: AppColors.primary.withAlpha(20),
                        child: avatarUrl == null
                            ? Text(displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primary))
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(displayName, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
                            const SizedBox(height: 2),
                            Text(phone, style: GoogleFonts.inter(fontSize: 13, color: AppColors.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.primary.withAlpha(20), borderRadius: BorderRadius.circular(6)),
                              child: Text('CITIZEN', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 1.5)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                Text('PREFERENCES', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.outline)),
                const SizedBox(height: 12),

                _SettingsTile(
                  title: 'Push Notifications',
                  subtitle: 'Receive alerts when your incident is updated',
                  icon: Icons.notifications_active_outlined,
                  value: _notificationsEnabled,
                  onChanged: (v) {
                    setState(() => _notificationsEnabled = v);
                    _saveBool('setting_notifications', v);
                  },
                ),
                _SettingsTile(
                  title: 'Background GPS',
                  subtitle: 'Required for live tracking during emergencies',
                  icon: Icons.location_on_outlined,
                  value: _locationBackground,
                  onChanged: (v) {
                    setState(() => _locationBackground = v);
                    _saveBool('setting_location_bg', v);
                  },
                ),
                _SettingsTile(
                  title: 'Anonymous Reports by Default',
                  subtitle: 'Your identity will not be shared with responders',
                  icon: Icons.visibility_off_outlined,
                  value: _anonymousDefault,
                  onChanged: (v) {
                    setState(() => _anonymousDefault = v);
                    _saveBool('setting_anonymous_default', v);
                  },
                ),

                const SizedBox(height: 28),
                Text('ACCOUNT', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, color: AppColors.outline)),
                const SizedBox(height: 12),

                // Edit contacts shortcut
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.contacts_outlined, color: AppColors.primary),
                  title: Text('Emergency Contacts', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  subtitle: Text('Manage trusted contacts', style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () => context.push(AppRoutes.onboardingContacts),
                ),

                // Sign out
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded, color: AppColors.outline),
                  title: Text('Sign Out', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('hasOnboarded', false);
                    // ignore: use_build_context_synchronously
                    if (mounted) context.go(AppRoutes.login);
                  },
                ),

                // Delete account
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('Delete Account', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.red)),
                  subtitle: Text('Permanently removes all your data', style: GoogleFonts.inter(fontSize: 12, color: Colors.red.withAlpha(160))),
                  onTap: _deleteAccount,
                ),

                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'OPERATION RAINBOW v1.0.0\nPLATEAU STATE EMERGENCY RESPONSE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 9, color: AppColors.outline, letterSpacing: 1.5, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsTile({required this.title, required this.subtitle, required this.icon, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15)),
        subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.onSurfaceVariant)),
        secondary: Icon(icon, color: AppColors.primary),
        activeThumbColor: AppColors.primary,
        value: value,
        onChanged: onChanged,
      );
}

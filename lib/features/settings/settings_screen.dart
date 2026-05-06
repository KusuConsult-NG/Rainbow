import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/router/app_router.dart';
import '../../shared/widgets/rainbow_app_bar.dart';

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
              child: const Icon(Icons.delete_forever_rounded, color: Colors.red, size: 32),
            ),
            const SizedBox(height: 24),
            Text(
              'TERMINATE ACCOUNT',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action is irreversible. All mission data, tactical reports, and profile telemetry will be permanently purged from the mainframe.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.white10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('CANCEL', style: GoogleFonts.outfit(color: Colors.white)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: Text('TERMINATE', style: GoogleFonts.outfit(fontWeight: FontWeight.w900)),
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
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
        await user.delete();
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (!mounted) return;
        context.go(AppRoutes.login);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TERMINATION FAILED: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = _profile['name'] as String? ?? user?.displayName ?? 'ANONYMOUS CITIZEN';
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
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Profile Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(24),
                    border: AppColors.glassBorder,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.1)],
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
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phone,
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                color: Colors.white38,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
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
                          ],
                        ),
                      ),
                    ],
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
                    _saveBool('setting_notifications', v);
                  },
                ),
                _TacticalSwitchTile(
                  title: 'Geospatial Telemetry',
                  subtitle: 'Enable background GPS for field tracking',
                  icon: Icons.location_on_outlined,
                  value: _locationBackground,
                  onChanged: (v) {
                    setState(() => _locationBackground = v);
                    _saveBool('setting_location_bg', v);
                  },
                ),
                _TacticalSwitchTile(
                  title: 'Stealth Reporting',
                  subtitle: 'Enable anonymous reporting by default',
                  icon: Icons.visibility_off_outlined,
                  value: _anonymousDefault,
                  onChanged: (v) {
                    setState(() => _anonymousDefault = v);
                    _saveBool('setting_anonymous_default', v);
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
                  onTap: () {},
                ),

                const SizedBox(height: 32),
                _buildSectionHeader('DANGER ZONE'),
                const SizedBox(height: 16),
                _TacticalActionTile(
                  title: 'Sign Out',
                  subtitle: 'Terminate current session',
                  icon: Icons.logout_rounded,
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('hasOnboarded', false);
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
                          color: Colors.white24,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ENCRYPTED NODE: PR0-8842-RAINBOW',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          color: Colors.white10,
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
        color: Colors.white24,
        letterSpacing: 2.0,
      ),
    );
  }
}

class _TacticalSwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TacticalSwitchTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Colors.white,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.outfit(fontSize: 12, color: Colors.white38),
        ),
        secondary: Icon(icon, color: AppColors.primary.withValues(alpha: 0.7), size: 22),
        activeThumbColor: AppColors.primary,
        activeTrackColor: AppColors.primary.withValues(alpha: 0.1),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _TacticalActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  const _TacticalActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });

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
          color: isDestructive ? Colors.redAccent.withValues(alpha: 0.7) : Colors.white38,
          size: 22,
        ),
        title: Text(
          title,
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: isDestructive ? Colors.redAccent : Colors.white,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.outfit(fontSize: 12, color: Colors.white38),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white10, size: 20),
      ),
    );
  }
}

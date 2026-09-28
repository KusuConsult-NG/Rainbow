import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/reentry_lock_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _language = 'EN';

  @override
  void initState() {
    super.initState();
    unawaited(_loadLanguage());
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _language = prefs.getString('app_language') ?? 'EN';
    });
  }

  Future<void> _setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', lang);
    setState(() {
      _language = lang;
    });
  }

  Future<void> _updateFullName(String newName) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    await SupabaseConfig.client
        .from('profiles')
        .update({'full_name': newName}).eq('id', user.id);
    unawaited(ref.read(authProvider.notifier).refreshProfile());
  }

  Future<void> _updatePushEnabled(bool enabled) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    await SupabaseConfig.client
        .from('profiles')
        .update({'push_enabled': enabled}).eq('id', user.id);
    unawaited(ref.read(authProvider.notifier).refreshProfile());
  }
  
  Future<void> _addEmergencyContact(String contact) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    final profile = ref.read(authProvider).profile ?? {};
    final contacts = ((profile['emergency_contacts'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList();
    if (!contacts.contains(contact)) {
      contacts.add(contact);
      await SupabaseConfig.client
          .from('profiles')
          .update({'emergency_contacts': contacts}).eq('id', user.id);
      unawaited(ref.read(authProvider.notifier).refreshProfile());
    }
  }

  Future<void> _removeEmergencyContact(String contact) async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;
    final profile = ref.read(authProvider).profile ?? {};
    final contacts = ((profile['emergency_contacts'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList();
    if (contacts.contains(contact)) {
      contacts.remove(contact);
      await SupabaseConfig.client
          .from('profiles')
          .update({'emergency_contacts': contacts}).eq('id', user.id);
      unawaited(ref.read(authProvider.notifier).refreshProfile());
    }
  }

  void _showEditNameDialog(String currentName) {
    final controller = TextEditingController(text: currentName);
    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text('Edit Name', style: GoogleFonts.outfit(color: AppColors.onBackground)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.onBackground),
          decoration: const InputDecoration(
            hintText: 'Full Name',
            hintStyle: TextStyle(color: AppColors.textDim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textDim)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                unawaited(_updateFullName(controller.text.trim()));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Save'),
          ),
        ],
      ),
    ),);
  }

  void _showAddContactDialog() {
    final controller = TextEditingController();
    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainer,
        title: Text('Add Emergency Contact', style: GoogleFonts.outfit(color: AppColors.onBackground)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.onBackground),
          decoration: const InputDecoration(
            hintText: 'Phone Number',
            hintStyle: TextStyle(color: AppColors.textDim),
          ),
          keyboardType: TextInputType.phone,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textDim)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                unawaited(_addEmergencyContact(controller.text.trim()));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Add'),
          ),
        ],
      ),
    ),);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final profile = auth.profile ?? {};
    final fullName = profile['full_name'] as String? ?? 'Citizen User';
    final pushEnabled = profile['push_enabled'] as bool? ?? true;
    final contacts = ((profile['emergency_contacts'] as List<dynamic>?) ?? [])
        .map((e) => e.toString())
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'TACTICAL SYSTEM SETTINGS',
        subtitle: 'PREFERENCES & SECURITY',
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // 1. Profile Card
          ListTile(
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.person_outline, color: AppColors.primary),
            title: Text(
              fullName,
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.onBackground),
            ),
            subtitle: Text(
              auth.user?.email ?? 'Phone User: ${auth.user?.phone ?? "Unknown"}',
              style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12),
            ),
            trailing: IconButton(
                        tooltip: 'Edit your name',
              icon: const Icon(Icons.edit, color: AppColors.textDim),
              onPressed: () => _showEditNameDialog(fullName),
            ),
          ),
          const SizedBox(height: 16),
          
          // 2. Notifications toggle
          SwitchListTile(
            title: Text('Push Notifications', style: GoogleFonts.outfit(color: AppColors.onBackground)),
            subtitle: Text('Receive emergency alerts', style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12)),
            value: pushEnabled,
            activeThumbColor: AppColors.primary,
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onChanged: _updatePushEnabled,
          ),
          const SizedBox(height: 16),

          // 3. Emergency Contacts
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Emergency Contacts', style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold)),
                    IconButton(
                      tooltip: 'Add an emergency contact',
                      icon: const Icon(Icons.add, color: AppColors.primary),
                      onPressed: _showAddContactDialog,
                    ),
                  ],
                ),
                if (contacts.isEmpty)
                  Text('No emergency contacts added.', style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12))
                else
                  ...contacts.map((c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c, style: GoogleFonts.inter(color: AppColors.onBackground)),
                    trailing: IconButton(
                                tooltip: 'Remove this emergency contact',
                      icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                      onPressed: () => _removeEmergencyContact(c),
                    ),
                  ),),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Language
          ListTile(
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.language, color: AppColors.primary),
            title: Text('App Language', style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold)),
            trailing: DropdownButton<String>(
              value: _language,
              dropdownColor: AppColors.surfaceContainer,
              style: GoogleFonts.inter(color: AppColors.onBackground),
              items: const [
                DropdownMenuItem(value: 'EN', child: Text('English')),
                DropdownMenuItem(value: 'HA', child: Text('Hausa')),
              ],
              onChanged: (val) {
                if (val != null) unawaited(_setLanguage(val));
              },
            ),
          ),
          const SizedBox(height: 16),

          // Emergency PINs — per-user, verified on the server.
          ListTile(
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.pin_outlined, color: AppColors.emergency),
            title: Text(
              'Emergency PIN',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.onBackground),
            ),
            subtitle: Text(
              'Set or change your safe and duress PINs',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textDim),
            ),
            onTap: () => context.push(AppRoutes.emergencyPins),
          ),
          const SizedBox(height: 16),

          // Lock the app now.
          //
          // The re-entry lock engages by itself after the app has been away
          // from the foreground for a couple of minutes. This is for the case
          // it cannot see: handing the phone to somebody, deliberately, while
          // staying in the room. Without it the only way to close the app to
          // another person is to sign out, which also gives up the SMS device
          // key and the session — a heavy price for lending a phone.
          //
          // It is also the only way to REACH the lock screen on purpose, which
          // is what lets the browser harness photograph it and assert that the
          // emergency button on it works.
          ListTile(
            key: const ValueKey('lock_now_tile'),
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: const Icon(Icons.lock_outline, color: AppColors.primary),
            title: Text(
              'Lock This Phone',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                color: AppColors.onBackground,
              ),
            ),
            subtitle: Text(
              'Ask for a code before this app can be used again. '
              'The emergency button keeps working.',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textDim),
            ),
            onTap: () {
              ref.read(reentryLockProvider.notifier).lockNow();
              context.go(AppRoutes.lock);
            },
          ),
          const SizedBox(height: 16),

          // 6. App Removal Authorization
          ListTile(
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.security_outlined, color: AppColors.warning),
            title: Text(
              'App Removal Authorization',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.onBackground),
            ),
            onTap: () => context.push(AppRoutes.uninstallRequest),
          ),
          const SizedBox(height: 16),

          // 5. Sign Out
          ListTile(
            tileColor: AppColors.danger.withValues(alpha: 0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
            title: Text(
              'Sign Out Tactical Session',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.danger),
            ),
            onTap: () async {
              await ref.read(authProvider.notifier).signOut();
              if (context.mounted) context.go(AppRoutes.login);
            },
          ),
        ],
      ),
    );
  }
}

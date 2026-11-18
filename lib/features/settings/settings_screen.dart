import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/guardian/guardian_provider.dart';
import 'package:rainbow_app/core/router/app_router.dart';
import 'package:rainbow_app/core/sos/volume_sos.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';
import 'package:rainbow_app/shared/widgets/language_picker.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/reentry_lock_provider.dart';
import 'package:rainbow_app/services/mesh_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:rainbow_app/features/settings/volume_sos_lock_screen_tile.dart';

/// One emergency contact as text.
///
/// Settings stores contacts as strings and the side menu's form stored them as
/// `{name, phone}` maps — in the same column — so a contact saved there showed
/// here as "{name: Ada, phone: 0803…}". Both now store text; this reads the
/// older maps the same way.
String emergencyContactLabel(Object? entry) {
  if (entry is Map) {
    final name = (entry['name'] ?? '').toString().trim();
    final phone = (entry['phone'] ?? '').toString().trim();
    if (name.isEmpty) return phone;
    if (phone.isEmpty) return name;
    return '$name · $phone';
  }
  return entry?.toString() ?? '';
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// This screen's text in the chosen language.
  String _t(String key) => Translations.get(key, ref.read(languageProvider));

  /// Whether this phone relays others' sealed alerts over Bluetooth. Null until
  /// read, so the switch never flashes the wrong position.
  bool? _meshRelay;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMeshRelay());
  }

  Future<void> _loadMeshRelay() async {
    try {
      final enabled = await MeshService.instance.relayEnabled();
      if (mounted) setState(() => _meshRelay = enabled);
    } on Object catch (_) {
      if (mounted) setState(() => _meshRelay = false);
    }
  }

  // ignore: avoid_positional_boolean_parameters, Mirrors a switch's onChanged.
  Future<void> _setMeshRelay(bool enabled) async {
    setState(() => _meshRelay = enabled);
    final running = await MeshService.instance.setRelayEnabled(enabled);
    if (!mounted || !enabled || running) return;
    // Switched on, and the radio did not start. Say so rather than leave a
    // switch that claims something is happening when it is not.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_t('set_bt_unavailable')),
      ),
    );
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
        .map(emergencyContactLabel)
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
        .map(emergencyContactLabel)
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
        title: Text(_t('set_edit_name_title'), style: GoogleFonts.outfit(color: AppColors.onBackground)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.onBackground),
          decoration: InputDecoration(
            hintText: _t('set_full_name'),
            hintStyle: const TextStyle(color: AppColors.textDim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('set_cancel'), style: const TextStyle(color: AppColors.textDim)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                unawaited(_updateFullName(controller.text.trim()));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(_t('set_save')),
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
        title: Text(_t('set_add_contact_title'), style: GoogleFonts.outfit(color: AppColors.onBackground)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.onBackground),
          decoration: InputDecoration(
            hintText: _t('set_phone_number'),
            hintStyle: const TextStyle(color: AppColors.textDim),
          ),
          keyboardType: TextInputType.phone,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('set_cancel'), style: const TextStyle(color: AppColors.textDim)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                unawaited(_addEmergencyContact(controller.text.trim()));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(_t('set_add')),
          ),
        ],
      ),
    ),);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    // Redraw when the language changes; _t reads it.
    ref.watch(languageProvider);
    final profile = auth.profile ?? {};
    final fullName = profile['full_name'] as String? ?? _t('set_default_name');
    final pushEnabled = profile['push_enabled'] as bool? ?? true;
    final contacts = ((profile['emergency_contacts'] as List<dynamic>?) ?? [])
        .map(emergencyContactLabel)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: _t('set_title'),
        subtitle: _t('set_subtitle'),
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
              auth.user?.email ?? '${_t('set_phone_user')} ${auth.user?.phone ?? _t('set_unknown')}',
              style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12),
            ),
            trailing: IconButton(
                        tooltip: _t('set_edit_name'),
              icon: const Icon(Icons.edit, color: AppColors.textDim),
              onPressed: () => _showEditNameDialog(fullName),
            ),
          ),
          const SizedBox(height: 16),
          
          // 2. Notifications toggle
          SwitchListTile(
            title: Text(_t('set_push'), style: GoogleFonts.outfit(color: AppColors.onBackground)),
            subtitle: Text(_t('set_push_desc'), style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12)),
            value: pushEnabled,
            activeThumbColor: AppColors.primary,
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onChanged: _updatePushEnabled,
          ),
          const SizedBox(height: 16),

          // 2b. Bluetooth mesh relaying
          SwitchListTile(
            title: Text(_t('set_relay'), style: GoogleFonts.outfit(color: AppColors.onBackground)),
            subtitle: Text(
              _t('set_relay_desc'),
              style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12),
            ),
            value: _meshRelay ?? false,
            activeThumbColor: AppColors.primary,
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onChanged: _meshRelay == null ? null : _setMeshRelay,
          ),
          const SizedBox(height: 16),

          // 2c. Volume Down x3 silent SOS
          SwitchListTile(
            key: const ValueKey('volume_sos_toggle'),
            title: Text(Translations.get('volume_sos_title', ref.watch(languageProvider)), style: GoogleFonts.outfit(color: AppColors.onBackground)),
            subtitle: Text(
              Translations.get('volume_sos_desc', ref.watch(languageProvider)),
              style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12),
            ),
            value: ref.watch(volumeSosEnabledProvider),
            activeThumbColor: AppColors.primary,
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onChanged: (v) => ref.read(volumeSosEnabledProvider.notifier).set(v),
          ),
          // With the phone locked (Android): the accessibility service.
          const VolumeSosLockScreenTile(),
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
                    Text(_t('set_contacts'), style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold)),
                    IconButton(
                      tooltip: _t('set_add_contact'),
                      icon: const Icon(Icons.add, color: AppColors.primary),
                      onPressed: _showAddContactDialog,
                    ),
                  ],
                ),
                if (contacts.isEmpty)
                  Text(_t('set_no_contacts'), style: GoogleFonts.inter(color: AppColors.textDim, fontSize: 12))
                else
                  ...contacts.map((c) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(c, style: GoogleFonts.inter(color: AppColors.onBackground)),
                    trailing: IconButton(
                                tooltip: _t('set_remove_contact'),
                      icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger),
                      onPressed: () => _removeEmergencyContact(c),
                    ),
                  ),),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Language
          //
          // This was a DropdownButton bound to a private `_language` string and
          // written to SharedPreferences as `app_language` = 'HA'. Nothing
          // reads that key: every translated string watches `languageProvider`
          // from shared/localization/translations.dart, which stores `app_lang`
          // = 'ha'. So this control changed nothing, and it offered two of the
          // three languages the app actually has. One widget, one provider.
          const LanguagePicker(),
          const SizedBox(height: 16),

          // AI Emergency Guardian.
          ListTile(
            key: const ValueKey('guardian_settings_tile'),
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: Icon(
              ref.watch(guardianProvider).active ? Icons.hearing : Icons.hearing_disabled,
              color: AppColors.primary,
            ),
            title: Text(
              Translations.get('guardian_title', ref.watch(languageProvider)),
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.onBackground),
            ),
            subtitle: Text(
              Translations.get('guardian_settings_desc', ref.watch(languageProvider)),
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textDim),
            ),
            onTap: () => context.push(AppRoutes.guardian),
          ),
          const SizedBox(height: 16),

          // Emergency PINs — per-user, verified on the server.
          ListTile(
            tileColor: AppColors.surfaceContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            leading: const Icon(Icons.pin_outlined, color: AppColors.emergency),
            title: Text(
              _t('set_pin'),
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppColors.onBackground),
            ),
            subtitle: Text(
              _t('set_pin_desc'),
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
              _t('set_lock'),
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                color: AppColors.onBackground,
              ),
            ),
            subtitle: Text(
              _t('set_lock_desc'),
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
              _t('set_removal'),
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
              _t('set_sign_out'),
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

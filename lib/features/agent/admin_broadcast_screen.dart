import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final _messageCtrl = TextEditingController();
  String _severity = 'MEDIUM';
  String _audience = 'ALL';
  int _expiryHours = 24;

  Future<void> _sendBroadcast() async {
    if (_messageCtrl.text.trim().isEmpty) return;

    try {
      final expiresAt = DateTime.now().add(Duration(hours: _expiryHours)).toIso8601String();
      await SupabaseConfig.client.from('system_alerts').insert({
        'message': _messageCtrl.text.trim(),
        'severity': _severity,
        'target_type': _audience,
        'expires_at': expiresAt, // Column added by migration v2
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Broadcast sent successfully.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending broadcast: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'HQ BROADCAST SENDER',
        subtitle: 'SYSTEM ANNOUNCEMENTS',
        showBack: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Message',
            style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _messageCtrl,
            maxLines: 4,
            style: const TextStyle(color: AppColors.onBackground),
            decoration: InputDecoration(
              hintText: 'Enter broadcast message...',
              hintStyle: const TextStyle(color: AppColors.textDim),
              filled: true,
              fillColor: AppColors.surfaceContainer,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 24),

          Text('Severity', style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _severity,
            dropdownColor: AppColors.surfaceContainer,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceContainer,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: AppColors.onBackground),
            items: ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _severity = val);
            },
          ),
          const SizedBox(height: 24),

          Text('Audience', style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _audience,
            dropdownColor: AppColors.surfaceContainer,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceContainer,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: AppColors.onBackground),
            items: ['ALL', 'CITIZENS', 'AGENTS', 'LGA_JOS_NORTH', 'LGA_JOS_SOUTH']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _audience = val);
            },
          ),
          const SizedBox(height: 24),

          Text('Expiry', style: GoogleFonts.outfit(color: AppColors.onBackground, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            value: _expiryHours,
            dropdownColor: AppColors.surfaceContainer,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceContainer,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            style: const TextStyle(color: AppColors.onBackground),
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 Hour')),
              DropdownMenuItem(value: 6, child: Text('6 Hours')),
              DropdownMenuItem(value: 24, child: Text('24 Hours')),
              DropdownMenuItem(value: 48, child: Text('48 Hours')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _expiryHours = val);
            },
          ),
          const SizedBox(height: 40),

          ElevatedButton(
            onPressed: _sendBroadcast,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('SEND BROADCAST', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

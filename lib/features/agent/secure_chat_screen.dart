// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

/// Documentation for this public member.

class SecureChatScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const SecureChatScreen({required this.alertData, super.key});

  /// Documentation for this public member.

  final Map<String, dynamic> alertData;

  @override
  ConsumerState<SecureChatScreen> createState() => _SecureChatScreenState();
}

class _SecureChatScreenState extends ConsumerState<SecureChatScreen> {
  final _controller = TextEditingController();

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final auth = ref.read(authProvider);
    final user = auth.user;
    if (user == null) return;

    final alertId = widget.alertData['id'] as String;

    try {
      await SupabaseConfig.client.from('chat_messages').insert({
        'alert_id': alertId,
        'sender_id': user.id,
        'sender_name': auth.profile?['full_name'] ?? 'Tactical Unit',
        'sender_role': auth.role.name.toUpperCase(),
        'message': text,
      });
    } catch (e) {
      debugPrint('[CHAT_ERR] Secure chat insert failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertId = widget.alertData['id'] as String;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: 'TACTICAL COMMS CHANNEL',
        subtitle: 'INCIDENT REF #${alertId.substring(0, 8)}',
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseConfig.client
                  .from('chat_messages')
                  .stream(primaryKey: ['id'])
                  .eq('alert_id', alertId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading channel messages',
                      style: GoogleFonts.outfit(color: AppColors.danger),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'NO SECURE MESSAGES RECORDED',
                      style: GoogleFonts.outfit(
                        color: AppColors.textDim,
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                  );
                }

                final myUid = ref.watch(authProvider).user?.id;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index];
                    final isMe = data['sender_id'] == myUid;
                    final text = data['message'] as String? ?? '';
                    final senderName = data['sender_name'] as String? ?? 'Unit';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isMe
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : AppColors.outline,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMe ? 'YOU' : senderName.toUpperCase(),
                              style: GoogleFonts.outfit(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isMe ? AppColors.primary : AppColors.textDim,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              text,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: AppColors.onBackground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.surfaceContainer,
              border: Border(top: BorderSide(color: AppColors.outline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: GoogleFonts.inter(color: AppColors.onBackground),
                    decoration: InputDecoration(
                      hintText: 'Transmit tactical telemetry...',
                      hintStyle: GoogleFonts.inter(color: AppColors.textDim),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: AppColors.primary),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

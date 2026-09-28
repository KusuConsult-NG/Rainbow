// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

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

  /// THE SUBSCRIPTION IS CREATED ONCE, NOT ON EVERY FRAME.
  ///
  /// This used to be built inline in `build()`:
  ///
  ///     stream: SupabaseConfig.client.from('chat_messages')
  ///         .stream(primaryKey: ['id']).eq('alert_id', alertId),
  ///
  /// `.stream()` opens a realtime channel, so writing it there opens a NEW one
  /// on every rebuild and discards the one before it. Sending a message clears
  /// the text field, which rebuilds, which churned the channel — and the
  /// replacement came up in an error state. So the sender's own screen replaced
  /// the conversation with "Error loading channel messages" at the exact moment
  /// they sent something, while the message itself was written perfectly well.
  /// Every message after that was invisible to them until they left the screen
  /// and came back.
  ///
  /// A `late final` initialised in `initState` gives the widget one channel for
  /// its lifetime, which is what a subscription is meant to be.
  late final Stream<List<Map<String, dynamic>>> _messages;

  @override
  void initState() {
    super.initState();
    _messages = SupabaseConfig.client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('alert_id', widget.alertData['id'] as String);
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final auth = ref.read(authProvider);
    final user = auth.user;
    if (user == null) return;

    final alertId = widget.alertData['id'] as String;

    // CLEAR ONLY ONCE IT IS SENT.
    //
    // This cleared the box first and then swallowed any failure in a
    // `debugPrint`. On a tactical channel that means the operator types a
    // message, watches it disappear, sees it never arrive in the thread, and
    // has nothing to tell them whether it went. Row-level security, an expired
    // session and a dead network all present identically: as silence.
    _controller.clear();
    try {
      await SupabaseConfig.client.from('chat_messages').insert({
        'alert_id': alertId,
        'sender_id': user.id,
        'sender_name': auth.profile?['full_name'] ?? 'Tactical Unit',
        // WHO IS SPEAKING, NOT MERELY THAT THEY ARE STAFF.
        //
        // This wrote `auth.role.name.toUpperCase()`, and `UserRole` has three
        // values: citizen, responder, unknown. So EVERY staff message on a
        // tactical channel was signed 'RESPONDER' — an HQ commander's
        // instruction labelled identically to a neighbouring unit's remark.
        // On a channel people act on, the rank attached to "hold position" is
        // most of its meaning.
        //
        // It also put a third vocabulary in one column: the citizen's screen
        // and the console both write the real `profiles.role`, so the same
        // thread carried HQ_COMMAND from one writer and RESPONDER from another
        // for the same person. The profile role is the answer everywhere now,
        // with the coarse enum only as a fallback for a session whose profile
        // has not loaded.
        'sender_role': (auth.profile?['role'] as String?)?.toUpperCase()
            ?? auth.role.name.toUpperCase(),
        'message': text,
      });
    } catch (e) {
      debugPrint('[CHAT_ERR] Secure chat insert failed: $e');
      if (!mounted) return;
      // Give the text back, so it can be retried rather than retyped.
      _controller.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: const Text('MESSAGE NOT SENT — check your connection and retry'),
          action: SnackBarAction(
            label: 'RETRY',
            textColor: Colors.white,
            onPressed: () => unawaited(_sendMessage()),
          ),
        ),
      );
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
              stream: _messages,
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
                  tooltip: 'Send',
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

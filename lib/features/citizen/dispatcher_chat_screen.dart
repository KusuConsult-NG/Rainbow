// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/services/speech_service.dart';
import 'package:rainbow_app/services/tts_service.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';
import 'package:rainbow_app/shared/localization/translations.dart';

/// Documentation for this public member.

class DispatcherChatScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const DispatcherChatScreen({required this.alertId, super.key});

  /// Documentation for this public member.

  final String alertId;

  @override
  ConsumerState<DispatcherChatScreen> createState() =>
      _DispatcherChatScreenState();
}

class _DispatcherChatScreenState extends ConsumerState<DispatcherChatScreen> {
  final _controller = TextEditingController();
  bool _isListening = false;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  String? _lastMessageId;

  @override
  void initState() {
    super.initState();
    _subscription = SupabaseConfig.client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('alert_id', widget.alertId)
        .listen((messages) {
      if (messages.isNotEmpty) {
        final newest = messages.last;
        final msgId = newest['id'] as String;
        final senderId = newest['sender_id'] as String?;
        final text = newest['message'] as String?;
        final myUid = ref.read(authProvider).user?.id;

        if (msgId != _lastMessageId && senderId != myUid && text != null && text.isNotEmpty) {
          _lastMessageId = msgId;
          unawaited(TtsService.instance.speak(text));
        }
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final auth = ref.read(authProvider);
    final user = auth.user;
    if (user == null) return;

    final profile = auth.profile ?? {};
    final fullName = profile['full_name'] as String? ?? profile['name'] as String? ?? (user.email?.split('@')[0] ?? 'User');
    final role = (profile['role'] as String? ?? 'CITIZEN').toUpperCase();

    _controller.clear();

    try {
      await SupabaseConfig.client.from('chat_messages').insert({
        'alert_id': widget.alertId,
        'sender_id': user.id,
        'sender_name': fullName,
        'sender_role': role,
        'message': text,
      });
    } catch (e) {
      debugPrint('[CHAT_ERR] Message insert failed: $e');
    }
  }

  void _toggleListening() {
    final speechService = SpeechService.instance;
    if (_isListening) {
      unawaited(speechService.stopListening());
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      unawaited(speechService.startListening(onResult: (text) {
        setState(() {
          _controller.text = text;
          _isListening = false;
        });
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(languageProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: Translations.get('live_dispatch_channel', currentLang),
        subtitle: '${Translations.get('alert_ref', currentLang)} #${widget.alertId.length > 8 ? widget.alertId.substring(0, 8) : widget.alertId}',
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: SupabaseConfig.client
                  .from('chat_messages')
                  .stream(primaryKey: ['id'])
                  .eq('alert_id', widget.alertId),
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
                    final senderName = data['sender_name'] as String? ?? 'Dispatcher';

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
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
                    color: _isListening ? AppColors.danger : AppColors.primary,
                  ),
                  onPressed: _toggleListening,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: GoogleFonts.inter(color: AppColors.onBackground),
                    decoration: InputDecoration(
                      hintText: 'Type secure message...',
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

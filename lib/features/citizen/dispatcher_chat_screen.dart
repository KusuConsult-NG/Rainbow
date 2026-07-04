// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/firestore_provider.dart';
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
  StreamSubscription<QuerySnapshot>? _subscription;
  String? _lastMessageId;
  final DateTime _screenOpenTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    final uid = ref.read(authProvider).user?.uid;
    _subscription = ref.read(firestoreProvider)
        .collection('alerts')
        .doc(widget.alertId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final latestDoc = snapshot.docs.last;
        final data = latestDoc.data() as Map<String, dynamic>?;
        if (data != null && latestDoc.id != _lastMessageId) {
          _lastMessageId = latestDoc.id;
          final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
          if (timestamp == null ||
              timestamp.isAfter(
                  _screenOpenTime.subtract(const Duration(seconds: 2)))) {
            final senderUid = data['senderUid'];
            if (senderUid != uid) {
              final text = data['text']?.toString() ?? '';
              final senderName =
                  data['senderName']?.toString() ?? 'Dispatcher';
              if (text.isNotEmpty) {
                unawaited(
                    TtsService.instance.speak("$senderName says: $text"));
              }
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_subscription?.cancel());
    if (_isListening) {
      SpeechService.instance.stopListening();
    }
    super.dispose();
  }

  Future<void> _toggleDictation() async {
    if (_isListening) {
      await SpeechService.instance.stopListening();
      setState(() => _isListening = false);
    } else {
      await SpeechService.instance.initialize();
      await SpeechService.instance.startListening(
        onResult: (text) {
          setState(() {
            _controller.text = text;
          });
        },
      );
      setState(() => _isListening = true);
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final auth = ref.read(authProvider);
    final uid = auth.user?.uid ?? 'unknown';

    await ref.read(firestoreProvider)
        .collection('alerts')
        .doc(widget.alertId)
        .collection('messages')
        .add({
      'text': text,
      'senderUid': uid,
      'senderName': auth.profile?['displayName'] ?? 'Citizen',
      'senderRole': auth.role.toString(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authProvider).user?.uid;
    final lang = ref.watch(languageProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: RainbowAppBar(
        title: Translations.get('chat_title', lang),
        subtitle: Translations.get('chat_subtitle', lang),
        showBack: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: ref.watch(firestoreProvider)
                  .collection('alerts')
                  .doc(widget.alertId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Failed to load chat: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: AppColors.emergency,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snapshot.data!.docs;
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      Translations.get('chat_placeholder', lang),
                      style: GoogleFonts.outfit(
                        color: AppColors.textDim,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final msg = messages[i].data()! as Map<String, dynamic>;
                    final isMe = msg['senderUid'] == uid;
                    final isHQ =
                        msg['senderRole']?.toString().contains('HQ') ?? false;

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : (isHQ
                                  ? AppColors.accent.withValues(alpha: 0.1)
                                  : AppColors.surfaceContainer),
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isMe
                                // ignore: use_named_constants, Stylistic override to match system design
                                ? const Radius.circular(0)
                                : const Radius.circular(16),
                            bottomLeft: !isMe
                                // ignore: use_named_constants, Stylistic override to match system design
                                ? const Radius.circular(0)
                                : const Radius.circular(16),
                          ),
                          border: Border.all(
                            color: isMe
                                ? AppColors.primary.withValues(alpha: 0.3)
                                : (isHQ
                                    ? AppColors.accent.withValues(alpha: 0.3)
                                    : AppColors.outline),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMe
                                  ? 'YOU'
                                  : (msg['senderName']
                                          ?.toString()
                                          .toUpperCase() ??
                                      'DISPATCHER'),
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: isMe
                                    ? AppColors.primary
                                    : (isHQ
                                        ? AppColors.accent
                                        : AppColors.textDim),
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              msg['text']?.toString() ?? '',
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                color: AppColors.onSurface,
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
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.outline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: GoogleFonts.outfit(color: AppColors.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Message HQ...',
                      hintStyle: GoogleFonts.outfit(color: AppColors.textDim),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    color: _isListening ? AppColors.emergency : AppColors.primary,
                  ),
                  onPressed: _toggleDictation,
                ),
                IconButton(
                  icon:
                      const Icon(Icons.send_rounded, color: AppColors.primary),
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

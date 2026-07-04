// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/shared/widgets/rainbow_app_bar.dart';

/// Documentation for this public member.

class SecureChatScreen extends ConsumerStatefulWidget {
  /// Documentation for this public member.
  const SecureChatScreen({required this.alertDoc, super.key});

  /// Documentation for this public member.

  final DocumentSnapshot alertDoc;

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
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';

    await FirebaseFirestore.instance
        .collection('alerts')
        .doc(widget.alertDoc.id)
        .collection('messages')
        .add({
      'text': text,
      'senderUid': uid,
      'senderName': auth.profile?['displayName'] ?? 'Tactical Unit',
      'senderRole': auth.role.toString(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const RainbowAppBar(
        title: 'SECURE COMM LINK',
        subtitle: 'ENCRYPTED TACTICAL CHANNEL',
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('alerts')
                  .doc(widget.alertDoc.id)
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
                      'CHANNEL SECURED. WAITING FOR TRANSMISSION.',
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
                              ? AppColors.primary.withValues(alpha: 0.2)
                              : AppColors.surfaceContainer,
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
                                ? AppColors.primary.withValues(alpha: 0.5)
                                : AppColors.outline,
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
                                      'UNKNOWN'),
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: isMe
                                    ? AppColors.primary
                                    : AppColors.textDim,
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
                      hintText: 'Transmit message...',
                      hintStyle: GoogleFonts.outfit(color: AppColors.textDim),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
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

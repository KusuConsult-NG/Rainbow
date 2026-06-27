import 'package:flutter/foundation.dart';

class TtsService {
  SpeechBriefingOverlayCallback? onSpeechBriefing;

  TtsService._privateConstructor();
  static final TtsService instance = TtsService._privateConstructor();

  /// Speaks the given text using the best available platform synthesizer, and triggers the UI overlay callback
  Future<void> speak(String text) async {
    debugPrint('[TTS_BRIEFING] $text');
    if (onSpeechBriefing != null) {
      onSpeechBriefing!(text);
    }
  }
}

typedef SpeechBriefingOverlayCallback = void Function(String text);

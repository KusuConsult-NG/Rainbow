import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  SpeechBriefingOverlayCallback? onSpeechBriefing;
  bool _useFallback = false;

  set useFallback(bool value) {
    _useFallback = value;
  }

  TtsService._privateConstructor() {
    _initTts();
  }

  static final TtsService instance = TtsService._privateConstructor();

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
    } catch (e) {
      debugPrint('[TTS_INIT_ERR] Failed to initialize native TTS: $e');
    }
  }

  /// Speaks the given text using the best available platform synthesizer, and triggers the UI overlay callback
  Future<void> speak(String text) async {
    debugPrint('[TTS_BRIEFING] $text');
    if (onSpeechBriefing != null) {
      onSpeechBriefing!(text);
    }
    if (!_useFallback && !kIsWeb) {
      try {
        await _flutterTts.speak(text);
      } catch (e) {
        debugPrint('[TTS_SPEAK_ERR] Failed to speak text: $e');
      }
    }
  }
}

typedef SpeechBriefingOverlayCallback = void Function(String text);

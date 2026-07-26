import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum AudioOutputMode { speaker, earpiece }

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();
  static const _audioChannel = MethodChannel('com.operationrainbow.app/audio_routing');
  SpeechBriefingOverlayCallback? onSpeechBriefing;
  bool _useFallback = false;
  AudioOutputMode _outputMode = AudioOutputMode.speaker;

  AudioOutputMode get outputMode => _outputMode;

  set useFallback(bool value) {
    _useFallback = value;
  }

  TtsService._privateConstructor() {
    unawaited(_initTts());
  }

  static final TtsService instance = TtsService._privateConstructor();

  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await setAudioOutputMode(AudioOutputMode.speaker);
    } catch (e) {
      debugPrint('[TTS_INIT_ERR] Failed to initialize native TTS: $e');
    }
  }

  Future<void> setAudioOutputMode(AudioOutputMode mode) async {
    _outputMode = mode;
    try {
      if (!kIsWeb) {
        try {
          await _audioChannel.invokeMethod('setSpeakerphone', {
            'enabled': mode == AudioOutputMode.speaker,
          });
        } catch (e) {
          debugPrint('[AUDIO_METHOD_CHANNEL_ERR] MethodChannel routing fallback: $e');
        }
      }
      if (mode == AudioOutputMode.speaker) {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [IosTextToSpeechAudioCategoryOptions.defaultToSpeaker],
        );
      } else {
        await _flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playAndRecord,
          [],
        );
      }
      debugPrint('[TTS_AUDIO] Output mode set to: ${mode.name.toUpperCase()}');
    } catch (e) {
      debugPrint('[TTS_AUDIO_ERR] Failed to set audio category: $e');
    }
  }

  Future<void> toggleAudioOutputMode() async {
    final nextMode = _outputMode == AudioOutputMode.speaker
        ? AudioOutputMode.earpiece
        : AudioOutputMode.speaker;
    await setAudioOutputMode(nextMode);
  }

  /// Speaks the given text using the best available platform synthesizer, and triggers the UI overlay callback
  Future<void> speak(String text) async {
    debugPrint('[TTS_BRIEFING] [MODE: ${_outputMode.name.toUpperCase()}] $text');
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

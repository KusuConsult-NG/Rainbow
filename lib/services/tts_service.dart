import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AudioOutputMode { speaker, earpiece }

class TtsService {

  TtsService._privateConstructor() {
    unawaited(_initTts());
  }
  final FlutterTts _flutterTts = FlutterTts();
  static const _audioChannel = MethodChannel('com.operationrainbow.app/audio_routing');
  static const _modeKey = 'tts_output_mode';

  /// Called with each spoken line, for a UI that wants to show it.
  ///
  /// Nothing assigns this. It is kept because `speak` is the single place a
  /// briefing exists as text and a caption overlay would hang off exactly
  /// here — but the doc comment used to claim it "triggers the UI overlay
  /// callback", which described a feature that does not exist.
  SpeechBriefingOverlayCallback? onSpeechBriefing;

  /// Whether the service is running in its no-plugin fallback mode.
  bool useFallback = false;
  AudioOutputMode _outputMode = AudioOutputMode.speaker;

  AudioOutputMode get outputMode => _outputMode;


  static final TtsService instance = TtsService._privateConstructor();

  Future<void> _initTts() async {
    // RESTORE THE CHOSEN MODE BEFORE ANYTHING CAN SPEAK.
    //
    // `_outputMode` was an in-memory field that reset to `speaker` on every
    // launch. STEALTH EARPIECE exists so an incoming briefing does not
    // announce a covert officer's position out loud; an officer who selected
    // it got loudspeaker back the next time the app started, having been told
    // nothing. A safety setting that silently reverts is worse than one that
    // was never offered.
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_modeKey);
      if (saved == AudioOutputMode.earpiece.name) {
        _outputMode = AudioOutputMode.earpiece;
      }
    } catch (e) {
      debugPrint('[TTS_INIT_WARN] Could not read the saved audio mode: $e');
    }

    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1);
      await _flutterTts.setPitch(1);
      await setAudioOutputMode(_outputMode);
    } catch (e) {
      debugPrint('[TTS_INIT_ERR] Failed to initialize native TTS: $e');
    }
  }

  Future<void> setAudioOutputMode(AudioOutputMode mode) async {
    _outputMode = mode;
    // Persisted before the routing call, not after: the routing can throw on a
    // device with no telephony audio, and the officer's CHOICE should survive
    // that even when the hardware cannot honour it.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, mode.name);
    } catch (e) {
      debugPrint('[TTS_MODE_PERSIST_ERR] Could not save the audio mode: $e');
    }
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
    onSpeechBriefing?.call(text);
    if (!useFallback && !kIsWeb) {
      try {
        await _flutterTts.speak(text);
      } catch (e) {
        debugPrint('[TTS_SPEAK_ERR] Failed to speak text: $e');
      }
    }
  }
}

typedef SpeechBriefingOverlayCallback = void Function(String text);

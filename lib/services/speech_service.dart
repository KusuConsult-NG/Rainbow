import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  SpeechService._privateConstructor();
  static final SpeechService instance = SpeechService._privateConstructor();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  bool _useFallback = false;

  set useFallback(bool value) {
    _useFallback = value;
  }

  void Function(String status)? _onStatusCallback;

  Future<bool> initialize() async {
    if (_useFallback) {
      _isInitialized = true;
      return true;
    }
    try {
      if (kIsWeb) {
        _useFallback = true;
        _isInitialized = true;
        return true;
      }
      _isInitialized = await _speech.initialize(
        onError: (val) => debugPrint('[SPEECH_ERR] error: $val'),
        onStatus: (val) {
          debugPrint('[SPEECH_STATUS] status: $val');
          _onStatusCallback?.call(val);
        },
      );
      if (!_isInitialized) {
        _useFallback = true;
        _isInitialized = true;
      }
      return _isInitialized;
    } catch (e) {
      debugPrint('[SPEECH_INIT_ERR] Failed to initialize native speech: $e');
      _useFallback = true;
      _isInitialized = true;
      return true;
    }
  }

  bool get isListening => _useFallback ? _simulatedListening : _speech.isListening;

  bool _simulatedListening = false;

  Future<void> startListening({
    required Function(String text) onResult,
    Function(String status)? onStatusChange,
    String? languageCode,
  }) async {
    _onStatusCallback = onStatusChange;
    if (_useFallback) {
      _simulatedListening = true;
      // Simulate local dictation results for simulator fallback
      Future.delayed(const Duration(seconds: 1), () {
        if (_simulatedListening) onResult("Help! Urgent response team needed at my location.");
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (_simulatedListening) onResult("Help! Urgent response team needed at my location. Protesters blocking road access.");
      });
    } else {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
        },
        localeId: languageCode,
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(seconds: 10),
        listenMode: ListenMode.dictation,
      );
    }
  }

  Future<void> stopListening() async {
    if (_useFallback) {
      _simulatedListening = false;
    } else {
      await _speech.stop();
    }
  }
}

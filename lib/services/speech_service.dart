import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  SpeechService._privateConstructor();
  static final SpeechService instance = SpeechService._privateConstructor();

  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  /// Whether the service is running in its no-plugin fallback mode.
  bool useFallback = false;


  void Function(String status)? _onStatusCallback;

  Future<bool> initialize() async {
    if (useFallback) {
      _isInitialized = true;
      return true;
    }
    try {
      if (kIsWeb) {
        useFallback = true;
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
        useFallback = true;
        _isInitialized = true;
      }
      return _isInitialized;
    } catch (e) {
      debugPrint('[SPEECH_INIT_ERR] Failed to initialize native speech: $e');
      useFallback = true;
      _isInitialized = true;
      return true;
    }
  }

  bool get isListening => useFallback ? _simulatedListening : _speech.isListening;

  bool _simulatedListening = false;

  Future<void> startListening({
    required void Function(String text) onResult,
    void Function(String status)? onStatusChange,
    String? languageCode,
  }) async {
    _onStatusCallback = onStatusChange;
    if (useFallback) {
      _simulatedListening = true;
      // Simulate local dictation results for simulator fallback
      Future.delayed(const Duration(seconds: 1), () {
        if (_simulatedListening) onResult('Help! Urgent response team needed at my location.');
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (_simulatedListening) onResult('Help! Urgent response team needed at my location. Protesters blocking road access.');
      });
    } else {
      await _speech.listen(
        onResult: (result) {
          onResult(result.recognizedWords);
        },
        // speech_to_text 7.x deprecated the top-level listenFor/pauseFor/
        // localeId/listenMode in favour of SpeechListenOptions, which carries
        // all four.
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          listenFor: const Duration(minutes: 10),
          pauseFor: const Duration(seconds: 10),
          localeId: languageCode,
        ),
      );
    }
  }

  Future<void> stopListening() async {
    if (useFallback) {
      _simulatedListening = false;
    } else {
      await _speech.stop();
    }
  }
}

/// Guardian phase 2: speech to text on the phone, with no network.
///
/// Microphone samples go through a voice-activity detector, and each stretch
/// of speech, once it ends, is transcribed as a whole by a small offline
/// model. A quiet room costs almost nothing: the recognizer runs only on
/// speech. The text goes to [DistressDetector], the same tested rules as
/// phase 1.
///
/// WHY WHOLE STRETCHES, NOT A STREAMING MODEL. A streaming recognizer gives
/// words as they are spoken, which would send an SOS a second sooner. The
/// small streaming English model was tried first and measured on synthetic
/// distress phrases: it returned nothing at all for "They are trying to kill
/// me", and dropped the opening words of most others ("UE GOAT SINGS" for "I
/// think the blue goat sings"). This model, seeing each utterance whole, got
/// all 38 test phrases near-verbatim, and is smaller. A second of delay after
/// the phrase ends is the price; an SOS that never fires is not acceptable.
///
/// WHY NOT A KEYWORD SPOTTER. It cannot tell "they're kidnapping me" from
/// "nobody is kidnapping me", and it needs every phrase, the user's secret
/// one included, pre-split into its model's sub-word tokens, which nothing on
/// the phone can do.
///
/// Plain Dart and `package:sherpa_onnx`, no Flutter: the same code runs in the
/// app and in `tool/guardian_eval.dart`, which measures it on recordings.
///
/// Models (bundled under assets/guardian/, see LICENSES.md there):
/// - zipformer transducer, English, small, int8 (Apache-2.0);
/// - Silero VAD (MIT).
library;

import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Where the model files are, as paths on disk (the native code reads files,
/// not Flutter assets).
class GuardianModelFiles {
  const GuardianModelFiles({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
    required this.vad,
  });

  /// The files in [dir], named as they are bundled.
  factory GuardianModelFiles.inDirectory(String dir) => GuardianModelFiles(
        encoder: '$dir/$encoderName',
        decoder: '$dir/$decoderName',
        joiner: '$dir/$joinerName',
        tokens: '$dir/$tokensName',
        vad: '$dir/$vadName',
      );

  static const String encoderName = 'encoder-epoch-99-avg-1.int8.onnx';
  static const String decoderName = 'decoder-epoch-99-avg-1.int8.onnx';
  static const String joinerName = 'joiner-epoch-99-avg-1.int8.onnx';
  static const String tokensName = 'tokens.txt';
  static const String vadName = 'silero_vad.onnx';

  static const List<String> all = [
    encoderName, decoderName, joinerName, tokensName, vadName,
  ];

  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  final String vad;
}

/// Turns 16 kHz mono samples into text, offline, one utterance at a time.
class OfflineTranscriber {
  OfflineTranscriber(
    GuardianModelFiles files, {
    required this.onText,
    this.numThreads = 1,
    String? hausaDir,
  }) {
    _vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: files.vad,
          // Ends an utterance after 0.6 s of quiet: long enough not to cut a
          // frightened, broken sentence in two, short enough that the text
          // arrives promptly.
          minSilenceDuration: 0.6,
          minSpeechDuration: 0.2,
          // Unbroken talk is cut into pieces of at most this, so a long
          // stretch of speech is still checked as it goes.
          maxSpeechDuration: maxUtteranceSeconds.toDouble(),
        ),
        numThreads: 1,
      ),
      bufferSizeInSeconds: maxUtteranceSeconds * 2.0,
    );
    _recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          transducer: sherpa.OfflineTransducerModelConfig(
            encoder: files.encoder,
            decoder: files.decoder,
            joiner: files.joiner,
          ),
          tokens: files.tokens,
          numThreads: numThreads,
          modelType: 'transducer',
        ),
      ),
    );
    // Phase 3: the downloaded Hausa model (hausa_model.dart), a Whisper
    // fine-tuned on Hausa. Each utterance is transcribed by both, and both
    // texts go to the detector, which holds the rules for every language.
    if (hausaDir != null) {
      _hausa = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            whisper: sherpa.OfflineWhisperModelConfig(
              encoder: '$hausaDir/hausa-encoder.int8.onnx',
              decoder: '$hausaDir/hausa-decoder.int8.onnx',
              language: 'ha',
              task: 'transcribe',
            ),
            tokens: '$hausaDir/hausa-tokens.txt',
            numThreads: numThreads,
            debug: false,
          ),
        ),
      );
    }
  }

  sherpa.OfflineRecognizer? _hausa;

  /// Whether the Hausa model is loaded.
  bool get hearsHausa => _hausa != null;

  static const int sampleRate = 16000;
  static const int maxUtteranceSeconds = 12;
  static const int _window = 512; // Silero's window at 16 kHz.

  /// Called with each utterance's text once it has ended.
  final void Function(String text) onText;
  final int numThreads;

  late final sherpa.VoiceActivityDetector _vad;
  late final sherpa.OfflineRecognizer _recognizer;

  Float32List _pending = Float32List(0);
  bool _freed = false;

  // The last few seconds of audio, so each utterance can be widened a little
  // before it is transcribed. The detector clips the start of speech: on a
  // synthetic test, "The blue goat sings" reached the recognizer as "BLUE
  // GOAT SINGS" and the secret phrase was missed. Indexed by sample number
  // since the detector last started, the same numbering as its segments.
  static const int _lead = sampleRate * 3 ~/ 10; // 0.3 s before speech.
  static const int _tail = sampleRate * 2 ~/ 10; // 0.2 s after it.
  final Float32List _history = Float32List(sampleRate * (maxUtteranceSeconds + 4));
  int _fed = 0; // Samples given to the detector since it started.

  void _remember(Float32List w) {
    for (var i = 0; i < w.length; i++) {
      _history[(_fed + i) % _history.length] = w[i];
    }
    _fed += w.length;
  }

  /// Samples [from, to) from the history, as far as it still holds them.
  Float32List _recall(int from, int to) {
    final oldest = _fed - _history.length;
    final a = from < 0 ? 0 : (from < oldest ? oldest : from);
    final b = to > _fed ? _fed : to;
    if (b <= a) return Float32List(0);
    final out = Float32List(b - a);
    for (var i = 0; i < out.length; i++) {
      out[i] = _history[(a + i) % _history.length];
    }
    return out;
  }

  /// Feeds microphone samples, 16 kHz mono, in the range [-1, 1].
  void accept(Float32List samples) {
    if (_freed || samples.isEmpty) return;
    var data = samples;
    if (_pending.isNotEmpty) {
      data = Float32List(_pending.length + samples.length)
        ..setAll(0, _pending)
        ..setAll(_pending.length, samples);
    }
    var offset = 0;
    while (data.length - offset >= _window) {
      final w = Float32List.sublistView(data, offset, offset + _window);
      _remember(w);
      _vad.acceptWaveform(w);
      offset += _window;
    }
    _pending = Float32List.fromList(Float32List.sublistView(data, offset));
    _drain();
  }

  /// Transcribes every utterance the detector has finished.
  void _drain() {
    while (!_vad.isEmpty()) {
      final segment = _vad.front();
      _vad.pop();
      final start = segment.start;
      final end = start + segment.samples.length;
      final widened = _recall(start - _lead, end + _tail);
      // The history always holds a whole utterance plus its margins; the
      // detector's own copy is the fallback should that ever not be true.
      _transcribe(widened.length >= segment.samples.length ? widened : segment.samples);
    }
  }

  void _transcribe(Float32List speech) {
    for (final recognizer in [_recognizer, if (_hausa != null) _hausa!]) {
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: speech, sampleRate: sampleRate);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        if (text.isNotEmpty) onText(text);
      } finally {
        stream.free();
      }
    }
  }

  /// Ends any utterance in progress, as at the end of a recording or when a
  /// session stops.
  void flush() {
    if (_freed) return;
    if (_pending.isNotEmpty) {
      final last = Float32List(_window)..setAll(0, _pending);
      _pending = Float32List(0);
      _remember(last);
      _vad.acceptWaveform(last);
    }
    _vad.flush();
    _drain();
  }

  /// Drops anything heard but not yet transcribed, without reporting it: a
  /// pause is a promise not to be listening.
  void discard() {
    if (_freed) return;
    _pending = Float32List(0);
    _vad.reset();
    _fed = 0; // The detector numbers its samples from zero again.
  }

  /// Releases the native models. The object cannot be used afterwards.
  void free() {
    if (_freed) return;
    _freed = true;
    _recognizer.free();
    _hausa?.free();
    _vad.free();
  }
}

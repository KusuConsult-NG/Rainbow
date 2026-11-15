/// The microphone side of Guardian.
///
/// Behind an interface so the session logic is tested without a microphone.
///
/// PHASE 2: ON THE PHONE, AND IN THE BACKGROUND. Phase 1 used the phone's own
/// speech recognizer, which on some Android phones sends audio to Google and
/// which cannot run while the app is in the background. This listens with the
/// microphone directly and transcribes on the phone with the bundled offline
/// model (see offline_transcriber.dart): no audio and no text leaves the
/// device, and listening continues with the app in the background or the
/// screen off, kept alive by [GuardianKeepAlive].
///
/// NEVER THE DEMO TEXT. `SpeechService` falls back to a simulated dictation
/// when the recognizer is missing, which would be a false SOS here. Nothing
/// in this file uses it; a failure is reported, never papered over.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rainbow_app/core/guardian/guardian_models.dart';
import 'package:rainbow_app/core/guardian/guardian_worker.dart';
import 'package:rainbow_app/core/guardian/offline_transcriber.dart';
import 'package:rainbow_app/services/speech_service.dart';
import 'package:record/record.dart';

abstract class GuardianEar {
  /// Whether this platform can run Guardian at all.
  bool get supported;

  /// Whether listening can go on with the app in the background. When false,
  /// the session pauses while the app is off screen.
  bool get listensInBackground;

  /// Asks for the microphone if needed. True when it may be used.
  Future<bool> ensureMicrophone();

  /// Starts listening. [onWords] gets every recognized utterance; [onEnded]
  /// is called once when listening ends for any reason other than [stop].
  /// [hausaModelDir], when given, also listens in Hausa with that downloaded
  /// model. Returns false when listening could not start.
  Future<bool> listen({
    required void Function(String words, bool isFinal) onWords,
    required void Function() onEnded,
    String? hausaModelDir,
  });

  /// Stops listening and forgets anything heard but not yet transcribed.
  Future<void> stop();

  /// Frees what listening holds (the speech models) once a session is over.
  Future<void> release();

  /// True while another feature (a voice report, the dispatcher chat) is
  /// using the microphone. Guardian steps aside until it is false.
  ValueListenable<bool> get otherFeatureBusy;
}

/// Listens with the microphone and transcribes on the phone.
class OfflineEar implements GuardianEar {
  final AudioRecorder _recorder = AudioRecorder();
  GuardianWorker? _worker;
  StreamSubscription<Uint8List>? _mic;
  void Function()? _onEnded;
  int? _carry; // A byte left over from an odd-length chunk.

  @override
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  bool get listensInBackground => supported;

  @override
  ValueListenable<bool> get otherFeatureBusy =>
      SpeechService.instance.inUseByFeature;

  @override
  Future<bool> ensureMicrophone() async {
    try {
      return (await Permission.microphone.request()).isGranted;
    } on Object catch (_) {
      return false;
    }
  }

  @override
  Future<bool> listen({
    required void Function(String words, bool isFinal) onWords,
    required void Function() onEnded,
    String? hausaModelDir,
  }) async {
    if (!supported) return false;
    await _stopMic();
    try {
      // A worker loaded for a different set of languages is replaced.
      if (_worker != null && _worker!.hausaDir != hausaModelDir) {
        _worker!.close();
        _worker = null;
      }
      final worker = _worker ??= await GuardianWorker.spawn(
        await GuardianModels.install(),
        hausaDir: hausaModelDir,
      );
      worker
        ..onText = ((text) => onWords(text, true))
        ..onFailed = ((e) {
          debugPrint('[GUARDIAN] recognizer failed: $e');
          _endOnce();
        });

      final audio = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: OfflineTranscriber.sampleRate,
          numChannels: 1,
          androidConfig: AndroidRecordConfig(
            // The source meant for speech recognition: tuned for voice, and
            // left alone by the phone's call-audio processing.
            audioSource: AndroidAudioSource.voiceRecognition,
            manageBluetooth: false,
          ),
          iosConfig: IosRecordConfig(
            // Music or a call in another app carries on; Guardian listens
            // alongside it.
            categoryOptions: [
              IosAudioCategoryOption.mixWithOthers,
              IosAudioCategoryOption.allowBluetooth,
            ],
          ),
        ),
      );
      _onEnded = onEnded;
      _carry = null;
      _mic = audio.listen(
        (bytes) => worker.accept(_toSamples(bytes)),
        onError: (Object e) {
          debugPrint('[GUARDIAN] microphone error: $e');
          _endOnce();
        },
        onDone: _endOnce,
        cancelOnError: true,
      );
      return true;
    } on Object catch (e) {
      debugPrint('[GUARDIAN] listen failed: $e');
      await _stopMic();
      return false;
    }
  }

  void _endOnce() {
    final end = _onEnded;
    _onEnded = null;
    unawaited(_stopMic());
    end?.call();
  }

  /// 16-bit little-endian PCM to floats in [-1, 1].
  Float32List _toSamples(Uint8List bytes) {
    var data = bytes;
    if (_carry != null) {
      data = Uint8List(bytes.length + 1)
        ..[0] = _carry!
        ..setAll(1, bytes);
      _carry = null;
    }
    if (data.length.isOdd) {
      _carry = data.last;
      data = Uint8List.sublistView(data, 0, data.length - 1);
    }
    final view = ByteData.sublistView(data);
    final out = Float32List(data.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }

  Future<void> _stopMic() async {
    final mic = _mic;
    _mic = null;
    await mic?.cancel();
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } on Object catch (_) {}
  }

  @override
  Future<void> stop() async {
    _onEnded = null; // A stop is not an ending to report.
    await _stopMic();
    _worker?.discard();
  }

  @override
  Future<void> release() async {
    await stop();
    _worker?.close();
    _worker = null;
  }
}

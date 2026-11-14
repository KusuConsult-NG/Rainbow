/// The microphone side of Guardian: one listening pass at a time on the
/// phone's own speech recognizer.
///
/// Behind an interface so the session logic is tested without a microphone.
///
/// NEVER THE DEMO TEXT. `SpeechService` falls back to a simulated dictation
/// ("Help! Urgent response team needed…") when the recognizer is missing,
/// which is harmless in a voice report and would be a false SOS here. This
/// talks to the plugin directly and reports "unavailable" instead.
///
/// WHERE THE AUDIO GOES. Every pass asks for on-device recognition. On iPhone
/// that is enforced: a phone that cannot recognize offline refuses to listen.
/// On Android it is a preference the system may not honour on every phone;
/// guaranteeing it needs the on-device phrase-spotting model planned for
/// phase 2. The consent screen says so.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rainbow_app/services/speech_service.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract class GuardianEar {
  /// Whether this platform can run Guardian at all.
  bool get supported;

  /// Asks for the microphone if needed. True when it may be used.
  Future<bool> ensureMicrophone();

  /// Starts one listening pass. [onWords] gets every recognized update;
  /// [onEnded] is called once when the pass ends for any reason. Returns false
  /// when no pass could be started.
  Future<bool> listen({
    required void Function(String words, bool isFinal) onWords,
    required void Function() onEnded,
  });

  Future<void> stop();

  /// True while another feature (a voice report, the dispatcher chat) is
  /// using the recognizer. Guardian steps aside until it is false.
  ValueListenable<bool> get otherFeatureBusy;
}

class SpeechToTextEar implements GuardianEar {
  final SpeechToText _speech = SpeechToText();

  @override
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
  }) async {
    if (!supported) return false;
    var ended = false;
    void endOnce() {
      if (ended) return;
      ended = true;
      onEnded();
    }

    try {
      final ok = await _speech.initialize();
      if (!ok) return false;
      // The plugin keeps one set of listeners; claim them for this pass.
      _speech.statusListener = (status) {
        if (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus) {
          endOnce();
        }
      };
      _speech.errorListener = (_) => endOnce();
      await _speech.listen(
        onResult: (r) => onWords(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          onDevice: true,
          cancelOnError: true,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 6),
        ),
      );
      return true;
    } on Object catch (e) {
      debugPrint('[GUARDIAN] listen failed: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _speech.stop();
    } on Object catch (_) {}
  }
}

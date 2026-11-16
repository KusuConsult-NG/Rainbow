/// Runs Guardian's offline recognizer in its own isolate, so transcribing an
/// utterance never stalls the screen.
///
/// The main isolate sends microphone samples in; the worker sends text back.
/// Nothing the worker hears is kept: samples are discarded as soon as the
/// detector and recognizer have used them.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:rainbow_app/core/guardian/offline_transcriber.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class GuardianWorker {
  GuardianWorker._(this._isolate, this._toWorker, this._fromWorker);

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;

  /// Each finished utterance's text.
  void Function(String text)? onText;

  /// The worker stopped by itself (its models failed to load or it crashed).
  void Function(Object error)? onFailed;

  /// Hausa listening stopped (its model would not load, or failed later);
  /// English goes on. Set as soon as it happens, even before a listener is.
  String? hausaLost;

  /// Called when [hausaLost] is set.
  void Function(String reason)? onHausaLost;

  bool _closed = false;

  /// The Hausa model folder this worker loaded, if any.
  String? hausaDir;

  /// Starts a worker with the models in [modelDir], and the downloaded Hausa
  /// model in [hausaDir] if given. Fails if they cannot be loaded, so a broken
  /// install is reported instead of listening to nothing.
  static Future<GuardianWorker> spawn(String modelDir, {String? hausaDir}) async {
    final fromWorker = ReceivePort();
    final isolate = await Isolate.spawn(
      _main,
      [fromWorker.sendPort, modelDir, hausaDir],
      debugName: 'guardian-worker',
      errorsAreFatal: true,
    );
    final ready = Completer<SendPort>();
    late final GuardianWorker worker;
    String? lostBeforeReady;
    fromWorker.listen((Object? m) {
      if (m is List && m.length == 2 && m.first == 'hausa_lost') {
        final reason = '${m[1]}';
        if (ready.isCompleted) {
          worker
            ..hausaLost = reason
            ..onHausaLost?.call(reason);
        } else {
          lostBeforeReady = reason; // a load failure, reported during start-up
        }
      } else if (m is SendPort) {
        ready.complete(m);
      } else if (m is String) {
        worker.onText?.call(m);
      } else if (m is List && m.isNotEmpty && m.first == 'error') {
        final error = m.length > 1 ? m[1] as Object : 'unknown';
        if (!ready.isCompleted) {
          ready.completeError(StateError('Guardian models did not load: $error'));
        } else {
          worker.onFailed?.call(error);
        }
      }
    });
    try {
      final port = await ready.future.timeout(const Duration(seconds: 30));
      return worker = GuardianWorker._(isolate, port, fromWorker)
        ..hausaDir = hausaDir
        ..hausaLost = lostBeforeReady;
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      fromWorker.close();
      rethrow;
    }
  }

  /// Feeds 16 kHz mono samples in [-1, 1].
  void accept(Float32List samples) {
    if (_closed) return;
    _toWorker.send(TransferableTypedData.fromList([samples]));
  }

  /// Drops anything heard and not yet transcribed.
  void discard() {
    if (!_closed) _toWorker.send('discard');
  }

  /// Frees the models and ends the isolate.
  void close() {
    if (_closed) return;
    _closed = true;
    _toWorker.send('close');
    _fromWorker.close();
    // If it does not exit by itself, it is stopped.
    Timer(const Duration(seconds: 2), () => _isolate.kill(priority: Isolate.immediate));
  }

  static void _main(List<Object?> args) {
    final toMain = args[0]! as SendPort;
    final modelDir = args[1]! as String;
    final hausaDir = args[2] as String?;
    final inbox = ReceivePort();
    OfflineTranscriber? t;
    try {
      sherpa.initBindings();
      t = OfflineTranscriber(
        GuardianModelFiles.inDirectory(modelDir),
        hausaDir: hausaDir,
        onText: toMain.send,
        onHausaLost: (reason) => toMain.send(['hausa_lost', reason]),
      );
    } on Object catch (e) {
      toMain.send(['error', '$e']);
      inbox.close();
      return;
    }
    toMain.send(inbox.sendPort);
    inbox.listen((Object? m) {
      try {
        if (m is TransferableTypedData) {
          t!.accept(m.materialize().asFloat32List());
        } else if (m == 'discard') {
          t!.discard();
        } else if (m == 'close') {
          t!.free();
          inbox.close();
        }
      } on Object catch (e) {
        debugPrint('[GUARDIAN] worker: $e');
        toMain.send(['error', '$e']);
      }
    });
  }
}

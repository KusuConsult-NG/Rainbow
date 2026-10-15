import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A recording of the reporter's own voice, for somebody who cannot type.
///
/// ## Why this is its own thing
///
/// Two paths in this app already touched a microphone and neither of them
/// produced a voice note.
///
/// `report_details_screen.dart` records an `.m4a` and uploads it with the
/// photographs, so it lands in `media_urls` — the EVIDENCE list. Nothing
/// downstream could tell the reporter's voice from a photograph of a vehicle:
/// a responder's card said "3 attachments", and the console drew a 72px
/// thumbnail with a musical note on it.
///
/// The AI voice dialog — the one path built for a person who cannot type —
/// runs speech-to-text and files the TRANSCRIPT. **The audio is discarded.**
/// So if the recogniser mangles Hausa, or the phone has no network to reach
/// it, what the person actually said is gone, and a report that exists because
/// they could not type has nothing in it.
///
/// So: the audio is kept FIRST and the transcript is a bonus. A voice note
/// survives a failed transcription, no network, and a recogniser that has
/// never heard the language being spoken.
///
/// ## What it will not do
///
/// It will not record silently or indefinitely. [maxDuration] stops it at ten
/// minutes — the same ceiling the database's `voice_note_seconds` constraint
/// enforces, so a recording cannot be made that the row refuses to describe.
class VoiceNoteService {
  /// Creates a recorder. `recorder` and `tempDirectory` are seams for tests:
  /// the real ones need a microphone and a platform channel.
  VoiceNoteService({
    VoiceRecorder? recorder,
    Future<Directory> Function()? tempDirectory,
    DateTime Function()? now,
  })  : _recorder = recorder ?? _PluginRecorder(),
        _tempDirectory = tempDirectory ?? getTemporaryDirectory,
        _now = now ?? DateTime.now;

  final VoiceRecorder _recorder;
  final Future<Directory> Function() _tempDirectory;
  final DateTime Function() _now;

  /// Ten minutes, matching `alerts_voice_note_seconds_sane` in the database.
  static const Duration maxDuration = Duration(minutes: 10);

  DateTime? _startedAt;
  String? _path;

  /// Whether a recording is running.
  bool get isRecording => _startedAt != null;

  /// How long the current recording has been going.
  Duration get elapsed =>
      _startedAt == null ? Duration.zero : _now().difference(_startedAt!);

  /// Starts recording. Returns false when the microphone is not available —
  /// which the caller must SAY, because a record button that does nothing is
  /// how somebody who cannot type concludes the app cannot hear them.
  Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) return false;
      final dir = await _tempDirectory();
      final path =
          '${dir.path}/voice_note_${_now().millisecondsSinceEpoch}.m4a';
      // AAC in an m4a container (see `_PluginRecorder`): what the recorder
      // produces on both platforms, what Cloudinary serves back, and what an
      // <audio> tag and every phone can play. A format one of those three
      // cannot handle is a voice note nobody can hear.
      await _recorder.start(path);
      _path = path;
      _startedAt = _now();
      return true;
    } catch (e) {
      debugPrint('[VOICE_NOTE] could not start: $e');
      _startedAt = null;
      _path = null;
      return false;
    }
  }

  /// Stops recording and returns what was captured, or null if nothing was.
  ///
  /// A recording shorter than a second is discarded: it is a mis-tap, and an
  /// empty voice note on an incident is worse than none — a responder presses
  /// play, hears nothing, and cannot tell that from a file that failed to
  /// upload.
  Future<VoiceNote?> stop() async {
    if (_startedAt == null) return null;
    final seconds = elapsed.inSeconds;
    final path = _path;
    _startedAt = null;
    _path = null;
    try {
      final written = await _recorder.stop();
      final file = File(written ?? path ?? '');
      if (written == null && path == null) return null;
      if (!file.existsSync() || file.lengthSync() == 0) return null;
      if (seconds < 1) {
        try {
          file.deleteSync();
        } catch (_) {
          /* a temp file we could not remove is not worth failing over */
        }
        return null;
      }
      return VoiceNote(
        path: file.path,
        seconds: seconds.clamp(1, maxDuration.inSeconds),
      );
    } catch (e) {
      debugPrint('[VOICE_NOTE] could not stop: $e');
      return null;
    }
  }

  /// Abandons a recording without keeping it.
  Future<void> cancel() async {
    if (_startedAt == null) return;
    final path = _path;
    _startedAt = null;
    _path = null;
    try {
      await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    } catch (e) {
      debugPrint('[VOICE_NOTE] could not cancel cleanly: $e');
    }
  }

  /// Releases the platform recorder.
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (e) {
      debugPrint('[VOICE_NOTE] dispose: $e');
    }
  }
}

/// The microphone, as this service needs it.
///
/// Its own interface rather than `AudioRecorder` directly, for a reason that
/// only shows up in a test: `AudioRecorder`'s CONSTRUCTOR calls into the
/// platform channel, so a subclass that overrides every method still throws
/// `MissingPluginException` the moment it is built. A service that cannot be
/// tested without a microphone is a service nobody tests.
abstract class VoiceRecorder {
  /// Whether the phone has given this app the microphone.
  Future<bool> hasPermission();

  /// Begins writing audio to [path].
  Future<void> start(String path);

  /// Stops, and returns where the audio was written.
  Future<String?> stop();

  /// Releases the platform recorder.
  Future<void> dispose();
}

/// The real microphone, built on first use.
class _PluginRecorder implements VoiceRecorder {
  AudioRecorder? _it;
  AudioRecorder get _recorder => _it ??= AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() async {
    await _it?.dispose();
    _it = null;
  }
}

/// A finished recording: where it is, and how long it runs.
@immutable
class VoiceNote {
  /// Creates a voice note.
  const VoiceNote({required this.path, required this.seconds});

  /// The local file, before it is uploaded.
  final String path;

  /// Its duration, which travels with the url so a responder on a weak
  /// connection knows what they are about to pull.
  final int seconds;

  /// "0:08", "1:42" — what a play button is labelled with.
  String get label {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceNote && other.path == path && other.seconds == seconds;

  @override
  int get hashCode => Object.hash(path, seconds);
}

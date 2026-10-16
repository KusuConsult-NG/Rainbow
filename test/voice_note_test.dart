// A voice note from somebody who cannot type.
//
// Two paths in this app touched a microphone and neither produced one.
// `report_details_screen.dart` uploaded the recording into `media_urls` — the
// EVIDENCE list — so a responder's card said "3 attachments" with no way to
// tell that one of them was a person speaking. And the AI voice dialog, the
// one path built for somebody who cannot type, filed the TRANSCRIPT and threw
// the audio away: a recogniser that is offline, or has never heard Hausa or
// Pidgin, left nothing at all behind.
//
// So the rule these tests pin is: the AUDIO is kept, and the transcript is a
// bonus.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/voice_note_service.dart';

/// A recorder that writes a real file, so the service's own checks — does it
/// exist, is it empty — run against something.
///
/// Implements the service's own `VoiceRecorder`, not `AudioRecorder`: that
/// class calls the platform channel in its CONSTRUCTOR, so a subclass of it
/// throws `MissingPluginException` as soon as it is built, however much of it
/// is overridden.
class FakeRecorder implements VoiceRecorder {
  FakeRecorder({this.permitted = true, this.bytes = 2048, this.failOnStart = false});

  final bool permitted;
  final int bytes;
  final bool failOnStart;

  String? startedAt;
  bool stopped = false;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<void> start(String path) async {
    if (failOnStart) throw Exception('no microphone on this device');
    startedAt = path;
    File(path).writeAsBytesSync(List<int>.filled(bytes, 7));
  }

  @override
  Future<String?> stop() async {
    stopped = true;
    return startedAt;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('voice_note_test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  // A clock the test moves on purpose. A list of timestamps consumed per call
  // was the first version and it was wrong in a way that passed for the wrong
  // reason: `start()` reads the clock TWICE — once for the filename and once
  // for the start time — so the second entry was spent before the recording
  // began, every duration came out as zero, and every note was discarded as a
  // mis-tap.
  late DateTime clock;

  VoiceNoteService make(FakeRecorder recorder) {
    clock = DateTime(2026, 10, 15, 9);
    return VoiceNoteService(
      recorder: recorder,
      tempDirectory: () async => temp,
      now: () => clock,
    );
  }

  group('recording', () {
    test('keeps the audio and how long it ran', () async {
      final recorder = FakeRecorder();
      final service = make(recorder);

      expect(await service.start(), isTrue);
      expect(service.isRecording, isTrue);

      clock = clock.add(const Duration(seconds: 8));
      final note = await service.stop();

      expect(note, isNotNull);
      expect(File(note!.path).existsSync(), isTrue,
          reason: 'the file a voice note names has to exist');
      expect(note.seconds, 8);
      expect(note.label, '0:08');
      expect(service.isRecording, isFalse);
    });

    test('says so when the microphone is refused, rather than doing nothing',
        () async {
      // A record button that silently does nothing is how somebody who cannot
      // type concludes the app cannot hear them.
      final service = make(FakeRecorder(permitted: false));

      expect(await service.start(), isFalse);
      expect(service.isRecording, isFalse);
      expect(await service.stop(), isNull);
    });

    test('survives a recorder that throws', () async {
      final service = make(FakeRecorder(failOnStart: true));

      expect(await service.start(), isFalse);
      expect(service.isRecording, isFalse);
    });

    test('discards a mis-tap rather than filing silence', () async {
      // An empty voice note on an incident is worse than none: a responder
      // presses play, hears nothing, and cannot tell that from a file that
      // failed to upload.
      final recorder = FakeRecorder();
      final service = make(recorder); // and no time passes at all

      await service.start();
      final note = await service.stop();

      expect(note, isNull);
      expect(File(recorder.startedAt!).existsSync(), isFalse,
          reason: 'the discarded file should not be left behind');
    });

    test('discards a recording with no bytes in it', () async {
      final recorder = FakeRecorder(bytes: 0);
      final service = make(recorder);

      await service.start();
      clock = clock.add(const Duration(seconds: 8));

      expect(await service.stop(), isNull);
    });

    test('stopping without starting is not an error', () async {
      final service = make(FakeRecorder());
      expect(await service.stop(), isNull);
    });

    test('cancel removes the file and keeps nothing', () async {
      final recorder = FakeRecorder();
      final service = make(recorder);

      await service.start();
      final path = recorder.startedAt!;
      await service.cancel();

      expect(service.isRecording, isFalse);
      expect(File(path).existsSync(), isFalse);
      expect(await service.stop(), isNull);
    });

    test('a long recording is capped at the duration the database allows',
        () async {
      // `alerts_voice_note_seconds_sane` refuses anything over ten minutes, so
      // a recording longer than that would be a row the database rejects — the
      // report would fail over an audio length.
      final service = make(FakeRecorder());

      await service.start();
      clock = clock.add(const Duration(hours: 2));
      final note = await service.stop();

      expect(note!.seconds, VoiceNoteService.maxDuration.inSeconds);
    });

    test('dispose releases the platform recorder', () async {
      final recorder = FakeRecorder();
      final service = make(recorder);
      await service.dispose();
      expect(recorder.disposed, isTrue);
    });
  });

  group('VoiceNote', () {
    test('labels minutes and seconds the way a play button reads', () {
      expect(const VoiceNote(path: 'a', seconds: 8).label, '0:08');
      expect(const VoiceNote(path: 'a', seconds: 60).label, '1:00');
      expect(const VoiceNote(path: 'a', seconds: 102).label, '1:42');
      expect(const VoiceNote(path: 'a', seconds: 600).label, '10:00');
    });

    test('two notes of the same file and length are the same note', () {
      expect(const VoiceNote(path: 'a', seconds: 8),
          const VoiceNote(path: 'a', seconds: 8));
      expect(const VoiceNote(path: 'a', seconds: 8),
          isNot(const VoiceNote(path: 'a', seconds: 9)));
    });
  });
}

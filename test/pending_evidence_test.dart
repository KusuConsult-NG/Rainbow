// Evidence photographed before the SOS had somewhere to go.
//
// The duress screen told the person "SOS not yet confirmed — evidence saved
// locally" and then dropped the file path on the floor. Nothing recorded it,
// nothing retried, and the photograph was gone. A false reassurance during a
// duress event is worse than an error, because the person stops trying.
//
// These tests pin the three decisions that decide whether the evidence
// survives: it is held, it is only dropped once CONFIRMED, and a flush cannot
// run twice at once.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/emergency/pending_evidence.dart';

void main() {
  group('holding', () {
    test('keeps what was taken, oldest first', () {
      final q = PendingEvidence()
        ..hold('/tmp/one.jpg')
        ..hold('/tmp/two.jpg');
      expect(q.count, 2);
      expect(q.paths, ['/tmp/one.jpg', '/tmp/two.jpg']);
    });

    test('ignores a repeat of the same file', () {
      // A double tap on the shutter under stress is the normal case, not the
      // exception.
      final q = PendingEvidence()
        ..hold('/tmp/one.jpg')
        ..hold('/tmp/one.jpg')
        ..hold('  /tmp/one.jpg  ');
      expect(q.count, 1);
    });

    test('ignores a blank path', () {
      final q = PendingEvidence()..hold('')..hold('   ');
      expect(q.isEmpty, isTrue);
    });

    test('hands out a list a caller cannot mutate', () {
      // The screen reads `paths` to show a count while a flush is running.
      final q = PendingEvidence()..hold('/tmp/one.jpg');
      expect(() => q.paths.add('/tmp/sneaky.jpg'), throwsUnsupportedError);
    });
  });

  group('flushing', () {
    test('attaches everything held, in the order it was taken', () async {
      final q = PendingEvidence()
        ..hold('/tmp/one.jpg')
        ..hold('/tmp/two.jpg');
      final seen = <String>[];
      final res = await q.flush((p) async {
        seen.add(p);
        return true;
      });
      expect(seen, ['/tmp/one.jpg', '/tmp/two.jpg']);
      expect(res.delivered, ['/tmp/one.jpg', '/tmp/two.jpg']);
      expect(res.stillHeld, 0);
      expect(q.isEmpty, isTrue);
    });

    test('KEEPS a file whose attach did not succeed', () async {
      // The whole point. Dropping on attempt rather than on confirmation is how
      // a queue quietly empties itself and the evidence is gone.
      final q = PendingEvidence()..hold('/tmp/one.jpg');
      final res = await q.flush((_) async => false);
      expect(res.delivered, isEmpty);
      expect(res.stillHeld, 1);
      expect(q.paths, ['/tmp/one.jpg']);
    });

    test('keeps a file whose attach threw', () async {
      final q = PendingEvidence()..hold('/tmp/one.jpg');
      final res = await q.flush((_) async => throw Exception('socket hang up'));
      expect(res.delivered, isEmpty);
      expect(q.count, 1);
    });

    test('one failure does not abandon the rest', () async {
      final q = PendingEvidence()
        ..hold('/tmp/one.jpg')
        ..hold('/tmp/two.jpg')
        ..hold('/tmp/three.jpg');
      final res = await q.flush((p) async => p != '/tmp/two.jpg');
      expect(res.delivered, ['/tmp/one.jpg', '/tmp/three.jpg']);
      expect(q.paths, ['/tmp/two.jpg']);
    });

    test('retries what it kept on the next flush', () async {
      final q = PendingEvidence()..hold('/tmp/one.jpg');
      await q.flush((_) async => false);
      expect(q.count, 1);
      final res = await q.flush((_) async => true);
      expect(res.delivered, ['/tmp/one.jpg']);
      expect(q.isEmpty, isTrue);
    });

    test('an empty queue flushes to nothing without calling attach', () async {
      final q = PendingEvidence();
      var calls = 0;
      final res = await q.flush((_) async {
        calls += 1;
        return true;
      });
      expect(calls, 0);
      expect(res.anythingDelivered, isFalse);
    });
  });

  group('single-flight', () {
    test('a second flush while one is running uploads nothing again', () async {
      // The flush is triggered by a provider listener and that screen's timer
      // ticks every second. Without the guard a dispatcher would see the same
      // frame several times in one dossier.
      final q = PendingEvidence()..hold('/tmp/one.jpg');
      var attempts = 0;
      final gate = Completer<void>();

      final first = q.flush((_) async {
        attempts += 1;
        await gate.future;
        return true;
      });
      final second = await q.flush((_) async {
        attempts += 1;
        return true;
      });

      expect(second.delivered, isEmpty, reason: 'the second flush did work');
      expect(second.stillHeld, 1);
      gate.complete();
      await first;
      expect(attempts, 1);
      expect(q.isEmpty, isTrue);
    });

    test('the guard is released even when a flush throws out of attach',
        () async {
      // A stuck `_flushing` flag would mean nothing is ever sent again, which
      // is the same lost evidence by another route.
      final q = PendingEvidence()..hold('/tmp/one.jpg');
      await q.flush((_) async => throw Exception('boom'));
      final res = await q.flush((_) async => true);
      expect(res.delivered, ['/tmp/one.jpg']);
    });

    test('a photograph taken DURING a flush is picked up by the next one',
        () async {
      final q = PendingEvidence()..hold('/tmp/one.jpg');
      final gate = Completer<void>();
      final first = q.flush((_) async {
        q.hold('/tmp/late.jpg');
        await gate.future;
        return true;
      });
      gate.complete();
      final res1 = await first;
      expect(res1.delivered, ['/tmp/one.jpg']);
      // Not lost, just not in that pass.
      expect(q.paths, ['/tmp/late.jpg']);
      final res2 = await q.flush((_) async => true);
      expect(res2.delivered, ['/tmp/late.jpg']);
    });
  });

  group('what the person is told', () {
    test('does not claim the photo was saved when it is only held', () {
      // The original words were "SOS not yet confirmed — evidence saved
      // locally", and nothing was saved anywhere.
      final msg = heldEvidenceMessage(1);
      expect(msg, contains('held'));
      expect(msg, contains('will be sent'));
      expect(msg.toLowerCase(), isNot(contains('saved locally')));
    });

    test('counts them, so the person knows what is still waiting', () {
      expect(heldEvidenceMessage(3), contains('3 photos'));
      expect(heldEvidenceMessage(1), startsWith('Photo'));
      expect(heldEvidenceMessage(1), isNot(contains('1 photos')));
    });

    test('tells them to keep the app open, because that is what it needs', () {
      expect(heldEvidenceMessage(2).toLowerCase(), contains('keep the app open'));
    });

    test('says plainly when it has actually gone', () {
      expect(deliveredEvidenceMessage(1), contains('sent to HQ'));
      expect(deliveredEvidenceMessage(4), contains('4 held photos'));
    });
  });
}

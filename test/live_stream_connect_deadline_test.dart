// A stream that never connects must stop saying it is connecting.
//
// The note at the top of live_stream_service.dart says `connecting` "may be
// where this ends up: a stream that never connects stays `connecting` until
// ICE gives up". On a build with no TURN relay that is the ordinary outcome
// on mobile data, and ICE can sit there for minutes — or never give up.
//
// A citizen in Jos pressed BROADCAST LIVE and watched "CONNECTING TO HQ — NOT
// LIVE YET" for the length of the emergency. Honest, and useless: there is
// nothing in a spinner to act on. These tests pin the deadline that turns it
// into an answer, so the person can give up on it and contact the dispatcher.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/live_stream_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = LiveStreamService();

  setUp(() => LiveStreamService.deadline = const Duration(milliseconds: 40));
  tearDown(() {
    LiveStreamService.deadline = LiveStreamService.connectDeadline;
    service.debugSetStatus(LiveStreamStatus.idle);
  });

  test('connecting becomes failed once the deadline passes', () async {
    service.debugSetStatus(LiveStreamStatus.idle);
    final seen = <LiveStreamStatus>[];
    final sub = service.statusStream.listen(seen.add);
    addTearDown(sub.cancel);

    service.debugSetStatus(LiveStreamStatus.connecting);
    expect(service.status, LiveStreamStatus.connecting);

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(service.status, LiveStreamStatus.failed,
        reason: 'a person in an emergency cannot act on a spinner');
    expect(seen, contains(LiveStreamStatus.failed));
  });

  test('a connection that comes up in time is left alone', () async {
    service.debugSetStatus(LiveStreamStatus.idle);
    service.debugSetStatus(LiveStreamStatus.connecting);
    service.debugSetStatus(LiveStreamStatus.live);

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(service.status, LiveStreamStatus.live,
        reason: 'the deadline must not kill a stream HQ is receiving');
  });

  test('stopping cancels the deadline rather than reporting a failure later',
      () async {
    service.debugSetStatus(LiveStreamStatus.idle);
    service.debugSetStatus(LiveStreamStatus.connecting);
    service.debugSetStatus(LiveStreamStatus.idle);

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(service.status, LiveStreamStatus.idle,
        reason: 'nobody is waiting on a stream that was stopped');
  });

  // RTCPeerConnectionStateDisconnected is reported as `connecting`, because a
  // brief tunnel should not tell somebody their stream is dead. Each entry
  // gets a full window, not the remains of the previous one.
  test('a reconnect gets a fresh window, not the remains of the last one',
      () async {
    service.debugSetStatus(LiveStreamStatus.idle);
    service.debugSetStatus(LiveStreamStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    service.debugSetStatus(LiveStreamStatus.live);
    service.debugSetStatus(LiveStreamStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.status, LiveStreamStatus.connecting,
        reason: 'only 30ms into a fresh 40ms window');

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(service.status, LiveStreamStatus.failed);
  });

  test('the shipped deadline is thirty seconds', () {
    expect(LiveStreamService.connectDeadline, const Duration(seconds: 30));
  });
}

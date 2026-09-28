// The signalling key that could not be called `type`.
//
// `RealtimeChannel.send` in realtime_client 2.11.0 does this, at line 778:
//
//     payload['type'] = type.toType();
//
// It mutates the caller's map and overwrites any `type` key with the literal
// 'broadcast'. `LiveStreamService` used `type` as its own discriminator, so
// every signalling message it sent — the offer, every ICE candidate, the bye —
// reached HQ as `type: 'broadcast'`. The console matched on
// `payload?.type === 'offer'`, which could never be true, so it never answered
// and the negotiation never began.
//
// Meanwhile the phone HAD taken the camera and the microphone, and was telling
// the person "LIVE STREAM BROADCASTING TO HQ".
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/services/live_stream_service.dart';

void main() {
  group('reading which signalling message arrived', () {
    test('reads the kind from `signal`', () {
      expect(signalKind({'signal': 'offer', 'sdp': 'v=0'}), 'offer');
      expect(signalKind({'signal': 'answer'}), 'answer');
      expect(signalKind({'signal': 'candidate'}), 'candidate');
      expect(signalKind({'signal': 'bye'}), 'bye');
    });

    // The regression, stated as such. This is the exact shape that came off the
    // wire: the app's own `type` gone, replaced by the envelope's.
    test('never mistakes the envelope for the message', () {
      expect(
        signalKind({'type': 'broadcast', 'sdp': 'v=0', 'sender': 'mobile'}),
        isNull,
        reason: "'broadcast' is the SDK's word for the transport, not a kind of "
            'signalling message, and treating it as one is what made every '
            'branch on the receiving side fail to match.',
      );
    });

    test('`signal` wins even when the SDK has stamped `type`', () {
      // What a real send looks like after the SDK has mutated it.
      expect(
        signalKind({'signal': 'offer', 'type': 'broadcast', 'sdp': 'v=0'}),
        'offer',
      );
    });

    test('still understands a peer that has not been updated yet', () {
      expect(signalKind({'type': 'answer', 'sdp': 'v=0'}), 'answer');
      expect(signalKind({'type': 'candidate'}), 'candidate');
    });

    test('an empty or absent kind is null, not an empty string', () {
      expect(signalKind({}), isNull);
      expect(signalKind({'signal': ''}), isNull);
    });
  });
}

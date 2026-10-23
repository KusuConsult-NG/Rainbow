/// What a WebRTC connection needs to actually reach HQ, and why STUN is not it.
///
/// `live_stream_service.dart` lets somebody in an emergency show HQ what is
/// happening to them. Its ICE configuration was three of Google's public STUN
/// servers and nothing else, written into the service — and the console's
/// `LiveFeedViewer.tsx` had the same three literals written into it.
///
/// ## STUN is not a relay
///
/// STUN tells a peer what its own public address looks like from outside. That
/// is all it does. The media still has to travel directly between the two
/// peers, which requires UDP hole punching to work through both NATs.
///
/// A citizen's handset is on a Nigerian mobile network, behind carrier-grade
/// NAT. CGNAT is commonly SYMMETRIC: it allocates a different external port
/// per destination, so the address STUN reports is useless to a peer trying to
/// send to it. Hole punching fails. HQ, on an office network behind its own
/// firewall, is no better placed. When neither side can be reached directly
/// the connection needs a TURN server to relay the media, and WebRTC has no
/// other way to do it.
///
/// So with STUN alone the stream connects when the network happens to allow it
/// and silently does not when it does not — and "does not" is the ordinary case
/// for a phone on mobile data, which is every case this feature is for.
///
/// ## Why this file exists rather than a literal in each service
///
/// The same reason as `routing.dart` and `map_tiles.dart`: an endpoint written
/// into the code cannot be changed by whoever deploys it, and a build pointed
/// at somebody else's infrastructure should be a fact somebody can read rather
/// than something discovered in the field. It was also written TWICE here,
/// once per side, and a rule written twice drifts — this project has already
/// had that in the OneSignal auth scheme, where four copies disagreed.
///
/// No TURN server is invented here. There is no public one that works, and a
/// made-up credential would fail exactly like no credential while looking
/// configured. If `TURN_URL` is unset, `hasRelay` is false, the service logs it
/// once, and the screen does not promise the person anything it has not got.
/// See E2E_AUDIT_REPORT.md T-96.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Public STUN. Safe to default to: it needs no credential, it leaks nothing
/// but the handset's public address to Google, and without it there is no
/// candidate gathering at all.
const List<String> defaultStunUrls = <String>[
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
  'stun:stun2.l.google.com:19302',
];

String? _env(String key) {
  if (!dotenv.isInitialized) return null;
  final value = dotenv.env[key]?.trim();
  return (value == null || value.isEmpty) ? null : value;
}

/// The TURN relay, or null when this build has none.
String? get turnUrl {
  final url = _env('TURN_URL');
  if (url == null) return null;
  // A TURN URL that is not a turn: or turns: URI will be ignored by the peer
  // connection without complaint, which is the failure this whole file is
  // about: configured, and no different from unconfigured.
  if (!url.startsWith('turn:') && !url.startsWith('turns:')) {
    debugPrint(
      '[LIVE_STREAM] TURN_URL is "$url", which is not a turn: or turns: URI. '
      'Ignoring it — a malformed relay is indistinguishable from none, and '
      'this says which you have.',
    );
    return null;
  }
  return url;
}

/// Whether this build can relay media when neither peer is directly reachable.
///
/// False means the stream will connect on some networks and not on others,
/// with mobile data the likeliest to fail. The screen is told, so the person
/// is told.
bool get hasRelay => turnUrl != null;

/// The ICE servers to hand the peer connection.
List<Map<String, dynamic>> get iceServers {
  final servers = <Map<String, dynamic>>[
    for (final url in defaultStunUrls) <String, dynamic>{'urls': url},
  ];
  final relay = turnUrl;
  if (relay != null) {
    final username = _env('TURN_USERNAME');
    final credential = _env('TURN_CREDENTIAL');
    servers.add(<String, dynamic>{
      'urls': relay,
      if (username != null) 'username': username,
      if (credential != null) 'credential': credential,
    });
  }
  return servers;
}

/// Said once, at the point of use, rather than relying on anybody reading this
/// file. Mirrors how `routing.dart` reports a demonstration server.
void warnIfNoRelay() {
  if (hasRelay) return;
  debugPrint(
    '[LIVE_STREAM] No TURN relay configured (TURN_URL unset). STUN alone '
    'cannot get media through carrier-grade NAT, which is what a handset on '
    'mobile data is behind, so this connection will fail on many real '
    'networks. The screen now says CONNECTING until it is actually connected '
    'rather than claiming it is live.',
  );
}

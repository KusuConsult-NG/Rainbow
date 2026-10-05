/// Carrying what a phone holds out to HQ, once that phone has a network.
///
/// The exit point of the mesh is not the reporter's phone. It is whichever phone
/// reaches a network first — often a stranger's — and that phone POSTs every
/// envelope it is holding to `/api/mesh/ingest`. These two functions are the
/// whole of the wire format for that request, kept pure so that the shape HQ
/// expects is tested here rather than discovered against a live server.
///
/// The request needs no session and carries nothing about this phone: the
/// endpoint accepts opaque frames from anybody, because during a shutdown the
/// first phone back online may be signed out or holding an expired token. See
/// `hq-dashboard-next/src/app/api/mesh/ingest/route.ts`.
library;

import 'dart:convert';

import 'package:rainbow_app/core/mesh/mesh_envelope.dart';

/// The most frames one request may carry. The endpoint ignores any beyond this.
const int meshIngestMaxFrames = 32;

/// The JSON body for one `/api/mesh/ingest` request.
///
/// Frames go as unpadded base64url — the alphabet the endpoint decodes.
String meshIngestBody(Iterable<MeshEnvelope> envelopes) => jsonEncode({
      'frames': [
        for (final envelope in envelopes.take(meshIngestMaxFrames)) envelope.toBase64(),
      ],
    });

final _envelopeIdHex = RegExp(r'^[0-9a-f]{32}$');

/// The envelope ids HQ says it is finished with, as [MeshEnvelope.idHex].
///
/// HQ answers with the same list whatever it thought of each frame — accepted,
/// already seen, or junk — so a relay cannot learn which frames were real
/// emergencies. The caller stops carrying exactly these.
///
/// Anything unreadable is an empty set, never an exception: the safe failure for
/// a relay is to keep carrying, and try again later.
Set<String> meshIngestDone(String responseBody) {
  final Object? decoded;
  try {
    decoded = jsonDecode(responseBody);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map) return const {};
  final done = decoded['done'];
  if (done is! List) return const {};
  return {
    for (final id in done)
      if (id is String && _envelopeIdHex.hasMatch(id)) id,
  };
}

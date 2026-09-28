/// What a relaying phone is allowed to know.
///
/// A mesh moves a report through handsets that do not belong to the reporter.
/// In a communal-violence context the phone that relays an alert may belong to
/// somebody on the other side of the conflict, and an alert carries the
/// reporter's identity, their position, what is happening to them, and
/// sometimes a duress flag. If a relay can read what it carries, the mesh
/// becomes an efficient way to find out who is reporting and where they are
/// standing — worse than having no mesh.
///
/// So the requirement is not "encrypt the mesh". It is:
///
/// > A relay must forward an alert it CANNOT READ, and must learn nothing
/// > useful from having carried it.
///
/// That decides the shape of this file. The envelope carries the minimum a
/// relay needs in order to relay, and nothing else:
///
/// | field       | why a relay needs it                                |
/// |-------------|-----------------------------------------------------|
/// | `id`        | 128 random bits. Deduplication. Carries no meaning.  |
/// | `ttl`       | Hops remaining. Decremented; dropped at zero.        |
/// | `createdAt` | Coarse expiry, so nothing circulates for ever.       |
/// | `keyId`     | Which HQ key sealed it, so keys can be rotated.      |
/// | sealed body | Opaque.                                              |
///
/// In particular it does NOT carry the reporter, the location, the type, the
/// severity, or the duress flag. Not even coarsely. "There is a DURESS alert
/// somewhere near here" is itself actionable intelligence for the person the
/// alert is about.
///
/// ## Why not the per-device key the SMS channel uses
///
/// The SMS fallback seals with a per-device symmetric key and sends the device
/// reference in the clear. That is fine there: the carrier already knows which
/// handset sent the message. It would be wrong here. A stable identifier on
/// the wire would let a hostile relay fingerprint which handsets in a crowd
/// are reporting, and follow them, which is the attack this design exists to
/// prevent.
///
/// So the mesh seals to an HQ PUBLIC key with a fresh ephemeral keypair per
/// message. There is no stable sender identifier anywhere in the envelope, and
/// compromising a relay — or the reporter's own handset later — does not open
/// messages it carried.
///
/// ## What this deliberately does not do
///
/// It does not authenticate the sender, so the mesh can be filled with
/// rubbish. A signature would fix that and would identify the sender to every
/// relay, which is the thing being prevented. The mitigations are blunt and
/// live in `MeshRelay`: a hard size cap, a low TTL, deduplication, and a
/// bounded outbox. **We accept flood risk to keep reporters unidentifiable.**
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// How many bytes of random identity an envelope carries.
const int meshIdLength = 16;

/// The hop limit a freshly sealed envelope starts with.
///
/// Eight is enough to cross a crowd by short hops and low enough that garbage
/// dies quickly. It is a ceiling on amplification as much as a routing
/// parameter: each envelope can be forwarded at most this many times per path.
const int meshDefaultTtl = 8;

/// The longest an envelope may circulate, whatever its hop count says.
///
/// Hop count is the primary control because it needs no agreed clock. This is
/// a backstop for an envelope that keeps finding fresh relays, and it is
/// generous because phone clocks disagree and an emergency is not less real
/// for being twenty hours old.
const Duration meshMaxAge = Duration(hours: 24);

/// The largest envelope a relay will carry.
///
/// Small on purpose. A sealed alert is tens of bytes; anything much larger is
/// somebody using the mesh as a transport for something it is not for, and it
/// would crowd out real alerts on a link that carries a few hundred bytes at a
/// time.
const int meshMaxEnvelopeBytes = 512;

/// One relayable message.
@immutable
class MeshEnvelope {
  /// Creates an envelope.
  const MeshEnvelope({
    required this.id,
    required this.ttl,
    required this.createdAt,
    required this.keyId,
    required this.sealed,
  });

  /// 16 random bytes. The only identity this message has.
  final Uint8List id;

  /// Hops remaining.
  final int ttl;

  /// When the ORIGINATING phone sealed it, by that phone's clock.
  final DateTime createdAt;

  /// Which HQ key it is sealed to.
  final int keyId;

  /// The ephemeral public key, nonce, ciphertext and tag, as produced by
  /// `MeshSealer`. Opaque to everything that is not HQ.
  final Uint8List sealed;

  /// `id`, rendered for logs and for use as a map key.
  String get idHex =>
      id.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// A copy with one hop spent, or null when there are none left.
  MeshEnvelope? forwarded() {
    if (ttl <= 1) return null;
    return MeshEnvelope(
      id: id,
      ttl: ttl - 1,
      createdAt: createdAt,
      keyId: keyId,
      sealed: sealed,
    );
  }

  /// The wire form: a compact binary frame.
  ///
  /// ```
  ///   0   1  version
  ///   1  16  id
  ///  17   1  ttl
  ///  18   8  createdAt, unix milliseconds, big-endian
  ///  26   1  keyId
  ///  27   2  sealed length
  ///  29   n  sealed
  /// ```
  Uint8List encode() {
    final out = Uint8List(29 + sealed.length);
    final view = ByteData.sublistView(out);
    out[0] = 1;
    out.setRange(1, 1 + meshIdLength, id);
    out[17] = ttl;
    view.setUint64(18, createdAt.toUtc().millisecondsSinceEpoch);
    out[26] = keyId;
    view.setUint16(27, sealed.length);
    out.setRange(29, 29 + sealed.length, sealed);
    return out;
  }

  /// Reads a frame, or null if it is not one.
  ///
  /// Returns null rather than throwing for every malformation. This parses
  /// bytes handed over by a stranger's phone; it must not be possible to crash
  /// a relay by sending it something odd.
  static MeshEnvelope? decode(Uint8List bytes) {
    if (bytes.length < 29 || bytes.length > meshMaxEnvelopeBytes) return null;
    if (bytes[0] != 1) return null;
    final view = ByteData.sublistView(bytes);
    final sealedLength = view.getUint16(27);
    if (sealedLength == 0 || 29 + sealedLength != bytes.length) return null;
    final ttl = bytes[17];
    if (ttl == 0 || ttl > meshDefaultTtl) return null;
    final millis = view.getUint64(18);
    // A timestamp outside anything plausible is a malformed or hostile frame.
    if (millis <= 0 || millis > 4102444800000) return null; // year 2100
    return MeshEnvelope(
      id: Uint8List.fromList(bytes.sublist(1, 1 + meshIdLength)),
      ttl: ttl,
      createdAt: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      keyId: bytes[26],
      sealed: Uint8List.fromList(bytes.sublist(29)),
    );
  }

  /// Base64url, for transports that want text.
  String toBase64() => base64Url.encode(encode()).replaceAll('=', '');

  /// Reads a base64url frame, or null.
  static MeshEnvelope? fromBase64(String value) {
    try {
      final padded =
          value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
      return decode(Uint8List.fromList(base64Url.decode(padded)));
    } catch (_) {
      return null;
    }
  }

  /// A fresh random id.
  static Uint8List newId([Random? random]) {
    final rng = random ?? Random.secure();
    return Uint8List.fromList(
        List<int>.generate(meshIdLength, (_) => rng.nextInt(256)));
  }
}

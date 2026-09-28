/// What goes INSIDE the seal, and why it is the SMS message body.
///
/// ## The problem the mesh has and the SMS channel does not
///
/// A mesh envelope is sealed to HQ's public key. Anybody can do that — the
/// public key ships in the app — so sealing proves nothing about who sealed it.
/// That is deliberate: a signature would identify the reporter to every relay,
/// which is the attack the whole design exists to prevent.
///
/// But it leaves HQ with a problem the SMS channel does not have. An SMS is
/// authenticated by the per-device AES-GCM tag, so a message that decrypts is
/// a message that device really sent. A mesh payload sealed to a public key
/// carries no such proof, so if the payload simply said "reporter =
/// <some uuid>", anyone could manufacture an emergency attributed to anyone.
/// On an emergency system that is not a theoretical concern: the `smsWebhook`
/// this project is retiring could be used exactly that way.
///
/// ## So the mesh plaintext IS the SMS body
///
/// The 75-character `OR1…` string, unchanged, sealed inside the envelope.
///
/// ```
///   MeshEnvelope { id, ttl, createdAt, keyId,
///                  sealed = ECIES-to-HQ( "OR1AaGyw9QAAQ…" ) }
///                                         └── AES-GCM under the DEVICE key
/// ```
///
/// Two layers, each doing the thing it is good at:
///
/// * the **outer** seal makes the envelope unreadable to relays, with no
///   stable sender identifier anywhere on the wire;
/// * the **inner** device-key tag proves to HQ which handset raised the alert,
///   and is invisible to every relay that carried it.
///
/// What that buys, in order of how much it matters:
///
/// 1. **A mesh alert cannot be forged.** HQ verifies it exactly as it verifies
///    an SMS — same key, same tag, same code path.
/// 2. **One wire format, not two.** `sms_alert_payload.dart` and
///    `sms-alert-codec.ts` already agree on real bytes, checked against vectors
///    the Dart encoder produced. A second payload format would need a second
///    pair of implementations and a second reason for them to drift.
/// 3. **The two channels deduplicate against each other for free**, because
///    both carry the same `local_id` reference.
///
/// ## The cost, stated
///
/// Base64 inside a binary envelope wastes about 21 bytes — the SMS form is
/// base64 because GSM-7 demanded it, and the mesh has no such constraint. A
/// full envelope is around 150 bytes against the 512-byte cap, so the waste
/// buys the properties above and costs nothing that matters. If the mesh ever
/// needs to carry something SMS cannot express — a photograph reference, a
/// description in text — that is a new payload version, and `keyId` and the
/// version byte in the seal are both already there for it.
///
/// A second cost, and this one is real: a handset with no device key cannot
/// use the mesh either. Provisioning happens once, while the phone is online
/// (`SmsDeviceKeyService.ensureProvisioned`), which is the same moment the SMS
/// fallback needs. A phone that has never been online has no offline channel
/// at all, and no design here changes that.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:rainbow_app/core/mesh/mesh_envelope.dart';
import 'package:rainbow_app/core/mesh/mesh_sealer.dart';

/// Wraps an SMS-format alert body in a mesh envelope sealed to HQ.
///
/// [smsBody] is exactly what the SMS channel would send — `encodeSmsAlert`'s
/// output, prefix and all. [hqPublicKey] is HQ's compressed P-256 point.
/// [keyId] says which HQ key, so keys can be rotated without a release.
///
/// [now] and [random] are injectable so tests and the vector generator are
/// deterministic; production passes neither.
MeshEnvelope meshEnvelopeForSmsBody({
  required String smsBody,
  required Uint8List hqPublicKey,
  int keyId = 1,
  int ttl = meshDefaultTtl,
  DateTime? now,
  SecureRandom? random,
  Random? idRandom,
}) {
  if (smsBody.isEmpty) {
    throw ArgumentError.value(smsBody, 'smsBody', 'must not be empty');
  }
  final sealed = meshSeal(
    plaintext: Uint8List.fromList(ascii.encode(smsBody)),
    hqPublicKey: hqPublicKey,
    random: random,
  );
  final envelope = MeshEnvelope(
    id: MeshEnvelope.newId(idRandom),
    ttl: ttl,
    createdAt: (now ?? DateTime.now()).toUtc(),
    keyId: keyId,
    sealed: sealed,
  );
  // Refuse to emit something a relay would drop on sight. This is a programming
  // error, not a runtime condition: the size is decided by the payload format,
  // so if it ever trips it trips in the vector generator and in CI, not in the
  // field on the one night it matters.
  final frame = envelope.encode().length;
  if (frame > meshMaxEnvelopeBytes) {
    throw StateError(
      'a sealed alert came to $frame bytes, over the '
      '$meshMaxEnvelopeBytes-byte limit every relay enforces',
    );
  }
  return envelope;
}

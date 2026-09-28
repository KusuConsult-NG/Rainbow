/// An alert compressed, encrypted and authenticated to fit in ONE text message.
///
/// ## Why this is not plaintext
///
/// The obvious SMS fallback sends something like
/// `SOS KIDNAP 9.89654,8.85831 DURESS`, and the first design of this channel
/// assumed that was the only option — that the 160-character limit forced a
/// choice between carrying the duress flag and keeping it private, because
/// encrypting and base64-ing a payload would not fit.
///
/// That was wrong, and the arithmetic is worth writing down so nobody repeats
/// it:
///
///     version      1            flags/type/severity      3
///     device ref   4            latitude                 4
///     nonce       12            longitude                4
///     GCM tag     16            timestamp                4
///                               local ref                6
///     ------------------------------------------------------
///     33 bytes of envelope  +  21 bytes of alert  =  54 bytes
///     base64url, unpadded                        =  72 characters
///     plus the "OR1" prefix                      =  75 characters
///
/// A GSM-7 segment holds 160. So the whole alert — encrypted and
/// authenticated — travels in a single message, at single-message cost, with
/// 85 characters to spare. There was never a trade to make.
///
/// ## What that buys
///
/// * **The duress flag travels, and is not legible.** SMS content is visible
///   to the carrier and to anyone who can see the handset's message log. In
///   the situations a duress PIN exists for, the realistic adversary is often
///   the person standing next to you, and a plaintext `DURESS` in the sent
///   folder is the worst possible outcome.
/// * **HQ cannot be spoofed.** The GCM tag authenticates the message against
///   the device's key, so a forged SMS claiming to be an emergency does not
///   decrypt. The old `smsWebhook` this replaces accepted anything.
/// * **One segment, so one cost.** A flood of alerts is a flood of cost, and
///   that is a real constraint on an emergency service's budget.
///
/// ## What it does not buy
///
/// The carrier still learns that this handset sent a short message to the
/// emergency shortcode at a particular time, and roughly where the handset
/// was. Traffic analysis is not defeated by encryption and this design does
/// not claim to defeat it. What is protected is the CONTENT: who, what, where
/// precisely, and whether it was a duress.
///
/// ## The key
///
/// A per-device symmetric key, established once while the phone is online and
/// held in `flutter_secure_storage`. Per-device rather than one shared app key
/// because a single key extracted from one APK would let anyone forge alerts
/// from anybody; and symmetric rather than public-key because it authenticates
/// as well as conceals, and because it is 32 bytes smaller on the wire, which
/// is what keeps this inside one segment.
///
/// The provisioning handshake is deliberately NOT in this file: it needs a
/// server endpoint, and this codec is written so it can be tested without one.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The fixed prefix, so an operator reading a message log can tell what it is,
/// and so a gateway can route it without decrypting.
const String smsAlertPrefix = 'OR1';

/// Version 1 of the wire format. Bumped if the plaintext layout changes.
const int smsAlertVersion = 1;

/// Nonce length for AES-GCM, per NIST SP 800-38D.
const int smsNonceLength = 12;

/// The authentication tag length in bytes.
const int smsTagLength = 16;

/// How many bytes of `alerts.local_id` travel, for deduplication against the
/// offline queue.
///
/// Six bytes is 48 bits. HQ deduplicates within a short window rather than for
/// all time, so the collision risk is negligible and the saving keeps the
/// message inside one segment.
const int smsLocalRefLength = 6;

/// An alert, in the smallest form that is still useful to a dispatcher.
class SmsAlertPayload {
  /// Creates a payload.
  const SmsAlertPayload({
    required this.categoryCode,
    required this.severityCode,
    required this.sentAt,
    required this.localRef,
    this.latitude,
    this.longitude,
    this.isDuress = false,
    this.isAnonymous = false,
  });

  /// Index into `alertCategories`, or 255 for an SOS with no category.
  final int categoryCode;

  /// 0 low, 1 medium, 2 high, 3 critical.
  final int severityCode;

  /// When the phone raised it — NOT when the SMS arrived. An SMS can sit in a
  /// queue for minutes, and a dispatcher needs to know the incident is old.
  final DateTime sentAt;

  /// The first [smsLocalRefLength] bytes of the alert's `local_id`, so HQ can
  /// recognise the same incident if the phone later syncs its offline queue.
  final Uint8List localRef;

  /// Degrees, or null when there was no fix.
  final double? latitude;

  /// Degrees, or null when there was no fix.
  final double? longitude;

  /// Whether this was raised under duress.
  ///
  /// Carried, on an explicit decision: a duress SOS that silently degrades to
  /// an ordinary one when it travels by SMS is a duress signal that does not
  /// work in the one case it exists for. It is safe to carry here because the
  /// payload is encrypted.
  final bool isDuress;

  /// Whether the reporter asked not to be identified.
  final bool isAnonymous;

  /// Whether a position travelled with this alert.
  bool get hasLocation => latitude != null && longitude != null;
}

/// Fixed-point scale for coordinates.
///
/// 1e5 gives about a metre at this latitude, which is finer than any phone's
/// fix, and keeps each coordinate inside a signed 32-bit integer for the whole
/// world.
const int _coordScale = 100000;

const int _flagDuress = 0x01;
const int _flagAnonymous = 0x02;
const int _flagHasLocation = 0x04;

/// Encrypts [payload] into the body of a single text message.
///
/// [key] is the 32-byte per-device key. [deviceRef] is HQ's 4-byte handle for
/// that key, sent in the clear so HQ knows which key to try. [nonce] must be
/// 12 bytes and must never repeat for a given key — pass a fresh random one;
/// it is a parameter only so the tests can be deterministic.
String encodeSmsAlert({
  required SmsAlertPayload payload,
  required Uint8List key,
  required Uint8List deviceRef,
  required Uint8List nonce,
}) {
  if (key.length != 32) {
    throw ArgumentError.value(key.length, 'key', 'must be 32 bytes');
  }
  if (deviceRef.length != 4) {
    throw ArgumentError.value(deviceRef.length, 'deviceRef', 'must be 4 bytes');
  }
  if (nonce.length != smsNonceLength) {
    throw ArgumentError.value(nonce.length, 'nonce', 'must be 12 bytes');
  }
  if (payload.localRef.length != smsLocalRefLength) {
    throw ArgumentError.value(
      payload.localRef.length, 'localRef', 'must be $smsLocalRefLength bytes');
  }

  final plain = ByteData(21);
  var flags = 0;
  if (payload.isDuress) flags |= _flagDuress;
  if (payload.isAnonymous) flags |= _flagAnonymous;
  if (payload.hasLocation) flags |= _flagHasLocation;
  plain.setUint8(0, flags);
  plain.setUint8(1, payload.categoryCode);
  plain.setUint8(2, payload.severityCode);
  plain.setInt32(3, payload.hasLocation
      ? (payload.latitude! * _coordScale).round()
      : 0);
  plain.setInt32(7, payload.hasLocation
      ? (payload.longitude! * _coordScale).round()
      : 0);
  // Seconds, not milliseconds: it halves the field and a dispatcher does not
  // need sub-second precision on something that arrived by SMS.
  plain.setUint32(11, payload.sentAt.toUtc().millisecondsSinceEpoch ~/ 1000);
  final out = plain.buffer.asUint8List();
  out.setRange(15, 21, payload.localRef);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), smsTagLength * 8, nonce, Uint8List(0)),
    );
  final sealed = cipher.process(out);

  final body = Uint8List(1 + 4 + smsNonceLength + sealed.length)
    ..[0] = smsAlertVersion
    ..setRange(1, 5, deviceRef)
    ..setRange(5, 5 + smsNonceLength, nonce)
    ..setRange(5 + smsNonceLength, 5 + smsNonceLength + sealed.length, sealed);

  // base64url without padding: every character is in the GSM-7 default
  // alphabet, so the message stays one segment instead of being promoted to
  // UCS-2 at 70 characters.
  return smsAlertPrefix + base64Url.encode(body).replaceAll('=', '');
}

/// A fresh nonce for [encodeSmsAlert], from the platform's CSPRNG.
///
/// Exists so that nothing has to decide how to make one. AES-GCM tolerates a
/// repeated nonce under the same key worse than almost any other primitive:
/// two messages sharing one leak the XOR of their plaintexts AND the
/// authentication subkey, which is enough to forge a third. A counter would also
/// be correct and is harder to get right across reinstalls and clock changes,
/// and 96 random bits per message is well inside the safe margin for the handful
/// of messages one handset will ever send.
///
/// This is not decoration: the mesh sealer shipped with a clock-seeded generator
/// for exactly this job, and `scripts/check_crypto_entropy.py` now fails the
/// build for it. [random] is injectable for tests only.
Uint8List newSmsNonce([Random? random]) {
  final rng = random ?? Random.secure();
  return Uint8List.fromList(
      List<int>.generate(smsNonceLength, (_) => rng.nextInt(256)));
}

/// The result of reading a message body.
class SmsAlertDecodeResult {
  /// Creates a result.
  const SmsAlertDecodeResult._(this.payload, this.deviceRef, this.failure);

  /// A message that decrypted and authenticated.
  factory SmsAlertDecodeResult.ok(SmsAlertPayload p, Uint8List ref) =>
      SmsAlertDecodeResult._(p, ref, null);

  /// A message that did not.
  factory SmsAlertDecodeResult.failed(String why) =>
      SmsAlertDecodeResult._(null, null, why);

  /// The alert, when it decoded.
  final SmsAlertPayload? payload;

  /// Which device key opened it.
  final Uint8List? deviceRef;

  /// Why it did not decode, or null.
  final String? failure;

  /// Whether the message decoded and authenticated.
  bool get ok => payload != null;
}

/// Reads the [body] of a text message back into an alert.
///
/// Returns a failure rather than throwing, and the failure NEVER says which
/// step failed in a way a caller could relay onward: a bad tag, a wrong key
/// and a truncated message must be indistinguishable to anything outside HQ,
/// or the endpoint becomes an oracle.
SmsAlertDecodeResult decodeSmsAlert({
  required String body,
  required Uint8List key,
}) {
  const generic = 'undecodable';
  if (!body.startsWith(smsAlertPrefix)) {
    return SmsAlertDecodeResult.failed(generic);
  }
  Uint8List raw;
  try {
    var b64 = body.substring(smsAlertPrefix.length).trim();
    b64 = b64.padRight(b64.length + ((4 - b64.length % 4) % 4), '=');
    raw = base64Url.decode(b64);
  } catch (_) {
    return SmsAlertDecodeResult.failed(generic);
  }

  const headerLength = 1 + 4 + smsNonceLength;
  if (raw.length < headerLength + smsTagLength + 1) {
    return SmsAlertDecodeResult.failed(generic);
  }
  if (raw[0] != smsAlertVersion) {
    return SmsAlertDecodeResult.failed(generic);
  }
  final deviceRef = Uint8List.sublistView(raw, 1, 5);
  final nonce = Uint8List.sublistView(raw, 5, headerLength);
  final sealed = Uint8List.sublistView(raw, headerLength);

  Uint8List plain;
  try {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), smsTagLength * 8, nonce, Uint8List(0)),
      );
    plain = cipher.process(sealed);
  } catch (_) {
    // A failed tag lands here, which is the whole point of using GCM: a
    // tampered or forged message cannot be read at all.
    return SmsAlertDecodeResult.failed(generic);
  }
  if (plain.length != 21) return SmsAlertDecodeResult.failed(generic);

  final view = ByteData.sublistView(plain);
  final flags = view.getUint8(0);
  final hasLocation = flags & _flagHasLocation != 0;
  return SmsAlertDecodeResult.ok(
    SmsAlertPayload(
      categoryCode: view.getUint8(1),
      severityCode: view.getUint8(2),
      latitude: hasLocation ? view.getInt32(3) / _coordScale : null,
      longitude: hasLocation ? view.getInt32(7) / _coordScale : null,
      sentAt: DateTime.fromMillisecondsSinceEpoch(
        view.getUint32(11) * 1000,
        isUtc: true,
      ),
      localRef: Uint8List.fromList(plain.sublist(15, 21)),
      isDuress: flags & _flagDuress != 0,
      isAnonymous: flags & _flagAnonymous != 0,
    ),
    Uint8List.fromList(deviceRef),
  );
}

/// How many GSM-7 segments a body of this length needs.
///
/// Exposed so a test can assert the thing that actually costs money, and so a
/// future change to the payload cannot quietly double the bill.
int smsSegmentsFor(String body) {
  if (body.length <= 160) return 1;
  // Concatenated messages spend 7 bits of each segment on the UDH.
  return (body.length / 153).ceil();
}

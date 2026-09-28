/// Sealing an alert so that only HQ can open it.
///
/// ECIES over P-256: a fresh ephemeral keypair per message, ECDH against HQ's
/// long-lived public key, HKDF-SHA256 to an AES key, then AES-GCM.
///
/// ## Why ephemeral, and why that matters more here than anywhere else
///
/// Three properties, and the second is the one the whole mesh design rests on.
///
/// **Only HQ can read it.** The private half never leaves the HQ server, so a
/// relay carrying the message — or somebody who takes the relay's phone —
/// cannot open it.
///
/// **There is no stable sender identifier on the wire.** A fresh keypair per
/// message means two alerts from the same handset share no bytes. This is the
/// difference between a mesh that protects reporters and one that betrays
/// them: a fixed device reference would let a hostile relay fingerprint which
/// handsets in a crowd are reporting and follow them. The SMS channel can
/// afford a stable device reference because the carrier already knows who sent
/// the message. A stranger's phone does not, and must not learn.
///
/// **Forward secrecy per message.** The ephemeral private key is discarded
/// immediately. Taking the reporter's own handset later does not open the
/// alerts it already sent.
///
/// ## What it does not do
///
/// It does not authenticate the sender — deliberately, because a signature
/// would identify them to every relay. So anyone can seal something to HQ and
/// put it in the mesh. HQ learns that a message is well-formed and decryptable,
/// not who sent it, and the flood controls live in `MeshRelay`.
///
/// ## Why P-256 rather than X25519
///
/// Because it is what `pointycastle` gives us today, and adding a native
/// crypto dependency to an emergency app is a cost of its own. X25519 would be
/// smaller and harder to misuse; the security level is comparable and the
/// envelope has room. If the dependency situation changes, the wire format has
/// a version byte and a `keyId`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The sealed body: ephemeral public key, nonce, then ciphertext and tag.
///
/// ```
///   0   1  version
///   1  33  ephemeral public key, compressed P-256
///  34  12  nonce
///  46   n  ciphertext + 16-byte tag
/// ```
const int _sealVersion = 1;
const int _ephemeralLength = 33;
const int _nonceLength = 12;
const int _tagBits = 128;
const int _sealHeader = 1 + _ephemeralLength + _nonceLength;

/// Info string for HKDF, so a key derived here cannot be confused with one
/// derived for another purpose against the same secret.
final Uint8List _hkdfInfo =
    Uint8List.fromList(utf8.encode('operation-rainbow/mesh/v1'));

ECDomainParameters get _curve => ECDomainParameters('prime256v1');

/// Seals [plaintext] to HQ's public key.
///
/// [hqPublicKey] is the compressed or uncompressed P-256 point HQ published.
/// [random] is injectable so tests can be deterministic; production passes
/// nothing and gets a seeded Fortuna.
Uint8List meshSeal({
  required Uint8List plaintext,
  required Uint8List hqPublicKey,
  SecureRandom? random,
}) {
  final rng = random ?? _secureRandom();
  final domain = _curve;

  final generator = ECKeyGenerator()
    ..init(ParametersWithRandom(ECKeyGeneratorParameters(domain), rng));
  final pair = generator.generateKeyPair();
  final ephemeralPrivate = pair.privateKey;
  final ephemeralPublic = pair.publicKey;

  final hqPoint = domain.curve.decodePoint(hqPublicKey);
  if (hqPoint == null) {
    throw ArgumentError.value(hqPublicKey, 'hqPublicKey', 'not a P-256 point');
  }

  final agreement = ECDHBasicAgreement()..init(ephemeralPrivate);
  final shared = agreement.calculateAgreement(ECPublicKey(hqPoint, domain));
  final key = _deriveKey(shared, domain);

  final nonce = rng.nextBytes(_nonceLength);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true,
        AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)));
  final sealed = cipher.process(plaintext);

  final ephemeralBytes = ephemeralPublic.Q!.getEncoded(true);
  final out = Uint8List(_sealHeader + sealed.length)
    ..[0] = _sealVersion
    ..setRange(1, 1 + _ephemeralLength, ephemeralBytes)
    ..setRange(1 + _ephemeralLength, _sealHeader, nonce)
    ..setRange(_sealHeader, _sealHeader + sealed.length, sealed);
  return out;
}

/// Opens a sealed body with HQ's private scalar. HQ side only.
///
/// Returns null for every failure. A caller must not be able to tell a
/// tampered message from one sealed to a different key.
Uint8List? meshOpen({
  required Uint8List sealed,
  required BigInt hqPrivateKey,
}) {
  if (sealed.length <= _sealHeader) return null;
  if (sealed[0] != _sealVersion) return null;
  try {
    final domain = _curve;
    final ephemeral =
        domain.curve.decodePoint(sealed.sublist(1, 1 + _ephemeralLength));
    if (ephemeral == null) return null;
    final nonce = sealed.sublist(1 + _ephemeralLength, _sealHeader);
    final body = sealed.sublist(_sealHeader);

    final agreement = ECDHBasicAgreement()
      ..init(ECPrivateKey(hqPrivateKey, domain));
    final shared =
        agreement.calculateAgreement(ECPublicKey(ephemeral, domain));
    final key = _deriveKey(shared, domain);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false,
          AEADParameters(KeyParameter(key), _tagBits, nonce, Uint8List(0)));
    return cipher.process(Uint8List.fromList(body));
  } catch (_) {
    return null;
  }
}

/// HKDF-SHA256 over the ECDH shared secret, left-padded to the field size.
///
/// Padding matters: a shared secret whose big-integer form happens to be short
/// would otherwise derive a different key on the two sides, and the failure
/// would be intermittent and maddening — roughly one message in 256.
Uint8List _deriveKey(BigInt shared, ECDomainParameters domain) {
  final size = (domain.curve.fieldSize + 7) ~/ 8;
  final raw = _bigIntToBytes(shared, size);
  final hkdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(raw, 32, null, _hkdfInfo));
  return hkdf.process(Uint8List(0));
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}

SecureRandom _secureRandom() {
  final rng = FortunaRandom();
  final seed = Uint8List(32);
  final entropy = DateTime.now().microsecondsSinceEpoch;
  for (var i = 0; i < seed.length; i++) {
    seed[i] = (entropy >> (i % 8 * 8) & 0xff) ^ (i * 31 & 0xff);
  }
  rng.seed(KeyParameter(seed));
  return rng;
}

/// A deterministic random source, for tests only.
///
/// Exposed here rather than reimplemented in the test so the production path
/// and the tested path differ in exactly one thing: the seed.
SecureRandom meshTestRandom(int seed) {
  final rng = FortunaRandom();
  final material = Uint8List(32);
  for (var i = 0; i < material.length; i++) {
    material[i] = (seed + i * 7) & 0xff;
  }
  rng.seed(KeyParameter(material));
  return rng;
}

/// Generates an HQ keypair. Run once, offline; the private half never ships.
({Uint8List publicKey, BigInt privateKey}) meshGenerateHqKeypair({
  SecureRandom? random,
}) {
  final domain = _curve;
  final generator = ECKeyGenerator()
    ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(domain), random ?? _secureRandom()));
  final pair = generator.generateKeyPair();
  return (
    publicKey: pair.publicKey.Q!.getEncoded(true),
    privateKey: pair.privateKey.d!,
  );
}

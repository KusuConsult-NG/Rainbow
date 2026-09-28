# Reaching HQ when the network is gone

A design for two offline channels — a store-and-forward mesh, and an SMS
fallback — for Operation Rainbow. Nothing here is built yet. It is written to
be argued with before anything is.

## What we have today

Established by audit, not assumed:

* **The offline queue works.** `SqliteService` holds reports written with no
  signal; `SyncService` replays them when connectivity returns. Thirteen unit
  tests, including a regression for a fault where every alert queued offline
  reached HQ with no coordinates.
* **There is no second channel of any kind.** No Bluetooth, no Wi-Fi Direct, no
  Nearby Connections, no peer-to-peer, and no SMS capability — no `SEND_SMS`
  permission, no telephony plugin. The one SMS path in the system asks the HQ
  backend to send one over the internet.
* **So a phone alone with no uplink reaches nobody until it has one.** The
  report is safe. It is also stationary.

## The threat model, stated plainly

Four situations, in the order they are likely to happen in Plateau State:

1. **Cell but no data.** 2G coverage, data congested, exhausted or
   unaffordable. Common, routine, and the cheapest to solve.
2. **Congestion.** The network is up and unusable because everyone is using it.
   This is what a mass-casualty event looks like from a handset.
3. **Deliberate shutdown.** Data or all service cut during unrest. Phones have
   power and each other and no tower. This is the case a mesh exists for.
4. **A hostile reader.** Somebody wants to know who reported them and where
   that person is standing.

The fourth is not a separate scenario. It runs underneath the other three, and
it is the one that decides the design.

## The problem that decides everything: a relay is a stranger's phone

A mesh moves a report through handsets that do not belong to the reporter. In
this system a report carries the reporter's identity, their GPS position, a
description of what is happening to them, and sometimes a **duress** flag.

In a communal-violence context, the phone that relays an alert may belong to
somebody on the other side of the conflict. If a relay can read what it
carries, the mesh becomes an efficient way to discover who is reporting and
where they are standing. **That is worse than having no mesh at all.**

So the requirement is not "encrypt the mesh". It is stricter:

> A relay must be able to forward an alert it cannot read, and must not learn
> anything useful from having carried it.

That rules out the obvious design — a signed, readable alert flooded to peers —
and it rules out putting *any* operational detail in the envelope. Not the LGA.
Not the severity. Not the type. "There is a DURESS alert somewhere near here"
is itself actionable intelligence for the person the alert is about.

### What the envelope may contain

Only what a relay needs in order to relay:

| Field | Why a relay needs it |
|---|---|
| `id` | 128 random bits. Deduplication. Carries no meaning. |
| `ttl` | Hops remaining. Decremented on forward; dropped at zero. |
| `createdAt` | Coarse expiry, so nothing circulates for ever. |
| `keyId` | Which HQ key sealed it, so HQ can rotate keys. |
| `nonce` + `ciphertext` | The payload. Opaque. |

Nothing else. In particular the envelope does **not** carry the reporter, the
location, the type, the severity, or the duress flag. Those live inside the
ciphertext, which only HQ can open.

### Sealing

Ephemeral-static ECDH to an HQ public key, then AEAD:

* HQ holds a long-lived keypair. The **private key never leaves the HQ server**.
* The public key ships in the app build the way the Supabase keys already do
  (`--dart-define`), and is refreshable through `app_config` so it can be
  rotated without a release.
* Each alert generates a fresh ephemeral keypair, derives a shared secret, and
  encrypts with AES-GCM. The ephemeral public key travels in the envelope.
* Forward secrecy per message falls out of this: compromising one phone does
  not open alerts it relayed.

`pointycastle` is already in the dependency tree and provides what this needs.
No new native dependency.

### The cost of sealing, stated honestly

A relay cannot validate what it carries. That is the point, and it means the
mesh can be filled with rubbish by anyone. The mitigations are all blunt:

* a hard size cap per envelope,
* a TTL low enough that garbage dies (start at 8 hops),
* per-peer rate limiting,
* a bounded local outbox with oldest-dropped-first.

A signature would fix flooding and would also identify the sender to every
relay, which is the thing we are preventing. **We accept flood risk to keep
reporters unidentifiable.** If that trade ever looks wrong, the answer is a
blinded token from HQ, not a signature — and that is a larger piece of work.

## How a report actually gets out

The exit point is not the reporter's phone. It is whichever phone reaches the
network first.

```
  Reporter (no uplink)
      │  seals payload, writes to local queue AND mesh outbox
      ▼
  Relay B ──▶ Relay C ──▶ Relay D (has data)
      │           │            │  POSTs the ciphertext to /api/mesh/ingest
      └───────────┴────────────┘  HQ opens it, dedups, writes the alert
```

Every relay keeps the envelope in its own outbox and offers it to each new peer
it meets, until it expires or the relay itself gets online and uploads it.

### Duplicates

The same alert will arrive at HQ many times, by different paths, and possibly
again from the reporter's own queue when their phone recovers. Two dedup keys:

* the envelope `id`, at ingest, before decryption;
* `alerts.local_id` from inside the payload — a column that already exists and
  is already written by the offline queue.

Whichever arrives first creates the alert. The rest are counted and discarded.
The count is worth keeping: it is a rough measure of mesh health.

### The ingest endpoint

`POST /api/mesh/ingest` accepts opaque ciphertext. It must be:

* authenticated where possible (a relay is usually a signed-in citizen or
  responder), but **able to accept from an unauthenticated relay**, because
  insisting on a session defeats the purpose during a shutdown;
* rate-limited and size-capped, since it is an unauthenticated write path;
* incapable of leaking anything on failure — a decrypt failure returns the same
  response as a duplicate.

This is a new attack surface on an emergency system. It is the price of the
mesh and should be reviewed as such.

## Transport

The protocol above is independent of the radio. One interface, three
implementations:

```dart
abstract class MeshTransport {
  Stream<MeshEnvelope> get inbound;
  Future<void> start();
  Future<void> stop();
  Future<void> offer(MeshEnvelope envelope);
}
```

| Implementation | Platform | Range | Notes |
|---|---|---|---|
| `NearbyMeshTransport` | Android | ~100 m | Google Play Services. Best throughput. The recommended primary. |
| `BleMeshTransport` | Android + iOS | 10–30 m | Low throughput — an alert fits, photographs do not. Awkward in the background on iOS. |
| `LoopbackMeshTransport` | tests | — | In-process peers. Lets the whole protocol be proven without a radio. |

**Decided: BLE on both platforms** is the baseline, with Nearby as an optional
Android-to-Android accelerator. See the decisions section.

## The SMS channel

A different problem with a different shape, and worth building **first**:
scenario 1 (cell but no data) is far more common than scenario 3, and SMS is a
fraction of the work.

### What is actually possible

* **Android, silent send:** needs the `SEND_SMS` permission. Google Play
  restricts it to apps whose core function is SMS; anything else needs a
  Permissions Declaration and review. Emergency applications have been granted
  exceptions, but it is a real review risk and can hold up a release.
* **Android, no permission:** `url_launcher` with an `sms:` URI opens the
  messaging app with the message pre-filled and the user taps send. Play-safe,
  no declaration — **and useless for a silent or duress SOS**, because it
  requires a visible, deliberate action on screen.
* **iOS:** cannot send SMS programmatically at all, ever. `MFMessageComposeView`
  requires a user tap. Silent SMS is permanently Android-only.

### What an SMS can carry

160 characters in GSM-7, 70 in UCS-2. Sealing and base64-encoding a payload
does not fit in one segment, and every segment costs money.

### CORRECTION: the trade-off I described does not exist

This section originally said the 160-character limit forced a choice between
carrying the duress flag and keeping it private, because an encrypted payload
would not fit. **That was wrong**, and the arithmetic is short enough that it
should have been done before the question was asked:

    version      1            flags/type/severity      3
    device ref   4            latitude                 4
    nonce       12            longitude                4
    GCM tag     16            timestamp                4
                              local ref                6
    ------------------------------------------------------
    33 bytes of envelope  +  21 bytes of alert  =  54 bytes
    base64url, unpadded                        =  72 characters
    plus the "OR1" prefix                      =  75 characters

A GSM-7 segment holds 160. The whole alert — encrypted and authenticated —
fits in **one message with 85 characters to spare**. base64url is used rather
than standard base64 because every character of it is in the GSM-7 default
alphabet, so the message is never promoted to UCS-2 and cut to 70.

So the duress flag travels, and it is not legible to the carrier, and it costs
one message. Implemented and tested in `lib/core/offline/sms_alert_payload.dart`
(21 tests).

Three things fall out of encrypting rather than sending plaintext:

* **The duress flag is carried and concealed.** In the situations a duress PIN
  exists for, the realistic adversary is frequently the person standing next to
  you, and a plaintext `DURESS` in the handset's sent folder is the worst
  possible outcome.
* **HQ cannot be fed a forgery.** The GCM tag authenticates each message
  against that device's key. The `smsWebhook` this replaces accepted anything
  that reached it.
* **A duress alert is the same size as an ordinary one**, so it is not
  distinguishable by length either.

What encryption does NOT buy: the carrier still learns that this handset sent a
short message to the emergency shortcode at a time, from roughly a place.
Traffic analysis is not defeated here and this design does not claim to defeat
it. What is protected is the content.

HQ should still mark SMS-origin alerts as arriving by a degraded channel — not
because the content is untrusted, but because the phone that sent it could not
reach the network, which is itself operationally significant.

### Inbound

HQ's existing `smsWebhook` is a Firebase function this audit already flagged
for deletion: unauthenticated, and able to inject alerts. The SMS ingest needs
rebuilding as an authenticated endpoint that verifies the gateway's signature.
Do not revive the old one.

## What can be proven here, and what needs handsets

This matters because of how much of this session's work turned on the
difference.

**Provable in unit tests and the local harness:**

* envelope encode/decode, and that it carries nothing but routing metadata;
* sealing and opening, and that a relay holding the envelope learns nothing;
* TTL decrement, hop-limit drop, expiry, deduplication, outbox bounds;
* the loopback transport carrying an alert from phone A through phone B to
  ingest, with HQ opening it and writing one alert from three arrivals;
* SMS payload encoding, segment count, and that the duress flag is absent;
* HQ-side dedup against `alerts.local_id`.

**Needs real devices, and will not be verified by me:**

* discovery, pairing and background behaviour on Nearby and BLE;
* battery cost of relaying;
* actual range in the field;
* iOS permission behaviour;
* sending and receiving a real SMS.

## Decisions

### Made

**1. Both iOS and Android.** *(decided)*

This settles the transport. A cross-platform mesh means **BLE as the baseline
on both platforms**, because Nearby Connections is Android-only and Multipeer
Connectivity is iOS-only, and maintaining two native stacks to carry the same
54-byte envelope is not worth it.

The throughput objection to BLE mostly evaporates at this size. The envelope
was designed to carry nothing but routing metadata and a sealed payload, and a
sealed alert is tens of bytes — it fits comfortably in a GATT characteristic.
BLE's low bandwidth would matter if we were relaying photographs. We are not,
and we should not: media stays in the offline queue and uploads when the
reporter's own phone has a network.

Nearby Connections stays on the roadmap as an **optional accelerator** for the
Android-to-Android case, behind the same `MeshTransport` interface. It is not
required for correctness.

The honest cost of choosing both: **iOS background BLE is restricted.** An
iOS app in the background advertises in an "overflow" area that other iOS
devices can see but Android generally cannot, and background scanning requires
naming service UUIDs up front. In practice an iOS relay works well in the
foreground, and degrades in the background in ways that need measuring on real
handsets rather than predicting here.

**2. Carry the duress flag over SMS.** *(decided)*

And, per the correction above, the reason this was ever a question has gone:
it is carried AND encrypted AND still one segment. A duress SOS that silently
degrades to an ordinary one when it travels by SMS does not work in the one
case it exists for.

### Still open

3. **`SEND_SMS` declaration, or `sms:` compose?** The compose route is safe and
   cannot serve a silent SOS. *Recommend: pursue the declaration, with compose
   as the fallback if review refuses.* Note this only affects Android; iOS
   cannot send programmatically either way, so on iOS the SMS fallback is
   necessarily a compose sheet the user taps.
4. **Who pays for SMS, and through which gateway?** Termii is already used
   HQ-side. Every message is a cost, and a flood of alerts is a flood of cost.
5. **Does a citizen's phone relay strangers' alerts by default, or by opt-in?**
   Battery and storage are the obvious costs. The less obvious one is legal:
   carrying somebody else's emergency traffic is not neutral everywhere.
   *Recommend: on by default for responders, opt-in with a clear explanation
   for citizens.*
6. **HQ key rotation cadence**, and who holds the private key.

## What I would build, in order

1. **SMS fallback — BUILT.**
   * ~~payload codec~~ — `lib/core/offline/sms_alert_payload.dart`, 21 tests.
   * ~~device key provisioning~~ — `20260930000000_sms_device_keys.sql` and
     `lib/core/offline/sms_device_key.dart`. 12 assertions on real PostgreSQL,
     10 Dart tests.
   * ~~the Android send path, and the iOS compose sheet~~ —
     `lib/core/offline/sms_sender.dart` and the `SEND_SMS` channel in
     `MainActivity.kt`. 17 tests, most of them about when NOT to spend a
     message.
   * ~~the HQ inbound endpoint~~ — `api/sms/inbound`, 18 tests, replacing the
     unauthenticated `smsWebhook`.
   * ~~the degraded-channel marking~~ — `alerts.arrived_via`.
   * The two implementations of the wire format, Dart and TypeScript, are
     checked against **vectors produced by the Dart encoder** rather than
     against each other's prose: `hq-dashboard-next/src/lib/__fixtures__/`,
     regenerated by `flutter test test/gen_sms_vectors_test.dart`.

   Still needed before it can be switched on, and none of it is code:
   * **file the Play Permissions Declaration** for `SEND_SMS`;
   * choose and provision the gateway shortcode, and set
     `SMS_GATEWAY_SECRET` and the destination number;
   * a field test — two handsets, data off, cell on.
2. **The mesh protocol core**, fully tested against the loopback transport. No
   radio. At the end of this the whole design above is proven except the radio.
3. **The Nearby transport**, written against the interface and marked
   unverified until you have run it on handsets.
4. **Field test**, which is yours: two phones, aeroplane mode, and a walk.

Nothing in step 2 is wasted if step 3's radio choice changes.

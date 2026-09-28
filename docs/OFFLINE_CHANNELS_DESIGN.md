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

### What goes inside the seal: the SMS body, unchanged

Decided while building the ingest endpoint, and it removed a whole payload
format rather than adding one.

The mesh seals to HQ's **public** key, which ships in every app build. So
sealing proves nothing about who sealed it — deliberately, because a signature
would identify the reporter to every relay. That leaves HQ with a problem the
SMS channel does not have: if the payload simply named a reporter, anyone could
manufacture an emergency attributed to anyone.

So the mesh plaintext **is the 75-character `OR1…` SMS body**:

```
  MeshEnvelope { id, ttl, createdAt, keyId,
                 sealed = ECIES-to-HQ( "OR1AaGyw9QAAQ…" ) }
                                        └── AES-GCM under the DEVICE key
```

Two layers, each doing what it is good at. The outer seal makes the envelope
unreadable to relays with no stable sender identifier on the wire; the inner
per-device tag proves to HQ which handset raised the alert and is invisible to
every relay that carried it. What falls out:

* **a mesh alert cannot be forged** — HQ verifies it with the same key, the same
  tag and the same code path as an SMS;
* **one wire format, not two**, with one pair of implementations and one set of
  cross-language vectors;
* **the channels deduplicate against each other for free**, because both carry
  the same `local_id` reference.

The cost is about 21 wasted bytes (base64 inside a binary frame) out of a
512-byte budget, and that a handset with no device key has no offline channel at
all — provisioning happens once, while the phone is online, and a phone that has
never been online cannot be helped by any design here.

### The ingest endpoint — BUILT

`POST /api/mesh/ingest`. It accepts opaque ciphertext from **anyone**: no
session, no header, no identity. That is the one deliberate exception to the rule
this audit applied everywhere else, and the reason is the scenario — during a
shutdown the phone that gets a signal back first may be a stranger's, signed
out, or carrying a token that expired days ago. Requiring a session would mean
the mesh works only when it is not needed.

What makes that safe is not who is calling but what they can say. The worst an
anonymous caller can do is waste our time, and each way of doing so is bounded:

| control | value | what it stops |
|---|---|---|
| body cap | 64 KB | the endpoint used as a file upload |
| frames per request | 32 | one POST costing unbounded work |
| per-IP rate limit | 30/min | one host flooding |
| envelope-id dedup | 48h memory | one frame becoming many incidents |
| freshness window | 24h, +1h skew | a captured frame replayed for ever |
| `local_id` dedup | permanent | the reporter's own queue duplicating |

Two properties worth naming because they are easy to get backwards:

* **The response is the same for every frame.** It lists the ids this endpoint is
  finished with — accepted, already seen, sealed to another key, or garbage — and
  a relay drops exactly those. A relay that could tell which frames HQ actually
  wanted could tell which of the phones around it are reporting.
* **The envelope-id dedup fails OPEN.** If the dedup table is unavailable the
  alert is recorded anyway. A duplicate incident is visible to a dispatcher and
  can be merged; an alert dropped because a bookkeeping table was down is visible
  to nobody.

Still an operational requirement, not satisfied by code here: the per-IP limit is
**per running instance**, so on a platform that scales this route out, ten
instances permit ten times the traffic. A distributed flood has to be handled at
the edge. Said plainly rather than quietly assumed.

28 endpoint tests, 41 more on the frame decoder and the sealer, all driving
frames that the Dart app actually sealed.

### A defect this step found in the previous one

`mesh_sealer.dart` shipped seeding its generator from
`DateTime.now().microsecondsSinceEpoch`. That generator produces every AES-GCM
nonce the mesh uses **and** HQ's own keypair. Two seals in the same microsecond
would have seeded identically and emitted the same nonce under the same key —
which leaks the XOR of the two plaintexts and the authentication subkey, enough
to forge — and the keypair had a searchable keyspace, for a key that opens every
mesh alert ever sent.

It decrypts perfectly, so no behaviour test would ever have found it. It is now
`Random.secure()`, and `scripts/check_crypto_entropy.py` fails the build for a
clock used as entropy anywhere in the two crypto directories. That gate was
mutation-tested against the original line.

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
* the loopback transport carrying an alert from phone A through phone B to a
  phone with a network, and HQ opening it and writing one alert from several
  arrivals. Stated precisely, because it is a chain of two runs rather than one:
  the Dart test drives the crossing and produces the frame, and the TypeScript
  tests take **that frame's bytes** through the real endpoint. What is NOT
  proven by either is an HTTP round trip between the two, which is the one link
  the field test covers anyway;
* SMS payload encoding, segment count, and that the duress flag is absent;
* HQ-side dedup against `alerts.local_id`.

* chunking a frame into eleven 20-byte BLE writes and reassembling it, including
  every way a hostile peer can abuse that;
* a peer disconnecting mid-frame, a write failing, a queue filling, and one dead
  link not stopping the peer that works;
* the platform channel's decoding of everything a native side might send,
  including what it should not.

**Needs real devices, and will not be verified by me:**

* discovery, pairing and background behaviour on BLE — and the native halves are
  not even written yet;
* whether MTU negotiation succeeds, and what happens on the handsets where it
  does not;
* battery cost of relaying;
* actual range in the field;
* iOS permission and background behaviour;
* sending and receiving a real SMS.

The seam is at `BleRadio` precisely so that this list is short and the list above
it is long. Everything in the second list is about a radio finding another radio.

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
2. **The mesh protocol core — BUILT.** No radio; everything above the transport
   seam, proven in unit tests.
   * `mesh_envelope.dart` — the wire frame, carrying a random id, a hop count,
     a coarse timestamp, a key id and an opaque body, and nothing else. 16
     tests, including that nothing operational is legible in a frame and that
     a stranger's malformed bytes return null rather than crashing a relay.
   * `mesh_sealer.dart` — ECIES over P-256: ephemeral keypair per message,
     ECDH to HQ's public key, HKDF, AES-GCM. 11 tests, including the one the
     design turns on: **two alerts from the same handset share no bytes**, so
     a hostile relay cannot fingerprint which phones in a crowd are reporting.
   * `mesh_relay.dart` — deduplication, hop limit, age limit, size cap and a
     bounded outbox that drops the OLDEST first, so a flood wins a delay and
     not permanent silence. 16 tests.
   * `mesh_transport.dart` — the seam. A loopback implementation carries real
     encoded frames through the real decoder, so a wire-format regression
     fails here rather than only on a handset.
   * `mesh_end_to_end_test.dart` — a sealed report crossing three phones to one
     with a network, with the relays unable to read what they carry, HQ opening
     it, and the hop limit stopping it dead in a line of twelve.
3. **The HQ mesh ingest endpoint — BUILT.** `api/mesh/ingest`, plus the two
   halves it needs:
   * `mesh-envelope.ts` and `mesh-sealer.ts` — the HQ mirror of the wire format
     and of ECIES, opening frames the **Dart encoder** produced
     (`test/fixtures/mesh_envelope_vectors.json`). ECIES has four places where
     two implementations diverge silently — point compression, the HKDF info
     string, padding the shared secret, tag position — and all four fail
     identically as "authentication failed", so this is checked on real bytes
     rather than on two readings of the same prose.
   * `offline-alert-ingest.ts` — the recording path, now **shared** by SMS and
     mesh, so "created_at is when the phone raised it", "a duress alert is
     CRITICAL" and "an anonymous report is not attributed" cannot be true in one
     channel and false in the other.
   * `20261001000000_mesh_ingest.sql` — `mesh_envelopes_seen`, its RPC and its
     48-hour purge. 12 assertions on real PostgreSQL, one of them structural:
     the table must have **exactly** four columns, so nobody can later add
     "which relay uploaded it" and turn a dedup table into a record of who
     carried whose emergency.
   * Two new CI gates, both of which caught something before they were
     committed: `check_vectors_synced.py` (the console's copy of the vectors must
     equal the Dart-generated one) and `check_crypto_entropy.py` (see above).
4. **The BLE transport — everything above the radio is BUILT. The radio is not.**
   The seam is `BleRadio`, four verbs wide: who is in range, what they wrote,
   how much may be written at once, write this. Above it, tested:
   * `mesh_chunking.dart` — the reason this step is not trivial. A frame is 166
     bytes and a **default BLE write carries 20**, so every frame is split into
     eleven pieces and reassembled by a stranger's phone. That makes it the most
     dangerous file in the mesh: it is the one place where bytes somebody else
     chose are assembled into a buffer whose size they choose. Hence a declared
     length that may not change, a 512-byte cap, four open messages per peer, a
     20-second expiry, and the rule that only the last chunk may be short. 25
     tests, most of them refusals.
   * `ble_mesh_transport.dart` — one write at a time per peer (BLE stacks drop
     parallel writes on one link), a bounded queue that drops the OLDEST frame,
     and isolation between peers so one dead link cannot stop the phone that can
     actually carry the alert out. 10 tests, driven by a fake radio that enforces
     the MTU, fails writes, drops them silently and disconnects mid-frame.
   * `mesh_node.dart` — the schedule, which nothing else owned: on meeting a
     peer, offer everything held; on receiving, apply the relay's rules before
     storing; on sign-out, stop and forget. 5 tests, including a duress alert
     crossing two strangers to a phone with a network, through the real chunker.
   * `method_channel_ble_radio.dart` — the platform contract, written as code so
     the remaining work is "implement these five messages" rather than "add
     Bluetooth". 15 tests, most of them sending things no correct native side
     would send, because a platform channel hands over `Map<Object?, Object?>`
     with nothing checked and a crash there takes down a relay carrying
     somebody's duress alert.

   **What remains, and it is all native:** an Android implementation (GATT server
   + scanner, `BLUETOOTH_ADVERTISE` / `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` with
   `neverForLocation`) and an iOS one (`CBPeripheralManager` +
   `CBCentralManager`). The permissions are deliberately **not** in the manifest
   yet: declaring a capability the app does not have is noise in a Play review.
   The four requirements that are easy to miss — an unstable `peerId` that is not
   an identity, reporting the MTU actually negotiated, advertising no identity at
   all, and reporting disconnects promptly — are written at the top of
   `method_channel_ble_radio.dart`.
5. **The app actually calls them — BUILT.** Everything above was built, tested
   and **unreachable**: a report raised with no data went into the local queue and
   nothing in the app called the SMS codec, the device key, the sealing, the relay
   or the transport. Three joins were missing, and finding them turned up two
   defects that no amount of testing the pieces separately could have found.
   * `offline_escalation.dart` — called at the two moments a report fails to
     reach the database: the radio says there is no network, **and** the insert
     was refused. The second matters more and is the one a connectivity check
     cannot see — a captive portal, a congested tower that carries a text but not
     a TLS handshake, an expired token, an RLS refusal, HQ down. One sealed body
     goes to both channels. 17 tests, most about when NOT to spend a message.
   * `offline_ref.dart` — **the dedup could never have matched.** HQ recognises a
     repeat delivery with `local_id LIKE '%<hex>%'`, the offline channels carry
     six bytes of it, and the queue's id was `OFFLINE_<milliseconds>` — a string
     those bytes do not appear in under any encoding. So one emergency arriving by
     SMS and again from the queue would have become two incidents and two
     dispatches. The id now ends in a random 12-hex tag, and the queue's own flush
     checks for a row already carrying it, so both orders are covered — which
     matters because in the field the SMS usually wins and the design assumed the
     queue would. The tag is random rather than a truncated timestamp because a
     dedup collision is not a duplicate, it is a **dropped** emergency.
   * `sqlite_service.dart` v3 — **the queue did not record who reported.** So
     `buildOfflineSyncPayload` could not carry it and every alert replayed from
     the offline queue reached HQ with `reported_by` NULL: no callback number for
     the dispatcher, no visibility for the reporter under RLS, and nothing for the
     dedup to scope by. Fixed with a nullable column and a migration that leaves
     older rows null, because null is the truth about them.
   * The key is obtained at **sign-in** (`AuthService.onSessionEstablished`), and
     it has to be: the channels exist for when there is no data, so the key cannot
     be fetched at the moment it is needed. Failure never blocks the sign-in.

   **A flag nothing can set, stated rather than left to be discovered.** The SMS
   payload carries a duress bit, and no code path sets it today. Duress is
   established by a **server-verified** PIN — deliberately, since the alternative
   is PIN material on the handset, which is what this audit removed — and the
   server is exactly what is unreachable when these channels are in use. So an
   offline duress signal would need a different mechanism, not a different call
   site. The bit stays in the format because adding it later would be a wire
   change; claiming the capability now would be a lie.
6. **Field test**, which is yours: two phones, aeroplane mode, and a walk.

Nothing in steps 2 and 3 is wasted if step 4's radio choice changes.

### What each channel still needs before it can be switched on

**SMS** — all of it operational, none of it code:
* file the Play Permissions Declaration for `SEND_SMS`;
* provision the gateway and set `SMS_EMERGENCY_SHORTCODE` (app) and
  `SMS_GATEWAY_SECRET` (HQ);
* a field test: two handsets, data off, cell on.

Until the shortcode is set the app skips SMS entirely rather than sending a
message with nowhere to go.

**Mesh** — the radio, and one key:

* **`MESH_HQ_PRIVATE_KEY`.** Generate the pair offline with
  `MESH_KEYGEN=1 flutter test test/mesh_keygen_test.dart`, which verifies that
  the pair it prints opens what it seals. The private half goes into the HQ
  server's environment and nowhere else.
* **`MESH_HQ_PUBLIC_KEY`** in the app's `.env`, as 66 hex characters. Safe to
  bundle — it can only seal — and refused outright unless it is a well-formed
  compressed point, because a phone that believes it has a working channel is
  worse than one that knows it has not.

  **Correction to this document:** it said earlier that the public key would ship
  through `app_config`, "so it can be rotated without a release". As built it is
  a bundled `.env` value, which means rotation **does** need a release. The
  envelope still carries a `keyId`, so HQ can accept two keys during a rotation,
  but the handset side of that is a release. Moving the value to `app_config`
  with the bundled one as a fallback is a small change and the right one before
  the first rotation; it is not done.
* **A decision on relaying by default**, still open (item 5 below).
* **The radio**, which is step 4.
* **Edge rate limiting**, per the note above.

Until the key is set, `/api/mesh/ingest` refuses every frame — and says nothing
about why.

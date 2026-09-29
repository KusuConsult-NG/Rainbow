# USSD reporting

Reporting an emergency from a handset that cannot make a call: no data, no
smartphone, no credit. In Plateau State that is most of the people this system
exists to protect.

---

## What a caller does

They dial the shortcode. The first item is the emergency, and it is the shortest
path deliberately:

```
Operation Rainbow
1. EMERGENCY - send help
2. Report an incident
3. My last report
4. My details
```

For a number **already known** to the system — anyone who onboarded in the app —
the location comes from their profile, so an emergency is **three keypresses**
after dialling: `1` → what is happening → confirm. For an unknown number it is
five, because the LGA and ward have to be chosen.

At any point on the emergency branch they can press `0` for **send now, no
place**. That is not a fallback bolted on; it is deliberate. An unlocated incident
is visible to *every* staff account by design (`20261006000000`), so somebody being
attacked is never held at a ward list.

### Three things the screens will not say

- **Never "help is on the way."** Nobody has decided that yet. A USSD report
  enters as unconfirmed intelligence and a named officer promotes it. Telling a
  frightened person units are coming when none is assigned is the same class of
  lie as an empty board saying ALL SECTORS CLEAR.
- **A failure gets no reference.** `NOT SENT. Please dial again now. If this is
  life-threatening, call 112.` Somebody who believes their report went through
  stops trying.
- **"My last report" carries no unit, position or ETA.** Whoever holds the SIM can
  read that screen. Somebody who filed a report to draw officers to a place must
  not be able to watch them arrive.

---

## Tracking a USSD report

The honest part first: **a USSD reporter's live movement cannot be tracked.** USSD
rides the signalling channel and has no access to the handset's location. There is
no GPS, no way to ask for one, and no engineering that changes it. The app's
`incident_tracks` — a reporter's route, drawn on the map — has no USSD equivalent
and cannot have one.

What *is* known, in descending order of precision:

| Precision | Drawn as | From |
|---|---|---|
| `GPS` | a pin | a real fix (app reports only) |
| `WARD` | a circle the size of that ward | the ward chosen on the menu |
| `LGA` | a much bigger circle | the LGA, when no ward was given |
| `NONE` | not drawn, counted as UNLOCATED | nothing |

An approximate position is a **translucent circle with a dashed edge and nothing
at its centre** — never a pin. The distinction decides whether a vehicle can be
sent: an area tells a commander which unit owns the incident, which is a different
question from where to drive. The dossier says so first: *"NO GPS — approximate
area only, about 3.5km across. Do not dispatch to this circle as an address."*

Radii are computed, not guessed — half the distance to the nearest other ward
centroid in the same LGA, clamped to [800m, 25km]. Across Plateau that is 800m to
16.5km, median 3.5km. A single made-up 5km would flatter a Jos North ward of a few
streets and lie about a Wase ward of open countryside.

### The landmark is what actually finds someone

After the report is filed — never before — the caller is asked to type the nearest
landmark. One screen, skippable with `0`.

This is the highest-value field on a USSD report. "Behind the mosque on the Bokkos
road" or `POLICE BARRACKS` is worth more to a driver than a 3km circle, and no
menu could have contained it. It is stored in `reporter_landmark` **and** appended
to the description, because the description is what a dispatcher reads first and
what the notices carry.

It is **not** a location. It never becomes coordinates: there are no
polling-unit coordinates in this system, and deriving a point from a string would
be the fabricated-fix defect wearing a different hat.

It is asked after filing so that a person under attack is never held behind one
more screen. If the session drops, the emergency is already on the board.

### What could improve this, and needs asking

**Cell-site location.** The carrier knows which tower served the session. Accuracy
runs from roughly 200m in Jos to tens of kilometres in rural Plateau — often not
enough to find a person, but enough to confirm they are in the ward they said. Some
aggregators expose Cell ID / LAC in the callback; many do not, and some require a
separate location-based-service agreement.

**Ask Interswitch whether their callback carries Cell ID, LAC or any location
field.** If it does, it is worth wiring: it is the only signal available that the
caller does not have to type. I have not built for it, because building against a
field I cannot confirm exists would be inventing a contract.

### Responders, on the other hand, *are* tracked

Worth saying plainly, because it is most of what the map is for during an incident:
the **responders** sent to a USSD report appear on the map exactly as they do for
an app report. Responder telemetry is keyed on the alert, not on how it arrived.
What you lose with USSD is the reporter's position, not the operation's.

---

## Registration: why there is no OTP

The app onboards with phone + SMS OTP, which proves somebody could read a code
sent to that SIM. USSD proves the same thing more directly: **the MSISDN arrives
in the session metadata from the carrier**, not from anything the user typed. It
cannot be mistyped, spoofed through a legitimate aggregator, or phished, because
there is no code to forward.

So an unknown number self-registers on the request that files its report — not
while it is still reading menus, so somebody who dials, looks and hangs up leaves
no account behind. What is created is thin on purpose: a `CITIZEN` with a
proven-reachable number and, if they chose one, an area. No name, and no claim
about who they are.

A USSD-only reporter has no session and cannot open an app they never installed,
which is why menu item 3 exists — dialling back in is their only window.

---

## The ambush problem, and what is actually done about it

USSD is the cheapest possible way to lure responders to a chosen place: no
install, no data, a cheap SIM, and the report is indistinguishable from a real
one. Security personnel in this state have been attacked after being drawn to a
location.

### Two mitigations that are theatre

**Rate-limiting per number** and **requiring registration**. Both cost one more
SIM to defeat, and self-registration is instant *by design* — the carrier asserts
the number, so there is nothing to verify and nothing to slow down. That openness
is the point of the channel and is worth its cost. Pretending a rate limit closes
the hole would be worse than leaving it open knowingly.

### What is done

**1. No timer may act on an unconfirmed report.** `escalate_overdue_alerts()`
climbs any unacknowledged alert a tier at a time — UNIT, WARD, LGA, HQ — and every
new row defaults to `UNIT`. So a fake report would page a ward commander, then an
LGA commander, then Command HQ, with no human having judged it: *the timers do the
attacker's work*. `awaiting_human_confirmation()` holds it at UNIT.

It is **not hidden and not quiet** — it is on the board, counted, and shown with
its provenance. What it cannot do is manufacture urgency by itself.

**2. Dispatch confirms; it is never blocked.** Greying out DISPATCH until somebody
clicks CONFIRM costs seconds in an armed attack and buys nothing. Dispatching an
unconfirmed report confirms it in the officer's name, in the same action.

**3. A false report is recordable.** There was no way to say a report was a lie —
`status` had RESOLVED and CANCELLED, and CANCELLED is a reporter standing
themselves down. `mark_false_report()` is an officer's accusation, attributed.
Without it no signal could ever accumulate against a number and every credibility
measure below would be guesswork dressed up as evidence.

**4. Corroboration, counted two ways.** `ussd_report_credibility()` reports the
number of other reports *and* the number of distinct other numbers, in the same
ward and category within 45 minutes. Four reports from one number is one person
pressing keys; four from four numbers is a village. Repeats from the same number
are shown as an **absence** of corroboration.

Figures, not a score. The failure mode of a confidence percentage on an emergency
console is an officer who trusts 82% and never reads the four facts behind it.

### What deliberately does *not* count as suspicion

- **A declined callback.** A witness to a militia attack has excellent reasons not
  to want their phone ringing. Treating that as a warning punishes exactly the
  people this channel is for.
- **A first-time caller.** Almost every USSD reporter is one. If that were enough,
  the flag would be on every report and mean nothing.
- Corroboration from independent numbers **outweighs** a bad history. A village
  under attack may include somebody who cried wolf last month.

### The honest limit

None of this makes a false report impossible. What it guarantees is that no
stranger's keystrokes turn into a deployment without a named officer deciding,
with the provenance in front of them.

---

## Provisioning

### 1. The shortcode

A Nigerian USSD shortcode is provisioned **per carrier**. MTN, Airtel, Glo and
9mobile each need it separately, and lead time is typically weeks. Start this
first — it is the long pole, and everything below can be tested without it.

Ask the aggregator for a **dedicated** code rather than a shared one with a menu
prefix. An emergency service behind `*347*100*4#` is three more keypresses and one
more chance to mis-key than `*347*100#`.

### 2. Environment

| Variable | Purpose |
|---|---|
| `USSD_GATEWAY_SECRET` | Shared secret the aggregator must send as `x-gateway-secret`. Compared in constant time. **Without it the endpoint refuses every request** — an open USSD endpoint lets anybody inject emergencies with a forged MSISDN, which removes the one thing this channel's trust rests on. |
| `USSD_REPLY_FORMAT` | `AT_TEXT` (default) for the `CON `/`END ` plain-text convention, or `JSON`. |

### 3. Point the aggregator at

```
POST https://<your-console-host>/api/ussd
     x-gateway-secret: <USSD_GATEWAY_SECRET>
```

Both `application/json` and `application/x-www-form-urlencoded` are accepted.

### 4. What the callback must contain

The adapter (`src/lib/ussd-gateway.ts`) accepts the field names used by every
aggregator whose contract could be verified, and **refuses anything else** rather
than guessing — logging the keys that did arrive. An adapter that silently reads
`undefined` as an empty keypress produces a menu that restarts on every screen and
gives you nothing to debug.

| Needed | Accepted names |
|---|---|
| Session id (**required**) | `sessionId`, `session_id`, `sessionID`, `sessionid` |
| Caller MSISDN (**required**) | `phoneNumber`, `msisdn`, `MSISDN`, `from`, `subscriberNumber`, `msisdn_number` |
| Latest input (optional — absent means the session just opened) | `text`, `userInput`, `input`, `message`, `ussdString` |
| Shortcode (optional, logged only) | `serviceCode`, `service_code`, `shortCode` |

**Accumulated input is handled either way.** Some aggregators send the whole
`*`-joined path (`"1*2*4"`), others only the new keypress (`"4"`). Both work
without configuration, because a keypress never contains `*` — the menu is digits
only.

> **If your aggregator's field names are not in that table**, send me a sample
> callback or their integration spec and the mapping is one small function. I have
> not invented field names for a contract I cannot verify, because names that look
> right and fail in UAT are worse than a refusal that says which keys arrived.

### 5. Apply the migrations

```
20261011000000_ussd_reports_are_unconfirmed.sql
20261012000000_ussd_filing.sql
```

### 6. Schedule the session sweep

```sql
select cron.schedule('rainbow-sweep-ussd', '*/30 * * * *',
                     $$select public.sweep_ussd_sessions()$$);
```

`ussd_sessions` holds the MSISDNs of people who reported, including anonymously.
Keeping rows after the dialogue ends turns a session store into a log of who
dialled what. The alert keeps what it needs; the dialogue does not outlive the
call.

---

## Testing without a shortcode

```bash
curl -X POST http://localhost:3000/api/ussd \
  -H "x-gateway-secret: $USSD_GATEWAY_SECRET" \
  -H 'content-type: application/json' \
  -d '{"sessionId":"test-1","phoneNumber":"08030001111"}'
# CON Operation Rainbow
# 1. EMERGENCY - send help
# ...

curl -X POST http://localhost:3000/api/ussd \
  -H "x-gateway-secret: $USSD_GATEWAY_SECRET" \
  -H 'content-type: application/json' \
  -d '{"sessionId":"test-1","phoneNumber":"08030001111","text":"1"}'
```

Send the **same** session and input twice and you get the identical screen back:
that is the retry path, and it is the reason a congested network cannot turn one
kidnapping into four incidents.

---

## The constraint that breaks things silently

**182 characters per USSD screen.** A longer reply is truncated by some networks
and dropped by others — silently, and differently per carrier. One menu item added
in a refactor can break the emergency path on MTN while it still works on Airtel.

`ussd-menu.test.ts` asserts the limit on **every reachable screen**, including
every page of every ward picker in all 17 LGAs (the longest ward name is 25
characters, so a page size chosen against average names overflows on whichever LGA
has long ones) and every invalid-input screen, which prepend a line to a menu
already near the limit and are therefore where an overflow hides.

If you add a menu item and the tests fail, **the tests are right.**

---

## Where the code is

| Concern | File |
|---|---|
| The menu, as a pure reducer | `hq-dashboard-next/src/lib/ussd-menu.ts` |
| Aggregator adapter and reply rendering | `hq-dashboard-next/src/lib/ussd-gateway.ts` |
| The gateway endpoint | `hq-dashboard-next/src/app/api/ussd/route.ts` |
| What a dispatcher is shown | `hq-dashboard-next/src/lib/ussd-provenance.ts` |
| Escalation hold, false reports, credibility | `supabase/migrations/20261011000000_*.sql` |
| Filing exactly once per session | `supabase/migrations/20261012000000_*.sql` |
| Behaviour assertions against real PostgreSQL | `scripts/ussd_*_behaviour_test.sql` |

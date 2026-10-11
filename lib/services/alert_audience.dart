import 'package:rainbow_app/core/geo/geo_key.dart';

/// Which incidents reach this handset.
///
/// ## Why this is a function and not a closure
///
/// This rule used to live inside `alertsStreamProvider`, as a `.where()` in the
/// middle of a StreamProvider. Every test that touches the feed overrides that
/// provider — `alertsStreamProvider.overrideWith(...)` appears in four test
/// files — so the rule that decides which emergencies a responder is shown had
/// no test of its own. The app already learned this twice, with
/// `broadcast_targeting.dart` and `assignable_responders.dart`: a decision
/// worth getting right is worth extracting.
///
/// ## The defect that made it urgent
///
/// The word "liaison" did not appear anywhere in `lib/`, and the filter had no
/// branch that could match one. The database does:
///
/// ```sql
/// -- alert_is_ours(), 20261006000000_alerts_scoped_to_posting.sql
/// -- An outside agency: only what was handed to them.
/// OR (public.is_liaison()
///     AND upper(COALESCE(p_alert.escalated_to_agency, ''))
///           = public.liaison_agency());
/// ```
///
/// So RLS hands an agency liaison exactly the incidents escalated to their
/// agency and nothing else — and this filter then compared each one's location
/// against the liaison's OWN POSTING and dropped it. The Army liaison in the
/// fixtures is posted to MANGU; the incident escalated to the Army is in JOS
/// NORTH; their handset feed was empty. HQ's console shows the handover as
/// done, `/api/notify-agency` reports it sent, and the device the officer
/// carries shows nothing. T-28 was "escalating an incident to the Police
/// reached nobody, by three paths at once"; this is a fourth, on the handset.
///
/// Against the local stand-in it fails the other way, which is why no harness
/// run caught it: `fake_supabase.js` applies no RLS, so the Police liaison —
/// posted to JOS NORTH, where the fixture incidents are — was admitted by the
/// place rules and saw incidents that were never handed to the Police. Empty
/// against production, wrong against the stand-in, green in both.
///
/// ## The asymmetry that matters
///
/// RLS decides access; this decides what is worth putting in front of somebody,
/// so that a polling-unit officer is not handed the whole state. It may
/// therefore be MORE permissive than RLS harmlessly — the rows never arrive —
/// but it must never be STRICTER, because anything it drops that the database
/// deliberately granted is an emergency somebody was meant to see.
///
/// `scripts/check_alert_audience_agrees.py` holds the liaison rule on both
/// sides.

/// The officer, as `profiles` describes them.
class AlertAudience {
  /// Creates an audience test for one account.
  const AlertAudience({
    this.userId,
    this.role = '',
    this.agency,
    this.geoLga,
    this.geoWard,
    this.geoPu,
  });

  /// From the signed-in profile. `agency` is derived from the ROLE, never from
  /// `profiles.agency`, which is a decorative badge (T-28).
  factory AlertAudience.fromProfile(
    Map<String, dynamic>? profile, {
    String? userId,
  }) {
    final p = profile ?? const {};
    final role = (p['role'] as String? ?? '').toUpperCase();
    return AlertAudience(
      userId: userId,
      role: role,
      agency: agencyOfRole(role),
      geoLga: p['geo_lga'] as String?,
      geoWard: p['geo_ward'] as String?,
      geoPu: p['geo_pu'] as String?,
    );
  }

  /// This account's id, or null when the session has not resolved.
  final String? userId;

  /// `profiles.role`, upper-cased. Empty when it is not known yet.
  final String role;

  /// The agency this account is a liaison for, or null for Rainbow staff.
  final String? agency;

  /// The officer's own posting. Any may be absent.
  final String? geoLga;

  /// The officer's own posting. Any may be absent.
  final String? geoWard;

  /// The officer's own posting. Any may be absent.
  final String? geoPu;

  /// Whether this account belongs to an outside agency.
  bool get isLiaison => agency != null;

  /// Whether this account commands the whole state.
  ///
  /// Mirrors `commands_whole_state()`. A liaison is excluded explicitly: their
  /// role cannot contain HQ today, and relying on that is how
  /// `role.contains('LGA')` would one day admit an agency whose code contains
  /// those letters.
  bool get commandsWholeState =>
      !isLiaison &&
      (role.contains('STATE') || role.contains('HQ') || role == 'ADMIN');
}

/// The agency a `_LIAISON` role belongs to, or null.
///
/// Mirrors `agencyOf()` in the console's `console-access.ts` and
/// `is_liaison()`/`liaison_agency()` in SQL, which match `'%\_LIAISON'` and
/// take everything before it.
String? agencyOfRole(String? role) {
  final r = (role ?? '').trim().toUpperCase();
  if (!r.endsWith('_LIAISON')) return null;
  final code = r.substring(0, r.length - '_LIAISON'.length);
  return code.isEmpty ? null : code;
}

/// The LGA the last escalation entry handed this incident to, if any.
///
/// Mirrors `alert_delegated_to_my_lga()`: the LAST entry only, because the log
/// is append-only and an earlier handover has been superseded.
String? delegatedLga(Map<String, dynamic> alert) {
  final log = alert['escalation_log'];
  if (log is! List || log.isEmpty) return null;
  final last = log.last;
  if (last is! Map) return null;
  final to = (last['to_lga'] as String?)?.trim();
  return (to == null || to.isEmpty) ? null : to;
}

/// Whether the last escalation handed this incident to `myLga`.
bool delegatedToLga(Map<String, dynamic> alert, String? myLga) {
  if (myLga == null || myLga.trim().isEmpty) return false;
  final to = delegatedLga(alert);
  return to != null && sameGeo(to, myLga);
}

/// The WARD the last escalation entry handed this incident to, if any.
///
/// Mirrors `alert_delegated_to_my_ward()`. An LGA commander can hand an
/// incident to a ward other than the one it sits in — the roadblock is on the
/// far side of the boundary, or the ward it is in has nobody free — and before
/// `to_ward` existed they could assign individual responders but could not give
/// that ward's commander the incident.
String? delegatedWard(Map<String, dynamic> alert) {
  final log = alert['escalation_log'];
  if (log is! List || log.isEmpty) return null;
  final last = log.last;
  if (last is! Map) return null;
  final to = (last['to_ward'] as String?)?.trim();
  return (to == null || to.isEmpty) ? null : to;
}

/// Whether the last escalation handed this incident to `myWard` in `myLga`.
///
/// The LGA is compared too, because ward names are NOT unique across Plateau's
/// seventeen LGAs — granting on the ward name alone would hand the incident to
/// a commander in a different LGA who happens to share it. An entry that
/// recorded no LGA is trusted on the ward alone, which is what the SQL does.
bool delegatedToWard(
  Map<String, dynamic> alert,
  String? myWard,
  String? myLga,
) {
  if (myWard == null || myWard.trim().isEmpty) return false;
  final toWard = delegatedWard(alert);
  if (toWard == null || !sameGeo(toWard, myWard)) return false;
  final toLga = delegatedLga(alert);
  return toLga == null || sameGeo(toLga, myLga);
}

/// Whether `alert` belongs on `officer`'s handset.
bool alertReaches(Map<String, dynamic> alert, AlertAudience officer) {
  final assignedTo = alert['assigned_to'] as String?;
  final assignedResponders =
      (alert['assigned_responders'] as List<dynamic>?)?.cast<String>() ??
          const <String>[];

  // 1. Theirs by name: the lead, or one of the dispatched team. Always.
  final id = officer.userId;
  if (id != null && (assignedTo == id || assignedResponders.contains(id))) {
    return true;
  }

  // 2. An outside agency sees what was handed to their agency, and only that.
  //
  // BEFORE the place rules, and returning rather than falling through, because
  // their posting is where they are based and has nothing to do with which
  // incidents are theirs. This is the branch that did not exist.
  if (officer.isLiaison) {
    final handedTo =
        (alert['escalated_to_agency'] as String? ?? '').trim().toUpperCase();
    return handedTo.isNotEmpty && handedTo == officer.agency;
  }

  // 3. HQ, state command and administrators: the state.
  //
  // Deliberately broader than `commands_whole_state()`, which is the exact set
  // ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'). Being broader than RLS is free — the
  // extra rows never arrive — while being narrower drops incidents the database
  // granted. A deployment that adds 'HQ_OPERATOR' keeps working; tightening
  // this to the SQL's three literals is the change that would break it.
  if (officer.commandsWholeState) return true;

  // An officer whose role has not loaded yet is deliberately NOT failed closed
  // here, which is the opposite of what the console's advisory banner does
  // (T-34). The costs point opposite ways. Withholding an advisory addressed to
  // another agency shows nothing and loses nothing; an EMPTY mission feed on a
  // responder's handset reads as ALL CLEAR, which is the exact fault
  // `AlertsFeed.liveness` exists to prevent — "never reports ALL CLEAR
  // territory: liveness is degraded, not live". So an unresolved role falls
  // through to the place rules below with null postings, which admits the
  // unlocated incidents and nothing else, until the profile lands.
  //
  // Unknown AGENCY still fails closed, two rules up: that one withholds
  // somebody else's incident rather than their own.

  // Place names are compared on geoKey, not on toUpperCase(). This app writes a
  // ward resolved from the GPS centroid asset ('GINDIRI  I') while an officer
  // is posted from the tactical map ('GINDIRI  1'), so the raw comparison
  // failed for four Mangu wards. See lib/core/geo/geo_key.dart.
  final alertLga = alert['geo_lga'] as String?;
  final alertWard = alert['geo_ward'] as String?;
  final alertPu = alert['geo_pu'] as String?;

  // 4. An incident with no LGA recorded is UNLOCATED, and reaches all staff.
  //
  // `alert_in_my_area()` tests only the LGA for this — "Unlocated incidents
  // fail OPEN. See the note above: an emergency nobody can see is worse than
  // one seen too widely" — while this filter used to require all three of
  // LGA, ward and PU to be absent. So an incident with a ward but no LGA was
  // granted by the database to every officer and shown by the handset only to
  // that ward's. Stricter than RLS, which is the one direction that loses
  // emergencies.
  if (alertLga == null) return true;

  // 5. Handed down to an LGA, or across to a WARD, by name.
  //
  // HQ delegates by setting `assigned_tier` and naming a target LGA in the last
  // escalation_log entry, and `alert_delegated_to_my_lga()` grants it to that
  // LGA's staff whatever the incident's own location says. The old inline
  // filter's comment claimed this — "Show alerts matching LGA, unassigned, or
  // escalated to LGA" — and the code under it read only `geo_lga`. It bites
  // when the target LGA differs from the incident's own, which is why an
  // incident is delegated across a boundary in the first place.
  if (delegatedToWard(alert, officer.geoWard, officer.geoLga)) return true;
  if (delegatedToLga(alert, officer.geoLga)) {
    // AN ENTRY THAT ALSO NAMES A WARD IS AIMED AT THAT WARD.
    //
    // A hand-down carries both: an LGA commander directing a ward writes
    // `to_ward` and their own `to_lga`. Granting on the LGA alone would then
    // put the incident on every ward commander's screen in that LGA, which is
    // the noise this filter exists to prevent. The LGA command that directed
    // it keeps the incident — they chose the ward, and the incident may sit
    // outside their own area — and the named ward has it from the rule above.
    //
    // Deliberately STRICTER than `alert_delegated_to_my_lga()`, which grants on
    // `to_lga` whatever else the entry says. That is the one shape where
    // stricter is right: the row is granted to a GROUP and this narrows it to
    // the member it names, rather than withholding something addressed to the
    // officer in front of it. Nothing is lost — the named ward, the LGA
    // command and HQ all have it.
    if (delegatedWard(alert) == null || officer.role.contains('LGA')) {
      return true;
    }
  }

  // 6. LGA command: their LGA.
  if (officer.role.contains('LGA')) {
    if (officer.geoLga == null || officer.geoLga == 'ALL') return true;
    return sameGeo(alertLga, officer.geoLga);
  }

  // 7. Ward command: their ward, or their LGA.
  if (officer.role.contains('WARD')) {
    if (officer.geoWard == null || officer.geoWard == 'ALL') return true;
    return alertWard == null ||
        sameGeo(alertWard, officer.geoWard) ||
        sameGeo(alertLga, officer.geoLga);
  }

  // 8. Polling-unit and beat responders: their PU, ward or LGA.
  if (sameGeo(alertPu, officer.geoPu)) return true;
  if (sameGeo(alertWard, officer.geoWard)) return true;
  if (sameGeo(alertLga, officer.geoLga)) return true;

  // No rule matched. Not shown, rather than delivering the whole state to every
  // field device.
  return false;
}

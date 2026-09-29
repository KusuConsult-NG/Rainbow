/// Which officers a commander may actually send to an incident.
///
/// ## What was wrong
///
/// `_DispatchDialog._loadResponders()` selected every profile and kept
/// `role != 'CITIZEN'`. It even asked for `geo_lga` and `geo_ward` in the same
/// query and then never looked at them.
///
/// So a ward commander in Jos North was offered — and could dispatch — an
/// officer posted in Mangu, 80km away and in nobody's chain of command. That
/// officer would receive a dispatch for an incident their own commander knew
/// nothing about, and the commander who does own them would never learn they
/// had been sent.
///
/// The console's picker had the identical defect. This is the same rule, in
/// Dart, deliberately kept the same shape as
/// `hq-dashboard-next/src/lib/assignable-responders.ts` and as
/// `alert_in_my_area()` in 20261006000000_alerts_scoped_to_posting.sql — that
/// last one decides which incidents a posting reaches, these decide which
/// officers it reaches. An officer you may send is an officer whose work you
/// may see.
///
/// Hiding a name is not access control; the database decides. But offering a
/// name that leads to a dispatch nobody downstream expects is its own defect.
library;

import 'package:rainbow_app/core/geo/geo_key.dart';

/// Compare roles the way the database does: trimmed, case-insensitively.
///
/// PLACE names go through [geoKey] instead, which additionally folds the two
/// spellings of the numbered Mangu wards — this app files an incident in
/// 'GINDIRI  I' while an officer is posted to 'GINDIRI  1'. Roles have no such
/// divergence and are left on the simpler rule.
String? _norm(Object? value) {
  final v = (value as String?)?.trim().toUpperCase();
  return (v == null || v.isEmpty) ? null : v;
}

/// Whether this account commands the whole state.
///
/// Narrower than the app's general "is command" idea, which includes LGA.
bool commandsWholeState(String? role) {
  final r = _norm(role) ?? '';
  return r == 'HQ_COMMAND' || r == 'HQ_OFFICER' || r == 'ADMIN';
}

/// Whether [officer] is inside [commander]'s command.
///
/// A commander with no posting reaches nobody. `profiles.geo_lga` is
/// self-writable — only `role` is guarded by the privilege-escalation trigger
/// — so an empty posting must be the weakest, never a way to reach the state.
bool isUnderCommand(
  Map<String, dynamic> officer,
  Map<String, dynamic> commander,
) {
  if (commandsWholeState(commander['role'] as String?)) return true;

  final myLga = geoKey(commander['geo_lga']);
  if (myLga == null) return false;
  if (geoKey(officer['geo_lga']) != myLga) return false;

  final role = _norm(commander['role']) ?? '';

  if (role.startsWith('WARD')) {
    final myWard = geoKey(commander['geo_ward']);
    return myWard != null && geoKey(officer['geo_ward']) == myWard;
  }

  // A polling-unit officer IS the field unit, not a dispatcher.
  // `canDispatchFrom` already refuses them the control; this makes the list
  // agree with it rather than offering names behind a button they do not have.
  if (role.startsWith('UNIT') || role.startsWith('POLLING')) return false;

  // LGA command, and anything else with a posting: their LGA.
  return true;
}

/// The officers this commander may send, from every profile loaded.
///
/// Citizens are never assignable, and neither is the dispatcher themselves:
/// self-dispatch is what ENGAGE is for, and offering it here produced an
/// incident assigned to the person who assigned it.
List<Map<String, dynamic>> assignableResponders(
  List<Map<String, dynamic>> officers,
  Map<String, dynamic> commander,
) {
  final myId = commander['id'] as String?;
  return officers.where((o) {
    final role = _norm(o['role']);
    if (role == null || role == 'CITIZEN') return false;
    if (myId != null && o['id'] == myId) return false;
    return isUnderCommand(o, commander);
  }).toList();
}

/// What to say when the list is empty.
///
/// An empty picker with no explanation reads as "the app is broken" during an
/// emergency, and the two causes need different actions: nobody is posted to
/// this command, or this account has no posting and so commands nobody.
String emptyRosterReason(Map<String, dynamic> commander) {
  if (commandsWholeState(commander['role'] as String?)) {
    return 'No officers are registered.';
  }
  final lga = geoKey(commander['geo_lga']);
  if (lga == null) {
    return 'Your account has no posting, so it commands no officers. '
        'Ask HQ to set your LGA.';
  }
  final role = _norm(commander['role']) ?? '';
  final where = role.startsWith('WARD')
      ? (geoKey(commander['geo_ward']) ?? lga)
      : lga;
  return 'No officers are posted to $where. Escalate to have one sent.';
}

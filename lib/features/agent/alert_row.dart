/// Reading an alert row the way the database actually returns it.
///
/// An alert row reaches these screens straight from PostgREST, so every key on
/// it is the column name: snake_case, always. Three places in the agent
/// dashboard read `alert['assignedToUid']` instead — the camelCase field name
/// from `AlertModel`, which is a *local* Dart model that never touches these
/// maps. That key is never present, so every one of those reads was a constant
/// `null`, and each comparison against it a constant `false`.
///
/// What that cost, concretely:
///
///   * The visibility filter opens with "if this alert is assigned to me, show
///     it" — the one rule that lets HQ hand an incident to a specific officer
///     outside their tier. It could never fire. So HQ overriding the chain and
///     assigning an alert to a polling-unit officer produced a mission that
///     officer could not see, which is precisely the case the override exists
///     for.
///   * The tactical action sheet gates EN ROUTE, ON SITE, RESOLVE MISSION,
///     MISSION INTEL and SECURE CHAT on `isAssignedToMe`. With it stuck at
///     false the sheet showed a generic DEPLOY button forever: an officer who
///     had accepted a mission could not advance or resolve it from the feed.
///
/// One function, so there is one answer. It reads the real column and keeps
/// tolerating the camelCase key, because a map built from `AlertModel.toJson()`
/// does carry it and passing one of those in should not silently stop working.
library;

/// The uuid of the responder this alert is assigned to, or null.
String? alertAssignee(Map<String, dynamic>? alert) {
  if (alert == null) return null;
  final v = alert['assigned_to'] ?? alert['assignedToUid'];
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Whether [uid] is the responder this alert is assigned to.
///
/// False when [uid] is null. A null uid means the session could not be read,
/// and "we do not know who you are" must never resolve to "this is yours" —
/// with `null == null` it did, for every unassigned alert, which waved the row
/// past all the tier scoping below it.
bool alertIsAssignedTo(Map<String, dynamic>? alert, String? uid) {
  if (uid == null || uid.isEmpty) return false;
  return alertAssignee(alert) == uid;
}

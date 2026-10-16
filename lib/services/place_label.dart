/// Places and postings as they read on a screen somebody acts on.
///
/// ## The defect this closes
///
/// `AlertService` goes to deliberate lengths NOT to guess where an incident
/// happened. Its own comment:
///
/// > The reporter's profile is deliberately NOT a fallback here. Filing an
/// > incident against the address someone registered at is how a report from
/// > Mangu is routed to a unit in Jos, and it would be indistinguishable
/// > afterwards from a measured position.
///
/// and when the coordinates do not resolve to a Plateau LGA it logs
/// "submitting without jurisdiction rather than guessing one" and writes NULL.
/// The responder feed filter agrees: an alert with no `geo_lga` reaches
/// everybody, because an unknown place must fail open.
///
/// The screen in between invented one anyway:
///
/// ```dart
/// '${alert['geo_lga'] ?? 'PLATEAU'} · '
/// '${alert['geo_ward'] ?? 'HQ'} · '
/// '${alert['geo_pu'] ?? 'UNIT'}'
/// ```
///
/// So a responder deciding where to go read **PLATEAU · HQ · UNIT** for an
/// incident whose jurisdiction is unknown — three place names, none of them
/// measured, one of which reads as a headquarters. And `geo_pu` is null on
/// essentially every GPS-originated incident by design ("there is no polling
/// unit from coordinates, and there cannot be"), so almost every card in the
/// feed ended in a fabricated **· UNIT**.
///
/// The dispatch roster did the same to people:
///
/// ```dart
/// 'Role: ${r['role'] ?? 'RESPONDER'} · ${r['geo_lga'] ?? 'JOS'}'
/// ```
///
/// `JOS` is not an LGA this system has. The seventeen are JOS NORTH, JOS SOUTH,
/// JOS EAST and fourteen others, and T-16 is the finding about invented
/// geography — "rows that look right and behave wrong". A statewide commander
/// reaches officers regardless of posting (`assignableResponders` returns true
/// for them before it compares LGAs), so the account that dispatches across all
/// seventeen LGAs was the one shown a place that exists in none of them.
///
/// ## The rule
///
/// Show what is known. Say so when nothing is. Never name a place, an agency or
/// a rank that was not recorded — on a screen where somebody acts on it, an
/// invented value is worse than a blank, because a blank is obviously a blank.
library;

/// The segments that are actually recorded, joined; `whenNone` when there are
/// none.
///
/// A segment counts as recorded when it is a non-blank string. `null`, `''` and
/// whitespace are all "not recorded" — a column can hold any of the three and
/// they mean the same thing to a reader.
String knownSegments(
  Iterable<Object?> segments, {
  required String whenNone,
  String separator = ' · ',
}) {
  final known = segments
      .map((s) => s?.toString().trim() ?? '')
      .where((s) => s.isNotEmpty)
      .toList();
  return known.isEmpty ? whenNone : known.join(separator);
}

/// Where an incident is, for a responder's card.
///
/// The polling unit is usually absent and that is not a fault, so a missing
/// segment is DROPPED rather than filled: `JOS NORTH · NARAGUTA`, not
/// `JOS NORTH · NARAGUTA · UNIT`.
///
/// When none of the three is recorded the card says so. The position itself is
/// not lost by this — the coordinates are what the map plots, and they are
/// measured. It is the jurisdiction that is unknown, and that is what this line
/// is about.
String incidentPlace(Map<String, dynamic> alert) => knownSegments(
      [alert['geo_lga'], alert['geo_ward'], alert['geo_pu']],
      whenNone: 'JURISDICTION NOT RESOLVED',
    );

/// A responder's posting, for the list a commander picks from.
///
/// Role and LGA are reported separately, because a row can have one without the
/// other and conflating them is how `JOS` came to stand for "we do not know".
String responderPosting(Map<String, dynamic> officer) {
  final role = knownSegments([officer['role']], whenNone: 'ROLE NOT SET');
  final lga = knownSegments([officer['geo_lga']], whenNone: 'NO LGA RECORDED');
  return 'Role: $role · $lga';
}

/// Attaching evidence to an incident.
///
/// ## Why this is a module and not three copies of five lines
///
/// Three places appended to `alerts.media_urls`, and every one of them did it
/// the same wrong way: read the array, add to the copy, write the whole thing
/// back. Read-modify-write over a network is lost-update by construction, so
/// two uploads that overlapped erased each other — while the screen said
/// "Evidence captured and sent to HQ".
///
/// The overlap was not hypothetical. The offline flush uploads a whole queue in
/// a loop; the duress screen fires each upload with `unawaited(...)` and does
/// not wait; a responder can photograph a scene twice in a few seconds.
///
/// The append is now one locked statement in the database
/// (`append_alert_media`, migration 20261010000000). This is the only thing that
/// calls it, so there is one place for the rule and one place to test.
library;

import 'package:flutter/foundation.dart';

import 'package:rainbow_app/core/supabase/supabase_config.dart';

/// What happened when evidence was offered to an incident.
enum AttachOutcome {
  /// At least one URL is now on the incident.
  attached,

  /// The call succeeded and added nothing new — every URL was already there.
  /// A retry of an upload that had in fact worked lands here, and it is not a
  /// failure.
  alreadyThere,

  /// The database returned NO ROW: row-level security refused this account, or
  /// the incident does not exist.
  ///
  /// Kept distinct from [alreadyThere] on purpose. "You may not attach to this"
  /// and "there was nothing new to add" are different facts and call for
  /// different words on an operator's screen — and collapsing them is exactly
  /// how a refusal gets reported as a success.
  refused,

  /// The call itself failed — no network, a transport error, a timeout. The
  /// evidence still exists locally and the caller should hold it.
  failed,
}

/// The result of one attach: what happened, and how many files the incident
/// carries now.
@immutable
class AttachResult {
  const AttachResult(this.outcome, {this.added = 0, this.total = 0, this.error});

  final AttachOutcome outcome;

  /// How many URLs this call actually added.
  final int added;

  /// How many the incident carries in total afterwards.
  final int total;

  /// The transport error, when [outcome] is [AttachOutcome.failed].
  final String? error;

  /// Whether the evidence is now on the incident — either because this call
  /// put it there or because it was already there.
  ///
  /// This is the question a caller holding a local file should ask: may I stop
  /// holding it? A refusal and a transport failure both mean NO, for different
  /// reasons, and both keep the file.
  bool get isOnTheIncident =>
      outcome == AttachOutcome.attached || outcome == AttachOutcome.alreadyThere;
}

/// Attaching evidence URLs to an incident, atomically.
class AlertMedia {
  const AlertMedia._();

  /// Append [urls] to `alerts.media_urls` for [alertId].
  ///
  /// Duplicates are dropped by the database and blank strings are discarded, so
  /// a caller does not need to filter first — but an empty list is short-
  /// circuited here rather than spending a round trip on nothing.
  static Future<AttachResult> append(
    String alertId,
    List<String> urls,
  ) async {
    final clean = urls
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (clean.isEmpty) {
      return const AttachResult(AttachOutcome.alreadyThere);
    }

    try {
      final rows = await SupabaseConfig.client.rpc<dynamic>(
        'append_alert_media',
        params: {'p_alert_id': alertId, 'p_urls': clean},
      );

      // A SETOF function comes back as a list. NO ROW means the statement
      // matched nothing — RLS refused, or the incident is gone. Reading that as
      // success is the defect this whole module exists to prevent, so it is the
      // first thing checked.
      final list = rows is List
          ? rows
          : (rows == null ? const <dynamic>[] : <dynamic>[rows]);
      if (list.isEmpty) {
        return const AttachResult(AttachOutcome.refused);
      }

      final row = list.first as Map<String, dynamic>;
      final added = (row['added'] as num?)?.toInt() ?? 0;
      final total = (row['total'] as num?)?.toInt() ?? 0;
      return AttachResult(
        added > 0 ? AttachOutcome.attached : AttachOutcome.alreadyThere,
        added: added,
        total: total,
      );
      // ignore: avoid_catches_without_on_clauses, any transport failure is the
      // same answer to the caller: the file is still yours to hold.
    } catch (e) {
      debugPrint('[ALERT_MEDIA] append failed for $alertId: $e');
      return AttachResult(AttachOutcome.failed, error: e.toString());
    }
  }
}

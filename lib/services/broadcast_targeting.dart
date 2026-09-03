/// Who a mass broadcast actually reaches.
///
/// This was inline inside a stream `.map()` and only ever checked audience and
/// expiry — reading `target_type`, which the HQ console never wrote. The console
/// wrote `target_audience`, so every advisory arrived with `target_type` at its
/// 'ALL' default and went to everyone, while the console told the operator it
/// had gone to responders only. Geographic scope was not checked at all, so an
/// advisory for one ward went to the whole state.
///
/// It is a pure function of the row and the recipient, so it lives here and is
/// tested directly. See test/broadcast_targeting_test.dart.
library;

/// The recipient, as far as delivery is concerned.
class BroadcastRecipient {
  /// Everything delivery needs to know about one user.
  const BroadcastRecipient({
    required this.isResponder,
    this.geoLga,
    this.geoWard,
    this.geoPu,
  });

  /// True for field responders; false for citizens. Decides AGENTS vs CITIZENS.
  final bool isResponder;

  /// The user's own geography, from their profile. Any of these may be null —
  /// see [broadcastReaches] for why that delivers rather than withholds.
  final String? geoLga;

  /// The user's ward.
  final String? geoWard;

  /// The user's polling unit.
  final String? geoPu;
}

/// A scope value that means "no restriction".
bool _unscoped(String? value) {
  final v = (value ?? '').trim();
  return v.isEmpty || v.toUpperCase() == 'ALL';
}

/// Place names are entered by hand and are not consistent — "Jos North",
/// "JOS NORTH", "Jos North LGA" are one place. Matching is therefore loose in
/// both directions, the same rule the HQ board already uses to filter alerts.
///
/// Under-matching here is the expensive direction: it drops a warning for
/// somebody who is in the affected area.
bool _placeMatches(String scope, String? recipientValue) {
  final r = (recipientValue ?? '').trim().toLowerCase();
  // The recipient has no place recorded. Deliver anyway — see [broadcastReaches].
  if (r.isEmpty) return true;
  final s = scope.trim().toLowerCase();
  return r == s || r.contains(s) || s.contains(r);
}

/// The audience a row is addressed to, canonical column first.
///
/// `target_audience` is what the console writes and what the model has always
/// declared. `target_type` is the original schema's name and is still present on
/// rows written before the reconciliation, so it is read as a fallback.
String broadcastAudience(Map<String, dynamic> row) {
  final canonical = (row['target_audience'] as String?)?.trim();
  if (canonical != null && canonical.isNotEmpty) return canonical.toUpperCase();
  final legacy = (row['target_type'] as String?)?.trim();
  if (legacy != null && legacy.isNotEmpty) return legacy.toUpperCase();
  return 'ALL';
}

/// Whether [row] should be shown to [to] at [now].
///
/// Deliberately fails OPEN on missing recipient geography: a citizen whose
/// profile has no LGA recorded still receives a scoped advisory. Showing a
/// warning to somebody outside the affected area costs them a notification;
/// withholding one from somebody inside it costs more than that. Every other
/// condition fails closed.
bool broadcastReaches(
  Map<String, dynamic> row,
  BroadcastRecipient to, {
  DateTime? now,
}) {
  // Withdrawn by HQ.
  if (row['is_active'] == false) return false;

  // Expired. A row with no expiry stands until it is deactivated.
  final rawExpiry = row['expires_at'] as String?;
  if (rawExpiry != null && rawExpiry.isNotEmpty) {
    final expiresAt = DateTime.tryParse(rawExpiry);
    if (expiresAt != null && !expiresAt.isAfter(now ?? DateTime.now())) {
      return false;
    }
  }

  // An audience nobody recognises is treated as ALL rather than dropped: an
  // advisory that reaches too many people is recoverable; one that reaches
  // nobody because of a typo in a dropdown is not.
  final audience = broadcastAudience(row);
  if (audience == 'CITIZENS' && to.isResponder) return false;
  if ((audience == 'AGENTS' || audience == 'RESPONDERS') && !to.isResponder) {
    return false;
  }

  final lga = row['target_lga'] as String?;
  if (!_unscoped(lga) && !_placeMatches(lga!, to.geoLga)) return false;

  final ward = row['target_ward'] as String?;
  if (!_unscoped(ward) && !_placeMatches(ward!, to.geoWard)) return false;

  final pu = row['target_pu'] as String?;
  if (!_unscoped(pu) && !_placeMatches(pu!, to.geoPu)) return false;

  return true;
}

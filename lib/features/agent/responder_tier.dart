import 'package:rainbow_app/providers/auth_provider.dart';

/// The tier label an officer acts AS, and the tier an escalation goes TO.
///
/// These were computed twice inside `agent_dashboard_screen.dart`, in two
/// places, with two different fallbacks:
///
///   `_assignedTier`        default -> 'UNIT'
///   the alert card's local default -> 'LGA'
///
/// Both defaults caught the same users: HQ, whose tier was `unknown`, and a
/// plain RESPONDER, who has no tier at all. So one screen told the action
/// sheet an HQ commander was a UNIT and told the escalation dialog the same
/// commander was an LGA — and since the escalation ladder is
/// UNIT -> WARD -> LGA -> HQ, HQ escalated to WARD down one path and to
/// ITSELF down the other.
///
/// The guard that was supposed to stop that, `assignedTier != 'HQ'`, could
/// never fire, because neither computation could ever return 'HQ'.
///
/// One function now, and HQ has its own tier, so both callers agree and the
/// guard works.
String assignedTierLabel(ResponderTier tier) {
  switch (tier) {
    case ResponderTier.pu:
      return 'UNIT';
    case ResponderTier.ward:
      return 'WARD';
    case ResponderTier.lga:
      return 'LGA';
    case ResponderTier.hq:
      return 'HQ';
    case ResponderTier.unknown:
      // A responder outside the chain acts at the lowest tier. That is a
      // deliberate choice rather than a fallback: it is the only tier whose
      // escalation goes UP to somebody, and an officer who cannot escalate is
      // worse than one who escalates to their ward.
      return 'UNIT';
  }
}

/// Where an escalation from [tier] goes. `null` at the top: HQ has nobody to
/// escalate to, and offering the control anyway is what made HQ escalate to
/// itself.
String? escalationTargetFor(String assignedTier) {
  switch (assignedTier) {
    case 'UNIT':
      return 'WARD';
    case 'WARD':
      return 'LGA';
    case 'LGA':
      return 'HQ';
    case 'HQ':
      return null;
    default:
      return 'HQ';
  }
}

/// Rank of a tier in the chain, bottom to top. UNIT=0 ... HQ=3.
int tierRank(String tier) {
  switch (tier.toUpperCase()) {
    case 'UNIT':
      return 0;
    case 'WARD':
      return 1;
    case 'LGA':
      return 2;
    case 'HQ':
      return 3;
    default:
      return 0;
  }
}

/// Can an officer at [viewerTier] see an alert owned by [alertTier]?
///
/// The rule is **owner tier and everyone above**. A PU alert is actionable by
/// that PU and visible to its ward, its LGA and HQ; a ward alert is not
/// visible to the units below it.
///
/// Oversight downward, privacy upward. A commander who cannot see what their
/// units are handling cannot command; a unit that can see every other unit's
/// traffic is back to the fail-open noise this replaces.
///
/// HQ sees everything, which is what makes "HQ overrides where the chain is
/// not accessible" possible at all.
bool tierCanSee({required String viewerTier, required String? alertTier}) {
  // An alert with no tier is visible to everyone. That is deliberate: an
  // unowned emergency must not be invisible while the routing that should
  // have owned it is being fixed. Fail OPEN on the alert, never on the
  // viewer.
  if (alertTier == null || alertTier.trim().isEmpty) return true;
  return tierRank(viewerTier) >= tierRank(alertTier);
}

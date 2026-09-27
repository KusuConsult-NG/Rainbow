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

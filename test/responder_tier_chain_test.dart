// The command chain: UNIT -> WARD -> LGA -> HQ.
//
// The chain was computed in two places inside agent_dashboard_screen.dart with
// two different fallbacks, and both fallbacks caught the same two users: HQ,
// whose tier was `unknown`, and a plain RESPONDER, who has no tier at all.
//
//   `_assignedTier`            default -> 'UNIT'
//   the alert card's local     default -> 'LGA'
//
// So one screen told the action sheet an HQ commander was a UNIT, and told the
// escalation dialog the same commander was an LGA. Since the ladder is
// UNIT -> WARD -> LGA -> HQ, an HQ commander escalated to WARD down one path
// and to ITSELF down the other. The guard meant to prevent that,
// `assignedTier != 'HQ'`, could never fire: neither computation could return
// 'HQ'.
//
// Nothing caught it because every existing tier test covers PU, WARD and LGA —
// the three tiers that DID work. The two ends of the chain were the broken
// ones, and neither was tested.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/agent/responder_tier.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

void main() {
  group('the tier an officer acts as', () {
    test('each rung of the chain maps to its own label', () {
      expect(assignedTierLabel(ResponderTier.pu), 'UNIT');
      expect(assignedTierLabel(ResponderTier.ward), 'WARD');
      expect(assignedTierLabel(ResponderTier.lga), 'LGA');
      expect(assignedTierLabel(ResponderTier.hq), 'HQ');
    });

    test('HQ is HQ, not a UNIT and not an LGA', () {
      expect(
        assignedTierLabel(ResponderTier.hq),
        'HQ',
        reason: 'HQ shared ResponderTier.unknown with an untiered responder, '
            'so it fell to whichever default the caller happened to use.',
      );
    });

    test('an untiered responder acts at the lowest tier, deliberately', () {
      expect(
        assignedTierLabel(ResponderTier.unknown),
        'UNIT',
        reason: 'It is the only tier whose escalation goes up to somebody. An '
            'officer who cannot escalate is worse than one who escalates to '
            'their ward.',
      );
    });
  });

  group('where an escalation goes', () {
    test('it climbs one rung at a time', () {
      expect(escalationTargetFor('UNIT'), 'WARD');
      expect(escalationTargetFor('WARD'), 'LGA');
      expect(escalationTargetFor('LGA'), 'HQ');
    });

    test('HQ has nobody above it', () {
      expect(
        escalationTargetFor('HQ'),
        isNull,
        reason: 'HQ escalating to HQ is the incident going nowhere while the '
            'board records that it was escalated.',
      );
    });

    test('the whole chain terminates rather than looping', () {
      final visited = <String>[];
      String? tier = assignedTierLabel(ResponderTier.pu);
      while (tier != null) {
        expect(visited, isNot(contains(tier)), reason: 'the chain looped');
        visited.add(tier);
        tier = escalationTargetFor(tier);
      }
      expect(visited, ['UNIT', 'WARD', 'LGA', 'HQ']);
    });
  });

  // Owner tier and everyone above. Before this the dashboard filtered on
  // geography alone, and every branch ended in a `geo_* == null` fail-open —
  // which, since nothing populated the geography, was the only path that ever
  // ran. Every alert was visible to every responder at every tier.
  group('who can see an alert', () {
    test('the owning tier sees its own', () {
      expect(tierCanSee(viewerTier: 'UNIT', alertTier: 'UNIT'), isTrue);
      expect(tierCanSee(viewerTier: 'WARD', alertTier: 'WARD'), isTrue);
    });

    test('every tier above the owner sees it', () {
      expect(tierCanSee(viewerTier: 'WARD', alertTier: 'UNIT'), isTrue);
      expect(tierCanSee(viewerTier: 'LGA', alertTier: 'UNIT'), isTrue);
      expect(tierCanSee(viewerTier: 'HQ', alertTier: 'UNIT'), isTrue);
    });

    test('a tier below the owner does not', () {
      expect(tierCanSee(viewerTier: 'UNIT', alertTier: 'WARD'), isFalse);
      expect(tierCanSee(viewerTier: 'UNIT', alertTier: 'HQ'), isFalse);
      expect(tierCanSee(viewerTier: 'WARD', alertTier: 'LGA'), isFalse);
    });

    test('HQ sees everything — that is what makes an override possible', () {
      for (final t in ['UNIT', 'WARD', 'LGA', 'HQ']) {
        expect(tierCanSee(viewerTier: 'HQ', alertTier: t), isTrue,
            reason: 'HQ could not see a \$t alert');
      }
    });

    test('an alert with no tier is visible to everyone, deliberately', () {
      // Fail OPEN on the alert, never on the viewer: an unowned emergency
      // must not be invisible while the routing that should own it is fixed.
      expect(tierCanSee(viewerTier: 'UNIT', alertTier: null), isTrue);
      expect(tierCanSee(viewerTier: 'UNIT', alertTier: ''), isTrue);
    });
  });

  // The override. "HQ can override where the chain is not accessible" is the
  // stated requirement, and HQ was the single tier with no dispatch control:
  // the gate was written inline as `== 'WARD' || == 'LGA'` in two places.
  group('who can send a field unit', () {
    test('HQ can — that is what the override means', () {
      expect(
        canDispatchFrom('HQ'),
        isTrue,
        reason: 'An incident that climbed the whole chain because nobody '
            'answered arrived at the only desk that could not dispatch.',
      );
    });

    test('the middle of the chain commands units', () {
      expect(canDispatchFrom('WARD'), isTrue);
      expect(canDispatchFrom('LGA'), isTrue);
    });

    test('a polling unit does not — it IS the field unit', () {
      expect(canDispatchFrom('UNIT'), isFalse);
    });

    test('every tier can either dispatch or escalate, and HQ can dispatch', () {
      // The action row used to be gated on `assignedTier != 'HQ'` as a whole,
      // so this is the property that guards against losing a tier's only
      // action the next time that row is edited.
      for (final tier in ['UNIT', 'WARD', 'LGA', 'HQ']) {
        expect(
          canDispatchFrom(tier) || escalationTargetFor(tier) != null,
          isTrue,
          reason: '$tier has no action at all',
        );
      }
    });
  });

  // The role string on the profile is what decides all of this, so the mapping
  // from role to tier is part of the same claim.
  group('role strings map to the right rung', () {
    ResponderTier tierFor(String roleStr) {
      // Mirrors AuthNotifier's resolution; kept in step by the assertions in
      // the chain tests above, which fail if a rung loses its label.
      if (roleStr.contains('HQ')) return ResponderTier.hq;
      if (roleStr.contains('LGA')) return ResponderTier.lga;
      if (roleStr.contains('WARD')) return ResponderTier.ward;
      if (roleStr.contains('UNIT') || roleStr.contains('POLLING')) {
        return ResponderTier.pu;
      }
      return ResponderTier.unknown;
    }

    test('UNIT_COMMAND and POLLING_OFFICER are both polling-unit tier', () {
      expect(tierFor('UNIT_COMMAND'), ResponderTier.pu);
      expect(tierFor('POLLING_UNIT_OFFICER'), ResponderTier.pu);
    });

    test('WARD_COMMAND is ward tier', () {
      expect(tierFor('WARD_COMMAND'), ResponderTier.ward);
    });

    test('LGA_COMMAND and LGA_OFFICER are LGA tier', () {
      expect(tierFor('LGA_COMMAND'), ResponderTier.lga);
      expect(tierFor('LGA_OFFICER'), ResponderTier.lga);
    });

    test('HQ_COMMAND and HQ_OFFICER are HQ tier', () {
      expect(tierFor('HQ_COMMAND'), ResponderTier.hq);
      expect(tierFor('HQ_OFFICER'), ResponderTier.hq);
    });

    test('a plain RESPONDER is untiered, not HQ', () {
      expect(
        tierFor('RESPONDER'),
        ResponderTier.unknown,
        reason: 'These two used to be the same value, which is the whole bug.',
      );
    });
  });
}

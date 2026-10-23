// A rung must never be decided by whether one string happens to contain
// another.
//
// The production project's 22 staff accounts carry a vocabulary this
// repository never had: STATE_COMMANDER / LGA_COMMANDER / WARD_COMMANDER /
// POLLING_UNIT_OFFICER. The tier was chosen by four substring tests, so three
// of those four worked by accident of spelling and the fourth — the HQ rung —
// fell through to `unknown`, which renders as 'UNIT'. Every HQ duty officer was
// shown a polling unit's board for one ward while a CRITICAL SOS and a building
// fire sat in another, with no error anywhere.
//
// See E2E_AUDIT_REPORT.md T-85.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/agent/responder_tier.dart';
import 'package:rainbow_app/providers/auth_provider.dart';

void main() {
  group('the vocabulary production actually uses', () {
    test('STATE_COMMANDER is HQ, not the bottom of the chain', () {
      // The whole bug in one assertion. 'STATE_COMMANDER' contains none of
      // HQ, LGA, WARD, UNIT or POLLING.
      expect(tierForStaffRole('STATE_COMMANDER'), ResponderTier.hq);
      expect(assignedTierLabel(tierForStaffRole('STATE_COMMANDER')!), 'HQ');
    });

    test('and the other three rungs it uses', () {
      expect(tierForStaffRole('LGA_COMMANDER'), ResponderTier.lga);
      expect(tierForStaffRole('WARD_COMMANDER'), ResponderTier.ward);
      expect(tierForStaffRole('POLLING_UNIT_OFFICER'), ResponderTier.pu);
    });
  });

  group('the vocabulary this repository is written against', () {
    test('maps to the same four rungs', () {
      expect(tierForStaffRole('HQ_COMMAND'), ResponderTier.hq);
      expect(tierForStaffRole('LGA_COMMAND'), ResponderTier.lga);
      expect(tierForStaffRole('WARD_COMMAND'), ResponderTier.ward);
      expect(tierForStaffRole('UNIT_COMMAND'), ResponderTier.pu);
    });
  });

  group('staff who are deliberately outside the chain', () {
    test('have no rung, which is not the same as being unrecognised', () {
      for (final role in ['RESPONDER', 'POLICE_LIAISON', 'ARMY_LIAISON']) {
        expect(tierForStaffRole(role), ResponderTier.unknown, reason: role);
      }
    });
  });

  group('a role no release knows', () {
    test('is null — never silently the bottom of the chain', () {
      // The regression guard. Before the map, anything unmatched became
      // `unknown` and was rendered as 'UNIT'. Null makes the caller decide,
      // and the caller logs it.
      expect(tierForStaffRole('DEPUTY_INSPECTOR_GENERAL'), isNull);
      expect(tierForStaffRole('ZONAL_COORDINATOR'), isNull);
      expect(tierForStaffRole(''), isNull);
    });

    test('but a spelling that clearly names a rung is still guessed', () {
      // Last resort, kept so a vocabulary nobody added still gets a rung
      // rather than nothing. It logs that it fired.
      expect(tierForStaffRole('HQ_DUTY_OFFICER'), ResponderTier.hq);
      expect(tierForStaffRole('STATE_DUTY_OFFICER'), ResponderTier.hq);
      expect(tierForStaffRole('LGA_DESK'), ResponderTier.lga);
    });
  });

  test('case and whitespace do not decide a rung either', () {
    expect(tierForStaffRole('  state_commander  '), ResponderTier.hq);
    expect(tierForStaffRole('Hq_Command'), ResponderTier.hq);
  });

  test('every rung in the map renders a label the escalation ladder knows', () {
    // A tier that cannot be labelled is a tier the action sheet and the
    // escalation dialog will disagree about, which is the defect
    // responder_tier.dart was created for.
    for (final entry in staffRoleTiers.entries) {
      final label = assignedTierLabel(entry.value);
      expect(['UNIT', 'WARD', 'LGA', 'HQ'], contains(label),
          reason: '${entry.key} -> ${entry.value.name} -> $label');
    }
  });
}

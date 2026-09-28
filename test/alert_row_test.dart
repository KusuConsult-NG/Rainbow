// Reading the assignee off an alert row.
//
// Three places in the agent dashboard read `alert['assignedToUid']`. That is
// the camelCase field name from `AlertModel`; the maps in question come from
// PostgREST, where the key is the column, `assigned_to`. So all three reads
// were a constant null:
//
//   * the visibility filter's "if it is assigned to me, show it" rule — the one
//     that makes an HQ override to a lower-tier officer visible to them — could
//     never fire;
//   * the tactical action sheet's `isAssignedToMe` was permanently false, so EN
//     ROUTE, ON SITE, RESOLVE MISSION, MISSION INTEL and SECURE CHAT never
//     appeared and the sheet offered a generic DEPLOY forever.
//
// These tests pin the row shape the database actually returns, because that is
// what the bug was about — not the logic on top of it.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/agent/alert_row.dart';

void main() {
  const me = '11111111-1111-1111-1111-111111111111';
  const someoneElse = '22222222-2222-2222-2222-222222222222';

  group('reading the assignee', () {
    test('reads the column the database returns', () {
      expect(alertAssignee({'assigned_to': me}), me);
    });

    test('still reads the camelCase key a local model produces', () {
      // AlertModel.toJson() carries `assignedToUid`. Passing one of those maps
      // in should not silently stop working.
      expect(alertAssignee({'assignedToUid': me}), me);
    });

    test('the column wins when a map somehow carries both', () {
      expect(
        alertAssignee({'assigned_to': me, 'assignedToUid': someoneElse}),
        me,
      );
    });

    test('an unassigned alert has no assignee', () {
      expect(alertAssignee({'assigned_to': null}), isNull);
      expect(alertAssignee(const <String, dynamic>{}), isNull);
      expect(alertAssignee(null), isNull);
    });

    test('an empty string is not an assignee', () {
      // `assigned_to` is a uuid column so this cannot come from the database,
      // but a client that once wrote a tier name into it could leave ''.
      expect(alertAssignee({'assigned_to': '   '}), isNull);
    });
  });

  group('is this alert mine', () {
    test('yes, when the column names me', () {
      expect(alertIsAssignedTo({'assigned_to': me}, me), isTrue);
    });

    test('no, when it names somebody else', () {
      expect(alertIsAssignedTo({'assigned_to': someoneElse}, me), isFalse);
    });

    test('no, when nobody has it', () {
      expect(alertIsAssignedTo({'assigned_to': null}, me), isFalse);
    });

    test('an unknown viewer owns nothing, including unassigned alerts', () {
      // This is the bug the guard exists for. With a null uid and a null
      // assignee, `null == null` is true — every unassigned alert would be
      // "mine" and would bypass all the tier scoping below. A session that
      // cannot be read must not become a session that sees everything.
      expect(alertIsAssignedTo({'assigned_to': null}, null), isFalse);
      expect(alertIsAssignedTo(const <String, dynamic>{}, null), isFalse);
      expect(alertIsAssignedTo({'assigned_to': me}, null), isFalse);
      expect(alertIsAssignedTo({'assigned_to': null}, ''), isFalse);
    });

    test('the phantom key no longer decides it', () {
      // The regression, stated as such: a row that carries only `assigned_to`
      // used to answer false here, which is what broke the override and the
      // mission lifecycle.
      final rowFromDatabase = <String, dynamic>{
        'id': 'abc',
        'status': 'ACKNOWLEDGED',
        'assigned_to': me,
        'assigned_tier': 'HQ',
      };
      expect(
        alertIsAssignedTo(rowFromDatabase, me),
        isTrue,
        reason: 'HQ assigning an incident to a polling-unit officer produced a '
            'mission that officer could not see.',
      );
    });
  });
}

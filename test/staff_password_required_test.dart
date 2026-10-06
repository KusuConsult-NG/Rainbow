// A staff member must type a password. There was no password field.
//
// `signInWithAccessCode` read `AGENT_DEFAULT_PASS` out of the bundled `.env`
// and signed in as `<code>@operationrainbow.plateau.gov.ng` with it. Three
// facts together made that one published credential for every staff account:
//
//   * pubspec.yaml declares `.env` as a Flutter ASSET, so it ships verbatim
//     inside the APK and extracts with `unzip` (E2E_AUDIT_REPORT.md H-3);
//   * every officer shared the one password in it;
//   * the "access code" was only the email local-part — a USERNAME.
//
// So anybody holding the APK and any officer's code could sign in as that
// officer. Rotating the access codes would have changed the usernames and left
// the password published.
//
// The first test is the defect: a code alone must not authenticate anything.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/features/auth/login_screen.dart';
import 'package:rainbow_app/services/auth_service.dart';

/// Records what the screen asked for, and grants nothing.
class RecordingAuthService implements AuthService {
  final List<List<String>> badgeSignIns = [];
  final List<String> phoneRequests = [];

  @override
  Future<bool> signInWithBadge(String badgeOrEmail, String password) async {
    badgeSignIns.add([badgeOrEmail, password]);
    return false;
  }

  @override
  Future<bool> verifyPhoneNumber(String phone) async {
    phoneRequests.add(phone);
    return false;
  }

  @override
  String? get lastAuthError => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<RecordingAuthService> pumpLogin(WidgetTester tester) async {
  final auth = RecordingAuthService();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(auth)],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
  await tester.pump();
  return auth;
}

Future<void> tapAuthorize(WidgetTester tester) async {
  // The primary button carries different words per step, so find the button
  // rather than the label.
  await tester.tap(find.byType(ElevatedButton).first);
  await tester.pump();
}

void main() {
  testWidgets('an access code alone does NOT sign anybody in', (tester) async {
    final auth = await pumpLogin(tester);

    await tester.enterText(find.byType(TextField).first, 'PLT-0412');
    await tapAuthorize(tester);

    // The defect, as an assertion: before the fix this called
    // signInWithBadge('plt-0412@…', AGENT_DEFAULT_PASS) and a session was
    // created from a password that is in every copy of the APK.
    expect(auth.badgeSignIns, isEmpty,
        reason: 'a code with no password must not authenticate');

    // Instead the screen asks for one.
    expect(find.byKey(const ValueKey('staff_password_field')), findsOneWidget);
    expect(find.text('STAFF PASSWORD'), findsOneWidget);
  });

  testWidgets('the password is sent with the badge, and only then', (tester) async {
    final auth = await pumpLogin(tester);

    await tester.enterText(find.byType(TextField).first, 'PLT-0412');
    await tapAuthorize(tester);
    expect(auth.badgeSignIns, isEmpty);

    await tester.enterText(
        find.byKey(const ValueKey('staff_password_field')), 'a-real-password');
    await tapAuthorize(tester);

    expect(auth.badgeSignIns, hasLength(1));
    expect(auth.badgeSignIns.single, ['PLT-0412', 'a-real-password']);
  });

  testWidgets('an empty password does not submit', (tester) async {
    final auth = await pumpLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'PLT-0412');
    await tapAuthorize(tester);
    await tapAuthorize(tester); // press again with the field untouched
    expect(auth.badgeSignIns, isEmpty);
  });

  testWidgets('the password field is obscured and offers no suggestions',
      (tester) async {
    await pumpLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'PLT-0412');
    await tapAuthorize(tester);

    final field = tester.widget<TextField>(
        find.byKey(const ValueKey('staff_password_field')));
    // These handsets are passed between shifts.
    expect(field.obscureText, isTrue);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('a phone number still goes to the OTP path, not the badge path',
      (tester) async {
    final auth = await pumpLogin(tester);

    await tester.enterText(find.byType(TextField).first, '08031234567');
    await tapAuthorize(tester);

    expect(auth.phoneRequests, hasLength(1));
    expect(auth.badgeSignIns, isEmpty);
    // And no password is demanded of a citizen — they get a code by SMS.
    expect(find.byKey(const ValueKey('staff_password_field')), findsNothing);
  });

  testWidgets('going back clears the password and the identifier', (tester) async {
    final auth = await pumpLogin(tester);

    await tester.enterText(find.byType(TextField).first, 'PLT-0412');
    await tapAuthorize(tester);
    await tester.enterText(
        find.byKey(const ValueKey('staff_password_field')), 'typed-in-error');

    await tester.tap(find.text('BACK TO IDENTIFIER'));
    await tester.pump();

    // Back on the identifier step with nothing retained — a password left in a
    // controller is a password the next person on the handset submits.
    expect(find.byKey(const ValueKey('staff_password_field')), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'PLT-9999');
    await tapAuthorize(tester);
    await tester.enterText(
        find.byKey(const ValueKey('staff_password_field')), 'second-password');
    await tapAuthorize(tester);

    expect(auth.badgeSignIns.single, ['PLT-9999', 'second-password']);
  });

  testWidgets('a failure does not say which half was wrong', (tester) async {
    // "No such badge" would make this screen a roster of who works here.
    final auth = await pumpLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'PLT-0412');
    await tapAuthorize(tester);
    await tester.enterText(
        find.byKey(const ValueKey('staff_password_field')), 'wrong');
    await tapAuthorize(tester);

    expect(auth.badgeSignIns, hasLength(1));
    expect(find.textContaining('BADGE OR PASSWORD'), findsOneWidget);
  });
}

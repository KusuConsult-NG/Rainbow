// The part of the re-entry lock that cannot be a pure function: a clock, the
// app's lifecycle, and one bit of state the router reads.
//
// The decision itself lives in `lib/core/auth/reentry_lock.dart` and is tested
// there. What is tested here is the bookkeeping around it, which has two ways
// to fail silently — and both fail OPEN, leaving the app unlocked while
// appearing to work.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/providers/reentry_lock_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  // Who is signed in, as a knob a test can turn part-way through. The lock is
  // scoped to a session, so signing out and signing back in has to be
  // expressible here — it is the case that was broken.
  // A session key, not a person: the provider pairs the user id with the
  // sign-in time, so signing in again as the same person yields a new value.
  final whoIsSignedIn =
      StateProvider<String?>((ref) => 'citizen-1@2026-09-28T12:00:00Z');

  ProviderContainer containerWith({
    required bool signedIn,
    required bool emergency,
  }) {
    final container = ProviderContainer(
      overrides: <Override>[
        hasSessionProvider.overrideWithValue(signedIn),
        emergencyActiveProvider.overrideWithValue(emergency),
        sessionIdentityProvider
            .overrideWith((ref) => ref.watch(whoIsSignedIn)),
      ],
    );
    // The router holds a live subscription to the lock — `app_router.dart`
    // listens to it to drive redirects. Without one here, Riverpod is lazy: a
    // sign-out followed by a sign-in would be collapsed into a single rebuild
    // at the next read, which never sees the session go away and so is not the
    // sequence the app actually performs.
    container.listen(reentryLockProvider, (_, __) {});
    return container;
  }

  setUp(() {
    now = DateTime(2026, 9, 28, 12);
    ReentryLockNotifier.clock = () => now;
  });

  tearDown(() {
    ReentryLockNotifier.clock = DateTime.now;
  });

  test('locks after a long absence', () {
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);
    expect(container.read(reentryLockProvider), isFalse);

    container
        .read(reentryLockProvider.notifier)
        .simulateAway(const Duration(minutes: 30));

    expect(container.read(reentryLockProvider), isTrue);
  });

  test('does not lock after a moment away', () {
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);

    container
        .read(reentryLockProvider.notifier)
        .simulateAway(const Duration(seconds: 15));

    expect(container.read(reentryLockProvider), isFalse);
  });

  test('does not lock a running emergency, however long the absence', () {
    final container = containerWith(signedIn: true, emergency: true);
    addTearDown(container.dispose);

    container
        .read(reentryLockProvider.notifier)
        .simulateAway(const Duration(hours: 6));

    expect(container.read(reentryLockProvider), isFalse);
  });

  test('does not lock when nobody is signed in', () {
    final container = containerWith(signedIn: false, emergency: false);
    addTearDown(container.dispose);

    container
        .read(reentryLockProvider.notifier)
        .simulateAway(const Duration(days: 2));

    expect(container.read(reentryLockProvider), isFalse);
  });

  test('a second pause does not restart the clock', () {
    // `paused` can arrive more than once with no `resumed` between. Taking the
    // LAST one would reset the departure time on every repeat, and an app that
    // keeps being re-paused would stay unlocked indefinitely — a lock that
    // fails open and looks like it is working.
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);
    final notifier = container.read(reentryLockProvider.notifier);

    notifier.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 10));
    notifier
      ..didChangeAppLifecycleState(AppLifecycleState.paused)
      ..didChangeAppLifecycleState(AppLifecycleState.resumed);

    expect(container.read(reentryLockProvider), isTrue);
  });

  test('a notification shade is not leaving the app', () {
    // `inactive` fires for the shade, a permission dialog, an incoming call.
    // Treating it as a departure would start the clock constantly.
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);
    final notifier = container.read(reentryLockProvider.notifier);

    notifier.didChangeAppLifecycleState(AppLifecycleState.inactive);
    now = now.add(const Duration(hours: 1));
    notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);

    expect(container.read(reentryLockProvider), isFalse);
  });

  test('a resume with no prior departure locks nothing', () {
    // The first `resumed` of the process arrives without a matching `paused`.
    // Treating that as an absence of "now minus null" would lock the app at
    // launch, every launch.
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);

    container
        .read(reentryLockProvider.notifier)
        .didChangeAppLifecycleState(AppLifecycleState.resumed);

    expect(container.read(reentryLockProvider), isFalse);
  });

  test('unlocking clears the departure, so it does not re-lock at once', () {
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);
    final notifier = container.read(reentryLockProvider.notifier);

    notifier.simulateAway(const Duration(hours: 1));
    expect(container.read(reentryLockProvider), isTrue);

    notifier.unlock();
    expect(container.read(reentryLockProvider), isFalse);

    // A resume with nothing outstanding must not re-lock.
    notifier.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(container.read(reentryLockProvider), isFalse);
  });

  test('the lock can be applied deliberately, without waiting', () {
    // Handing the phone to somebody.
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);

    container.read(reentryLockProvider.notifier).lockNow();

    expect(container.read(reentryLockProvider), isTrue);
  });

  // ---- the lock belongs to one session -------------------------------------
  //
  // Found by the browser harness, not by reading the code. SIGN OUT INSTEAD is
  // the one way off the lock screen that needs no code; the sweep took it,
  // signed in again with the number and an OTP, and every screen it then
  // visited was the lock screen again.

  test('a lock does not follow the person who signed out', () {
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);

    container.read(reentryLockProvider.notifier).lockNow();
    expect(container.read(reentryLockProvider), isTrue);

    // They press SIGN OUT INSTEAD.
    container.read(whoIsSignedIn.notifier).state = null;
    expect(
      container.read(reentryLockProvider),
      isFalse,
      reason: 'there is no session left to lock',
    );
  });

  test('a fresh sign-in is not asked to prove the same phone twice', () {
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);

    container.read(reentryLockProvider.notifier).lockNow();
    container.read(whoIsSignedIn.notifier).state = null;
    // Signing in again means the number AND an OTP — strictly more proof than
    // the lock screen asks for. Same person, new sign-in, so a new session key.
    container.read(whoIsSignedIn.notifier).state =
        'citizen-1@2026-09-28T12:05:00Z';

    expect(container.read(reentryLockProvider), isFalse);
  });

  test('a colleague is not locked out of the session they just opened', () {
    // A stale lock met the next person instead of the app. They could get past
    // it — the lock screen reads the live session, so the code goes to their
    // own number — but re-verifying a sign-in completed seconds ago is the same
    // defect as above, arriving at a worse moment.
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);

    container.read(reentryLockProvider.notifier).lockNow();
    container.read(whoIsSignedIn.notifier).state =
        'colleague-2@2026-09-28T12:05:00Z';

    expect(container.read(reentryLockProvider), isFalse);
  });

  test('the same session stays locked across a profile refresh', () {
    // The guard must be the session IDENTITY, not the auth state. `authProvider`
    // rebuilds whenever the profile, role or tier resolves, and a lock lifted by
    // a background refresh would be no lock at all.
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);

    container.read(reentryLockProvider.notifier).lockNow();
    container.read(whoIsSignedIn.notifier).state =
        'citizen-1@2026-09-28T12:00:00Z'; // unchanged

    expect(container.read(reentryLockProvider), isTrue);
  });

  test('signing out clears the away-clock, not just the bit', () {
    // If the timestamp survived, the next session would be locked the instant
    // it was backgrounded for a moment, having inherited an hour of absence.
    final container = containerWith(signedIn: true, emergency: false);
    addTearDown(container.dispose);

    container.read(reentryLockProvider.notifier).lockNow();
    container.read(whoIsSignedIn.notifier).state = null;
    container.read(whoIsSignedIn.notifier).state =
        'citizen-1@2026-09-28T12:05:00Z';

    // A brief, innocent absence for the new session.
    container
        .read(reentryLockProvider.notifier)
        .simulateAway(const Duration(seconds: 5));

    expect(container.read(reentryLockProvider), isFalse);
  });
}

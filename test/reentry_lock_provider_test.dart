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

  ProviderContainer containerWith({
    required bool signedIn,
    required bool emergency,
  }) {
    return ProviderContainer(
      overrides: <Override>[
        hasSessionProvider.overrideWithValue(signedIn),
        emergencyActiveProvider.overrideWithValue(emergency),
      ],
    );
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
}

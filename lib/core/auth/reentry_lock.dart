/// Locking the app when it is picked up again.
///
/// ## What this is for
///
/// The app holds a person's incident history, their emergency contacts, the
/// live position of responders near them, and a panic button. A handset gets
/// left on a table, borrowed, taken. So coming back to the app after leaving it
/// asks the person to prove the number again, with a code sent to it.
///
/// ## What it must not do
///
/// This is an emergency application. A lock screen is a door, and a door in
/// front of a panic button is a liability, so three rules constrain it — and
/// they are the reason this decision is a tested function rather than an
/// `if` inside a lifecycle callback.
///
/// **A live emergency is never locked.** If an SOS is in progress, the person
/// is in the middle of the thing this app exists for. Locking them out of their
/// own alarm — to make them read an SMS — is the worst thing this feature could
/// do, and it is exactly what a naive "lock on resume" does.
///
/// **Leaving for a moment is not leaving.** Reporting an incident means
/// switching to the camera; being told to call someone means switching to the
/// dialler. Both put the app in the background. A grace window means the common
/// case — away for seconds, mid-task — does not cost an SMS, a wait, and the
/// loss of whatever was half-typed.
///
/// **The panic button stays reachable while locked.** The lock protects the
/// DATA: history, contacts, chat, the map. It does not protect the alarm. If
/// the phone is in a stranger's hands they can raise a false alarm, which costs
/// HQ a dispatch; if it is in the owner's hands during a kidnapping they can
/// raise a real one, which is the entire point of the product. Those are not
/// close.
///
/// ## The cost nobody sees until the bill
///
/// Every unlock is a paid SMS. That is a real constraint on how short the grace
/// window can be, and it belongs in the open: see
/// docs/PRODUCTION_DEPLOYMENT.md § 2b.
library;

/// How long the app may be away before it asks who is holding it.
///
/// Two minutes. Long enough to take a photo, copy a number, answer a call or
/// check a message and come back to a half-written report; short enough that a
/// phone left on a desk is locked before somebody wanders past it.
const Duration reentryGraceWindow = Duration(minutes: 2);

/// Why the app is (or is not) locked. Ordered from most to least urgent.
enum LockDecision {
  /// Stay open. Nobody is signed in — the login screen is the door.
  noSession,

  /// Stay open. An SOS is running; this is not the moment.
  emergencyInProgress,

  /// Stay open. Away only briefly, still mid-task.
  withinGrace,

  /// Ask for a code before anything but the panic button.
  lock,
}

/// Whether the app should be locked, and why.
///
/// [awayFor] is how long the app spent outside the foreground. [hasSession] is
/// whether anyone is signed in. [emergencyActive] is whether an SOS is running.
LockDecision reentryDecision({
  required Duration awayFor,
  required bool hasSession,
  required bool emergencyActive,
  Duration grace = reentryGraceWindow,
}) {
  if (!hasSession) return LockDecision.noSession;
  if (emergencyActive) return LockDecision.emergencyInProgress;
  if (awayFor < grace) return LockDecision.withinGrace;
  return LockDecision.lock;
}

/// Convenience for the caller that only wants the answer.
bool shouldLockOnResume({
  required Duration awayFor,
  required bool hasSession,
  required bool emergencyActive,
  Duration grace = reentryGraceWindow,
}) =>
    reentryDecision(
      awayFor: awayFor,
      hasSession: hasSession,
      emergencyActive: emergencyActive,
      grace: grace,
    ) ==
    LockDecision.lock;

/// What the person can actually do on the lock screen right now.
enum UnlockPath {
  /// A code can be sent and checked.
  codeBySms,

  /// There is no way to verify anyone until the network returns. The panic
  /// button still works; nothing else does.
  emergencyOnly,
}

/// Which unlock paths are open.
///
/// With no network there is no way to verify identity at all: the code cannot
/// be sent, and the emergency PIN is checked by a database function
/// (`verify_emergency_pin`), so it needs the network too.
///
/// This returns [UnlockPath.emergencyOnly] rather than pretending, because a
/// lock screen that shows a code box during a network blackout — which is the
/// condition this whole product is built around, and the reason the SMS and
/// mesh channels exist — is asking for something that cannot arrive. Saying so,
/// and leaving the panic button live, is the honest state.
UnlockPath unlockPathFor({required bool online}) =>
    online ? UnlockPath.codeBySms : UnlockPath.emergencyOnly;

/// What the lock screen tells the person, given the path open to them.
String lockScreenExplanation(UnlockPath path) {
  switch (path) {
    case UnlockPath.codeBySms:
      return 'For your safety, confirm this is your phone. '
          'We will send a code to your number.';
    case UnlockPath.emergencyOnly:
      return 'You are offline, so a code cannot be sent. '
          'Your emergency button still works — everything else is locked until '
          'you have a connection.';
  }
}

/// Whether a lock should survive a change of session.
///
/// It should not, and getting this wrong is worse than it sounds.
///
/// The lock is a property of ONE signed-in session: it says "this session has
/// been away, prove the phone is still yours". It was held as a bare bit that
/// only a verified code ever cleared, which left two bad outcomes on the one
/// route out of the lock screen that needs no code — SIGN OUT INSTEAD:
///
///   * **A fresh sign-in landed straight back on the lock.** Signing out and
///     signing in again means entering the number and passing an OTP, which is
///     strictly more proof than the lock screen asks for. Being shown the lock
///     screen again immediately afterwards asks the person to do the same thing
///     twice, and the browser harness walked into exactly that: signed out,
///     completed the OTP, and every screen of the sweep was the lock screen.
///
///   * **It showed the previous person's number to the next one.** The lock
///     screen names the number a code went to. Hand the phone to a colleague,
///     let them sign in as themselves, and a stale lock put the last user's
///     mobile number on their screen.
///
/// So: same session, the lock stands. Different session — including no session
/// at all — the lock is not theirs and does not apply. Ending the session is a
/// stronger act than unlocking, not a way around it: it leaves the person with
/// no session and nothing to unlock into.
///
/// "Session" here means one sign-in, not one person. A user id alone cannot
/// distinguish signing out and back in as the same person from nothing having
/// happened at all, and that is the case this exists for; the caller pairs the
/// id with the sign-in time so each sign-in is its own session.
bool lockSurvivesSessionChange({
  required String? lockedSession,
  required String? currentSession,
}) =>
    lockedSession != null && lockedSession == currentSession;

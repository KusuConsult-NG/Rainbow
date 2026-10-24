// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/auth/phone_number.dart';
import 'package:rainbow_app/core/offline/sms_device_key.dart';
import 'package:rainbow_app/core/supabase/supabase_config.dart';
import 'package:rainbow_app/services/background_tracking_service.dart';
import 'package:rainbow_app/services/mesh_service.dart';
import 'package:rainbow_app/services/secure_storage_service.dart';
import 'package:rainbow_app/services/sim_watch_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rainbow_app/core/config/staff_identity.dart' as identity;
import 'package:rainbow_app/core/auth/last_known_role.dart';

/// Provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(secureStorageProvider));
});

/// Handles all authentication logic for Plateau Eye users on Supabase.
class AuthService {
  AuthService(this._secureStorage);
  final SecureStorageService _secureStorage;

  String? _lastAuthError;
  String? _pendingPhone; // stores phone between step1 and step2

  /// Surface the last authentication error message
  String? get lastAuthError => _lastAuthError;

  /// Retrieves the current user ID
  String? get currentUserId {
    try {
      return SupabaseConfig.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  // ── CITIZEN PATH: phone number, then a code sent to it ─────────────────────
  //
  // `signInWithPhone(phone, otp)` used to live here — a second, combined
  // version of the two steps below, carrying its own copy of the demo bypass.
  // Nothing called it. Two implementations of a sign-in path is two places for
  // the demo bypass to be forgotten, and it was already the one with no
  // release-build guard.

  // ── AGENT PATH: Badge / Email Login ───────────────────────────────────────

  /// Authenticate agent with Badge ID / Email and Password
  Future<bool> signInWithBadge(String badgeOrEmail, String password) async {
    _lastAuthError = null;
    // The domain was a literal here and another one in the console's
    // login/page.tsx. It is the second half of the primary key of a person:
    // two copies that must agree is how one officer came to have two accounts
    // on two domains, with their posting on one of them and an empty board on
    // the other. See lib/core/config/staff_identity.dart. T-99.
    final email = identity.emailForBadge(badgeOrEmail);

    try {
      final res = await SupabaseConfig.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return await _sessionEstablished(res.session);
    } catch (e) {
      _lastAuthError = e.toString();
      return false;
    }
  }

  /// REMOVED: signInWithAccessCode(String code).
  ///
  /// It read `AGENT_DEFAULT_PASS` out of the bundled `.env` and signed in as
  /// `<code>@operationrainbow.plateau.gov.ng` with it. Three facts together
  /// made that a published credential for every staff account at once:
  ///
  ///   * `pubspec.yaml` declares `.env` as a Flutter ASSET, so it ships
  ///     verbatim inside the APK and extracts with `unzip` (E2E_AUDIT_REPORT.md
  ///     H-3);
  ///   * every officer shared the one password in it;
  ///   * the "access code" was only the email local-part — a USERNAME, not a
  ///     secret.
  ///
  /// So rotating the access codes would have changed the usernames while the
  /// single password stayed readable in the shipped binary. The code was never
  /// the secret; the password was, and it was published.
  ///
  /// Staff sign in through `signInWithBadge(badgeOrEmail, password)` with their
  /// own password. `login_screen.dart` asks for one instead of signing in on a
  /// code alone.
  ///
  /// Every existing staff password must be rotated server-side, because the one
  /// they shared is in every copy of the app ever shipped:
  /// `node scripts/rotate_staff_passwords.js`.

  /// The demo number that skips the SMS, and which does NOT exist in a
  /// released build.
  ///
  /// This returned true in every build. So in a shipped APK, typing
  /// `08000000000` and the code `123456` signed you in as whoever
  /// `DEMO_CITIZEN_EMAIL` is — a real account, with a real session, on the real
  /// database. The number is in this source file and the password is in the
  /// bundled `.env`, which extracts with `unzip`. That is not a demo bypass, it
  /// is a published credential.
  ///
  /// `kReleaseMode` is the single choke point: both call sites below ask this
  /// question, so the path simply does not exist in a release build and the
  /// number is treated like any other — which means it fails validation, since
  /// `0800…` is not a Nigerian mobile prefix.
  ///
  /// The `.env` values are a separate problem this cannot fix: a release build
  /// must not carry DEMO_CITIZEN_EMAIL/DEMO_CITIZEN_PASS at all, because they
  /// are readable in the APK whether or not any code reads them. See
  /// docs/PRODUCTION_DEPLOYMENT.md.
  static bool isDemoNumber(String phone) {
    if (kReleaseMode) return false;
    final clean = phone.trim().replaceAll(RegExp('[^0-9+]'), '');
    return clean == '08000000000' ||
        clean == '2348000000000' ||
        clean == '+2348000000000';
  }

  // ── TWO-STEP CITIZEN FLOW ──────────────────────────────────────────────────

  /// Step 1: ask for a code to be sent to this number.
  ///
  /// Returns whether the caller should now show the code screen. It used to
  /// return `void`, and the screen decided by reading `lastAuthError` — which
  /// worked, but put the decision in the caller and made it easy to advance on
  /// a send that had failed. There is nothing worse to show a person in an
  /// emergency than a box waiting for a code that was never sent.
  ///
  /// The number is normalised FIRST, and refused here if it cannot receive an
  /// SMS. See `lib/core/auth/phone_number.dart`: this is the identity, and it
  /// used to be whatever the person typed with the punctuation removed, so one
  /// person had four of them.
  Future<bool> verifyPhoneNumber(String phone) async {
    _lastAuthError = null;

    // The demo number is checked BEFORE normalisation, because `0800…` is not
    // a mobile prefix and would otherwise be refused — and it does not exist
    // in a release build at all. See [isDemoNumber].
    if (isDemoNumber(phone)) {
      _pendingPhone = phone.trim().replaceAll(RegExp('[^0-9+]'), '');
      debugPrint('[AUTH] demo number (debug build only) — the code is 123456');
      return true;
    }

    final read = readNigerianPhone(phone);
    if (!read.isValid) {
      _lastAuthError = read.problem;
      return false;
    }
    final e164 = read.e164!;
    _pendingPhone = e164;

    try {
      await SupabaseConfig.client.auth.signInWithOtp(phone: e164);
      // The number is not logged. It identifies a person who may be reporting
      // something they would be harmed for reporting, and debug logs are read
      // off handsets.
      debugPrint('[AUTH] a code was sent');
      return true;
    } catch (e) {
      _lastAuthError =
          describeOtpSendFailure(e, hasNetwork: await _handsetIsOnline());
      debugPrint('[AUTH] the code could not be sent: $e');
      return false;
    }
  }

  /// What the handset says about its own connection, or null if it will not
  /// say. Used only to tell "you are offline" apart from "the service cannot
  /// be reached from here" — never to decide whether to attempt a request,
  /// because a connectivity result is a statement about an interface, not
  /// about whether anything answers on it.
  static Future<bool?> _handsetIsOnline() async {
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      return !results.contains(ConnectivityResult.none);
    } catch (_) {
      return null;
    }
  }

  /// Turns a send failure into something a person can act on.
  ///
  /// The commonest one by far is not the person's fault and not transient:
  /// Supabase refuses `signInWithOtp` outright when the project has no SMS
  /// provider configured. Termii — which this deployment uses everywhere else —
  /// is not one of Supabase's built-in providers, so it has to be wired up as a
  /// Send SMS auth hook. Until that is done, EVERY citizen sign-in fails here.
  /// Saying "try again" to that is telling someone to keep pulling a lever that
  /// is not connected to anything. See docs/PRODUCTION_DEPLOYMENT.md.
  /// Static, and public for the same reason `isDemoNumber` is: it is pure
  /// string work that touches no storage and no session, and the messages it
  /// produces are the only thing a citizen ever sees when a code does not
  /// arrive. Constructing an AuthService to test them would mean supplying a
  /// SecureStorageService this method never uses.
  ///
  /// [hasNetwork] is what the handset says about its own connection, or null
  /// when nobody asked. It exists because "no connection" and "cannot resolve
  /// the service" are different faults with different remedies, and this
  /// function used to call both of them the first one.
  static String describeOtpSendFailure(Object e, {bool? hasNetwork}) {
    final text = e.toString().toLowerCase();
    if (text.contains('sms provider') ||
        text.contains('phone provider') ||
        text.contains('unsupported phone provider') ||
        text.contains('signups not allowed') ||
        text.contains('phone_provider_disabled')) {
      return 'SMS SIGN-IN IS NOT SWITCHED ON FOR THIS SERVICE YET. '
          'REPORT THIS TO HQ — IT IS NOT YOUR PHONE.';
    }
    // The provider IS switched on and the Send SMS hook answered with a
    // failure. These are the hook's own messages — "hook is not configured",
    // "TERMII_API_KEY is not set", "Termii refused the message", "could not
    // reach Termii" — matched on strings this repository controls rather than
    // on Supabase's wording, which would be guessing at somebody else's
    // contract.
    //
    // It needs its own branch because the fallback below says TRY AGAIN, and
    // none of these clears by trying again. Telling a person to retry a
    // deployment fault is the lever-not-connected-to-anything problem described
    // above, which is the thing this whole method exists to avoid.
    //
    // The list below is every reason `supabase/functions/send-sms` can return,
    // and it is kept honest by `scripts/check_every_hook_failure_is_explained.py`,
    // which reads the reasons out of the function itself. It used to be five
    // strings written from THESE BRANCHES rather than from the function, so it
    // could only ever confirm what was already matched; five more reasons fell
    // through to TRY AGAIN.
    //
    // `signature` is the one that matters. A signing-secret MISMATCH — the
    // dashboard holding one value and SEND_SMS_HOOK_SECRET another — produces
    // `no v1 signature matched` on every single sign-in, and it is the
    // likeliest misconfiguration left once everything else is wired, because
    // `wire_up_sms_provider.sh --check` cannot see it: its POST probe proves
    // the secret is SET and rejects a BAD signature, and a mismatched secret
    // does exactly that too. Every probe stays green and nobody can sign in.
    // Telling that citizen to TRY AGAIN is the lever-not-connected-to-anything
    // problem this whole method exists to avoid.
    if (text.contains('hook') ||
        text.contains('termii') ||
        text.contains('not configured') ||
        text.contains('signature') ||
        text.contains('payload has') ||
        text.contains('body is not json')) {
      return 'SMS SIGN-IN IS MISCONFIGURED FOR THIS SERVICE. '
          'REPORT THIS TO HQ — IT IS NOT YOUR PHONE.';
    }
    // 'rate limit', not 'rate': the bare substring also matches "generated",
    // "accurate" and "operate", any of which would send somebody away to wait a
    // minute for a fault that waiting does not fix.
    if (text.contains('rate limit') ||
        text.contains('rate_limit') ||
        text.contains('too many')) {
      return 'TOO MANY CODES REQUESTED. WAIT A MINUTE AND TRY AGAIN.';
    }
    // A NAME THAT WILL NOT RESOLVE IS NOT A MISSING CONNECTION.
    //
    // This branch used to swallow `failed host lookup` along with socket and
    // timeout errors and tell everyone "NO CONNECTION". It was reported from a
    // handset showing four bars of 4G: the phone was online, the service's
    // hostname would not resolve, and the app blamed the phone. That is the
    // same fault this method exists to avoid two branches above — sending
    // somebody to fix something that is not broken at their end.
    final cannotResolve = text.contains('failed host lookup') ||
        text.contains('no address associated') ||
        text.contains('nodename nor servname');
    if (cannotResolve) {
      if (hasNetwork == false) {
        return 'NO CONNECTION. THE CODE CANNOT BE SENT WITHOUT ONE.';
      }
      if (hasNetwork == true) {
        return 'THIS PHONE IS ONLINE BUT THE SERVICE ADDRESS WILL NOT '
            'RESOLVE. REPORT THIS TO HQ — IT IS NOT YOUR PHONE.';
      }
      // Nobody asked the handset. Claiming it is online is the same kind of
      // guess as claiming it is offline, in the other direction.
      return 'THE SERVICE ADDRESS WILL NOT RESOLVE. IF THIS PHONE IS ONLINE, '
          'REPORT IT TO HQ.';
    }
    if (text.contains('socket') ||
        text.contains('timeout') ||
        text.contains('network')) {
      return hasNetwork == false
          ? 'NO CONNECTION. THE CODE CANNOT BE SENT WITHOUT ONE.'
          : 'THE SERVICE DID NOT ANSWER. TRY AGAIN IN A MOMENT.';
    }
    return 'THE CODE COULD NOT BE SENT. TRY AGAIN.';
  }

  /// Step 2: Verify OTP and create Supabase session.
  Future<bool> verifyOTP(String otp) async {
    _lastAuthError = null;
    final phone = _pendingPhone;

    if (phone == null) {
      _lastAuthError = 'SESSION EXPIRED — PLEASE RE-ENTER YOUR PHONE NUMBER';
      return false;
    }

    // The number and the code were both printed here. A debug log is read off
    // a handset by anyone holding it, and together those two lines are enough
    // to sign in as the person — the code is single-use, but the window is the
    // whole time it sits unverified.
    debugPrint('[AUTH] checking a code');

    if (isDemoNumber(phone)) {
      // Demo citizen: only accept OTP 123456
      if (otp == '123456') {
        try {
          final demoEmail = dotenv.env['DEMO_CITIZEN_EMAIL'];
          final demoPass  = dotenv.env['DEMO_CITIZEN_PASS'];
          if (demoEmail == null || demoPass == null) {
            _lastAuthError = 'DEMO_CITIZEN_EMAIL / DEMO_CITIZEN_PASS not configured in .env';
            return false;
          }
          final res = await SupabaseConfig.client.auth.signInWithPassword(
            email: demoEmail,
            password: demoPass,
          );
          if (res.session != null) {
            _pendingPhone = null;
            return await _sessionEstablished(res.session);
          }
          _lastAuthError = 'DEMO LOGIN FAILED — CHECK SUPABASE CONFIGURATION';
          return false;
        } catch (e) {
          _lastAuthError = e.toString();
          return false;
        }
      } else {
        _lastAuthError = 'THE DEMO CODE IS 123456 (DEBUG BUILDS ONLY)';
        return false;
      }
    }

    // Real phone: verify via Supabase
    try {
      final res = await SupabaseConfig.client.auth.verifyOTP(
        type: OtpType.sms,
        token: otp,
        phone: phone,
      );
      if (res.session != null) {
        _pendingPhone = null;
        return await _sessionEstablished(res.session);
      }
      _lastAuthError = 'THAT CODE WAS NOT ACCEPTED.';
      return false;
    } catch (e) {
      _lastAuthError = _describeOtpCheckFailure(
        e,
        hasNetwork: await _handsetIsOnline(),
      );
      debugPrint('[AUTH] the code was not accepted: $e');
      return false;
    }
  }

  /// The number the code was sent to, for showing back to the person.
  ///
  /// In the form they wrote it — `0803 000 1111`, not `+2348030001111`, which
  /// invites a "…is that mine?" pause on the one screen where hesitating is
  /// worst. Null when no code is outstanding.
  String? get pendingPhoneForDisplay {
    final phone = _pendingPhone;
    if (phone == null) return null;
    return displayNigerianPhone(phone);
  }

  /// Turns a verification failure into something a person can act on.
  String _describeOtpCheckFailure(Object e, {bool? hasNetwork}) {
    final text = e.toString().toLowerCase();
    if (text.contains('expired')) {
      return 'THAT CODE HAS EXPIRED. ASK FOR A NEW ONE.';
    }
    if (text.contains('invalid') || text.contains('token')) {
      return 'THAT CODE IS NOT RIGHT. CHECK THE MESSAGE AND TRY AGAIN.';
    }
    if (text.contains('failed host lookup') ||
        text.contains('no address associated') ||
        text.contains('nodename nor servname')) {
      if (hasNetwork == false) {
        return 'NO CONNECTION. THE CODE CANNOT BE CHECKED WITHOUT ONE.';
      }
      if (hasNetwork == true) {
        return 'THIS PHONE IS ONLINE BUT THE SERVICE ADDRESS WILL NOT '
            'RESOLVE. REPORT THIS TO HQ — IT IS NOT YOUR PHONE.';
      }
      return 'THE SERVICE ADDRESS WILL NOT RESOLVE. IF THIS PHONE IS ONLINE, '
          'REPORT IT TO HQ.';
    }
    if (text.contains('socket') ||
        text.contains('timeout') ||
        text.contains('network')) {
      return hasNetwork == false
          ? 'NO CONNECTION. THE CODE CANNOT BE CHECKED WITHOUT ONE.'
          : 'THE SERVICE DID NOT ANSWER. TRY AGAIN IN A MOMENT.';
    }
    return 'THAT CODE WAS NOT ACCEPTED.';
  }

  /// Test seam: obtaining the SMS device key, which reaches secure storage and
  /// Supabase and so cannot run under `flutter test`.
  @visibleForTesting
  static Future<void> Function()? provisionSmsKeyOverride;

  /// Everything that has to happen once a session exists.
  ///
  /// THE OFFLINE CHANNELS ARE OBTAINED HERE OR NOT AT ALL.
  ///
  /// The SMS and mesh channels both authenticate with a per-device key that has
  /// to be fetched from the server. The whole point of them is that they work
  /// when there is no data connection, so the key cannot be fetched at the moment
  /// it is needed — by then there is nothing to fetch it over. Sign-in is the one
  /// moment the app is guaranteed to have both a session and a network, so this
  /// is where it happens.
  ///
  /// It runs on EVERY sign-in and costs one secure-storage read when a key is
  /// already held. Failure is never fatal and never blocks the sign-in: a handset
  /// with no key still works normally, it simply has one fewer way to reach HQ
  /// when the network dies. Saying so out loud matters, because the failure is
  /// silent until the night it counts.
  Future<bool> _sessionEstablished(Session? session) =>
      onSessionEstablished(session != null);

  /// The body of [_sessionEstablished], taking a bool rather than a `Session`.
  ///
  /// Split out only so it can be tested: constructing a real gotrue `Session` in
  /// a unit test means constructing a `User`, a token and an expiry, none of
  /// which this decision looks at. The production paths all go through
  /// [_sessionEstablished].
  @visibleForTesting
  Future<bool> onSessionEstablished(bool hasSession) async {
    if (!hasSession) return false;
    try {
      await (provisionSmsKeyOverride ??
          () async => SmsDeviceKeyService().ensureProvisioned())();
    } catch (e) {
      debugPrint('[SIGNIN_SMSKEY_ERR] could not obtain a device key: $e');
    }
    // Record which SIM this handset has, so a later removal is visible. The
    // first check never reports anything — it is the baseline — and a failure
    // here is not a reason to fail a sign-in.
    try {
      await (simBaselineOverride ?? () async => SimWatchService().check())();
    } catch (e) {
      debugPrint('[SIGNIN_SIM_ERR] could not record the SIM baseline: $e');
    }
    return true;
  }

  /// Test seam: the SIM check reaches a platform channel and Supabase.
  @visibleForTesting
  static Future<void> Function()? simBaselineOverride;

  /// Test seam: BackgroundTrackingService talks to platform channels, which do
  /// not exist under `flutter test`.
  @visibleForTesting
  static Future<void> Function()? stopTrackingOverride;

  /// Test seam: whether an SOS track is running, and for which incident.
  @visibleForTesting
  static Future<String?> Function()? activeSosOverride;

  /// Test seam: the write that tells HQ this handset signed out.
  @visibleForTesting
  static Future<void> Function(String alertId)? stampSignOutOverride;

  /// Test seam: the SMS key service reaches secure storage and Supabase.
  @visibleForTesting
  static Future<void> Function()? forgetSmsKeyOverride;

  /// Test seam: the SIM baseline reaches secure storage.
  @visibleForTesting
  static Future<void> Function()? forgetSimBaselineOverride;

  /// Test seam: the mesh reaches a platform channel.
  @visibleForTesting
  static Future<void> Function()? stopMeshOverride;

  /// Sign out user session.
  ///
  /// STOPPING LOCATION IS PART OF SIGNING OUT.
  ///
  /// This cleared the session and the secure storage and left the background
  /// location service running. Its keys live in SharedPreferences, which
  /// `deleteAll()` does not touch, and the isolate re-initialises Supabase by
  /// itself — so the phone carried on transmitting its position every few
  /// seconds under the signed-out user's uid, with the app showing a login
  /// screen. Signing out is the clearest statement a person can make that they
  /// are done being observed, and it was the one action that did not stop it.
  ///
  /// Tells HQ that the app is gone while this incident is still open.
  ///
  /// One column, not a message: `alerts.device_signed_out_at`. A handset must
  /// not be able to write prose onto an operator's screen — the same rule
  /// `sim_channel_events` states, where the words HQ reads are composed by the
  /// console from a code.
  static Future<void> _stampSignOut(String alertId) async {
    await SupabaseConfig.client
        .from('alerts')
        .update({'device_signed_out_at': DateTime.now().toIso8601String()})
        .eq('id', alertId);
  }

  /// EXCEPT WHILE AN EMERGENCY IS STILL OPEN.
  ///
  /// The paragraph above is right about a person signing out of their own
  /// phone, and wrong about the one case the duress design exists for. A duress
  /// PIN tells the person their alarm is cancelled and deliberately KEEPS
  /// TRACKING RUNNING, because they may still be in danger; and the lock
  /// screen offers a sign-out that needs no code at all. So whoever was holding
  /// the phone could end the tracking of a live duress alert without knowing
  /// any PIN, and all HQ saw was a track going quiet — indistinguishable from a
  /// flat battery.
  ///
  /// A RESPONDER's patrol track still stops: they are going off duty. An SOS
  /// track keeps running until the incident closes or the twelve-hour
  /// `sosTrackingMaxAge` ceiling expires, and the alert is stamped so the loss
  /// of the app is a fact an operator can read rather than a gap to infer.
  ///
  /// First, so that a failure below cannot leave a patrol track alive.
  Future<void> signOut() async {
    // `activeSosAlertId()` answers null rather than throwing, including on a
    // failure to read: the background isolate takes its mode from the same
    // store, so an unreadable store means there is no SOS track to preserve.
    final liveSos = await (activeSosOverride ??
        BackgroundTrackingService().activeSosAlertId)();

    if (liveSos == null) {
      try {
        await (stopTrackingOverride ?? BackgroundTrackingService().stopTracking)();
      } catch (e) {
        debugPrint('[SIGNOUT_TRACKING_ERR] could not stop tracking: $e');
      }
    } else {
      // Best-effort, and before the session is cleared so RLS still sees the
      // reporter. A phone being switched off must not have its sign-out
      // blocked on a network write.
      try {
        await (stampSignOutOverride ?? _stampSignOut)(liveSos);
      } catch (e) {
        debugPrint('[SIGNOUT_STAMP_ERR] HQ was not told the app is gone: $e');
      }
    }
    // And give up the SMS device key, for the same reason tracking stops: this
    // handset is no longer authorised to speak for that person, and the key
    // can both send an emergency in their name and decrypt the ones they send.
    try {
      await (forgetSmsKeyOverride ?? SmsDeviceKeyService().forget)();
    } catch (e) {
      debugPrint('[SIGNOUT_SMSKEY_ERR] could not retire the SMS key: $e');
    }
    // And forget which SIM was in this handset. Without this the next person
    // to sign in on the same phone is compared against the previous owner's
    // SIM, and gets a "SIM REPLACED" alert for what is really a change of
    // owner. `deleteAll()` below would cover it, but saying it explicitly
    // keeps the reason attached to the line.
    try {
      await (forgetSimBaselineOverride ?? SimWatchService().forget)();
    } catch (e) {
      debugPrint('[SIGNOUT_SIM_ERR] could not clear the SIM baseline: $e');
    }
    // And leave the Bluetooth mesh, dropping whatever it was carrying: a phone
    // should not keep relaying strangers' emergencies, on its owner's battery,
    // for somebody who has signed out.
    try {
      await (stopMeshOverride ?? MeshService.instance.onSignedOut)();
    } catch (e) {
      debugPrint('[SIGNOUT_MESH_ERR] could not stop the mesh: $e');
    }
    // And forget what rung this handset last opened as, so the next person to
    // pick it up gets the login screen rather than the previous holder's
    // board. BEFORE the sign-out call, which reaches the network to revoke the
    // token and throws when it cannot. T-100.
    try {
      await clearLastKnownRole();
    } catch (e) {
      debugPrint('[SIGNOUT_ROLE_ERR] could not clear the stored role: $e');
    }
    await SupabaseConfig.client.auth.signOut();
    await _secureStorage.deleteAll();
    _pendingPhone = null;
  }
}

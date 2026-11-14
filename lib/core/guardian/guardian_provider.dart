/// AI Emergency Guardian, phase 1: an opt-in listening session, English only,
/// while Plateau Eye is open on screen.
///
/// What a session does:
/// - listens through the phone's recognizer in short passes, restarting each
///   one as it ends (the recognizer stops after every pause);
/// - feeds what it hears to [DistressDetector] and drops the words at once:
///   nothing heard is stored or sent;
/// - on a match, ends itself and raises a Silent SOS whose description names
///   the rule that matched, never the words;
/// - steps aside while a voice report or the dispatcher chat is dictating,
///   and while the app is in the background, where phase 1 cannot listen;
/// - ends by itself at the time the user chose, at most 8 hours.
///
/// There is no confirmation prompt before the SOS: a person under threat may
/// not be able to answer one. A false alarm is cancelled afterwards with the
/// Safe PIN, like any SOS; the Duress PIN behaves as it always has.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rainbow_app/core/guardian/distress_detector.dart';
import 'package:rainbow_app/core/guardian/guardian_ear.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String guardianConsentKey = 'guardian_consent_v1';

/// The session lengths offered. The longest is the cap.
const List<Duration> guardianDurations = [
  Duration(hours: 1),
  Duration(hours: 2),
  Duration(hours: 4),
  Duration(hours: 8),
];

/// Where the secret phrase lives: the platform keystore, on this phone only.
abstract class GuardianPhraseStore {
  Future<String?> read();
  Future<void> write(String? phrase);
}

class SecureGuardianPhraseStore implements GuardianPhraseStore {
  static const _key = 'guardian_secret_phrase';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String? phrase) async {
    if (phrase == null) {
      await _storage.delete(key: _key);
    } else {
      await _storage.write(key: _key, value: phrase);
    }
  }
}

final guardianEarProvider = Provider<GuardianEar>((ref) => SpeechToTextEar());
final guardianPhraseStoreProvider =
    Provider<GuardianPhraseStore>((ref) => SecureGuardianPhraseStore());

/// Whether the user has read and accepted the Guardian notice.
final guardianConsentProvider =
    StateNotifierProvider<GuardianConsent, bool>((ref) => GuardianConsent());

class GuardianConsent extends StateNotifier<bool> {
  GuardianConsent() : super(false) {
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = prefs.getBool(guardianConsentKey) ?? false;
    } on Object catch (_) {}
  }

  Future<void> accept() async {
    state = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(guardianConsentKey, true);
    } on Object catch (_) {}
  }
}

/// Whether a secret phrase is set. The phrase itself is read only when a
/// session starts, and is never put in any state a widget can show.
final guardianHasPhraseProvider =
    StateNotifierProvider<GuardianHasPhrase, bool>(
  (ref) => GuardianHasPhrase(ref.read(guardianPhraseStoreProvider)),
);

class GuardianHasPhrase extends StateNotifier<bool> {
  GuardianHasPhrase(this._store) : super(false) {
    unawaited(_load());
  }

  final GuardianPhraseStore _store;

  Future<void> _load() async {
    final p = await _store.read();
    if (mounted) state = p != null && p.isNotEmpty;
  }

  /// Saves [phrase] when it passes [DistressDetector.checkSecretPhrase];
  /// returns the problem otherwise and saves nothing.
  Future<SecretPhraseProblem?> save(String phrase) async {
    final problem = DistressDetector.checkSecretPhrase(phrase);
    if (problem != null) return problem;
    await _store.write(phrase.trim());
    state = true;
    return null;
  }

  Future<void> remove() async {
    await _store.write(null);
    state = false;
  }
}

/// Why a session could not start or had to stop.
enum GuardianProblem {
  /// Not a phone (the web build), so there is nothing to listen with.
  unsupported,

  /// The microphone permission was refused.
  microphoneDenied,

  /// The phone's speech recognizer is missing, or refuses on-device
  /// recognition for this language.
  recognizerUnavailable,

  /// The recognizer kept stopping straight after starting.
  recognizerKeepsFailing,
}

@immutable
class GuardianState {
  const GuardianState({
    this.active = false,
    this.startedAt,
    this.endsAt,
    this.pausedForOtherFeature = false,
    this.pausedInBackground = false,
    this.problem,
    this.lastMatch,
  });

  final bool active;
  final DateTime? startedAt;
  final DateTime? endsAt;
  final bool pausedForOtherFeature;
  final bool pausedInBackground;
  final GuardianProblem? problem;

  /// What sent the last Guardian SOS, for the screen to say so.
  final GuardianMatch? lastMatch;

  bool get listening => active && !pausedForOtherFeature && !pausedInBackground;
}

final guardianProvider =
    NotifierProvider<GuardianNotifier, GuardianState>(GuardianNotifier.new);

class GuardianNotifier extends Notifier<GuardianState> {
  DistressDetector _detector = DistressDetector();
  Timer? _endTimer;
  Timer? _restartTimer;
  DateTime? _passStartedAt;
  bool _passRunning = false;
  int _quickFailures = 0;

  /// Clock seam for tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  static const int _maxQuickFailures = 5;
  static const Duration _quickPass = Duration(seconds: 1);

  GuardianEar get _ear => ref.read(guardianEarProvider);

  @override
  GuardianState build() {
    final busy = ref.read(guardianEarProvider).otherFeatureBusy;
    busy.addListener(_onBusyChanged);
    final lifecycle = AppLifecycleListener(
      onHide: () => _setBackground(true),
      onShow: () => _setBackground(false),
    );
    ref.onDispose(() {
      busy.removeListener(_onBusyChanged);
      lifecycle.dispose();
      _endTimer?.cancel();
      _restartTimer?.cancel();
    });
    return const GuardianState();
  }

  /// Starts a session of [length], capped at the longest offered.
  /// Returns the problem when it could not start.
  Future<GuardianProblem?> start(Duration length) async {
    if (state.active) return null;
    final ear = _ear;
    if (!ear.supported) return _fail(GuardianProblem.unsupported);
    if (!await ear.ensureMicrophone()) {
      return _fail(GuardianProblem.microphoneDenied);
    }

    final phrase = await ref.read(guardianPhraseStoreProvider).read();
    _detector = DistressDetector(secretPhrase: phrase);
    _quickFailures = 0;

    final cap = guardianDurations.last;
    final capped = length > cap ? cap : length;
    final started = now();
    state = GuardianState(
      active: true,
      startedAt: started,
      endsAt: started.add(capped),
      pausedForOtherFeature: ear.otherFeatureBusy.value,
    );
    _endTimer?.cancel();
    _endTimer = Timer(capped, () => unawaited(stop()));

    final ok = await _listenOnce();
    if (!ok && state.active && !state.pausedForOtherFeature) {
      await stop();
      return _fail(GuardianProblem.recognizerUnavailable);
    }
    return null;
  }

  /// Ends the session. Keeps [GuardianState.lastMatch] so the screen can say
  /// what happened.
  Future<void> stop({GuardianProblem? problem}) async {
    _endTimer?.cancel();
    _restartTimer?.cancel();
    final wasRunning = _passRunning;
    _passRunning = false;
    _detector.reset();
    state = GuardianState(problem: problem, lastMatch: state.lastMatch);
    if (wasRunning) await _ear.stop();
  }

  GuardianProblem _fail(GuardianProblem p) {
    state = GuardianState(problem: p, lastMatch: state.lastMatch);
    return p;
  }

  Future<bool> _listenOnce() async {
    if (!state.listening || _passRunning) return true;
    _passRunning = true;
    _passStartedAt = now();
    final ok = await _ear.listen(onWords: _onWords, onEnded: _onPassEnded);
    if (!ok) _passRunning = false;
    return ok;
  }

  void _onWords(String words, bool isFinal) {
    // Not while paused: a stopped recognizer can still deliver a late result,
    // and a pause is a promise not to be listening.
    if (!state.listening) return;
    final match = _detector.hear(words, now(), isFinal: isFinal);
    if (match == null) return;
    unawaited(_send(match));
  }

  Future<void> _send(GuardianMatch match) async {
    // Inactive at once, synchronously: the recognizer repeats a growing
    // utterance, and the next report must not send a second time.
    _endTimer?.cancel();
    _restartTimer?.cancel();
    final wasRunning = _passRunning;
    _passRunning = false;
    _detector.reset();
    state = GuardianState(lastMatch: match);
    // The SOS before the microphone: nothing waits on stopping a recognizer.
    final sos = ref.read(emergencyProvider.notifier).startEmergency(
          silent: true,
          description: match.description,
        );
    if (wasRunning) unawaited(_ear.stop());
    await sos;
  }

  void _onPassEnded() {
    _passRunning = false;
    if (!state.listening) return;
    final started = _passStartedAt;
    final quick = started != null && now().difference(started) < _quickPass;
    _quickFailures = quick ? _quickFailures + 1 : 0;
    if (_quickFailures >= _maxQuickFailures) {
      unawaited(stop(problem: GuardianProblem.recognizerKeepsFailing));
      return;
    }
    // A short, growing pause after a quick failure, so a recognizer that
    // refuses does not spin.
    _restartTimer?.cancel();
    _restartTimer = Timer(
      Duration(milliseconds: 200 + 400 * _quickFailures),
      () => unawaited(_listenOnce()),
    );
  }

  void _onBusyChanged() {
    if (!state.active) return;
    final busy = _ear.otherFeatureBusy.value;
    state = GuardianState(
      active: true,
      startedAt: state.startedAt,
      endsAt: state.endsAt,
      pausedForOtherFeature: busy,
      pausedInBackground: state.pausedInBackground,
      lastMatch: state.lastMatch,
    );
    if (busy) {
      // The other feature's own listen has already taken the recognizer over.
      _restartTimer?.cancel();
      _passRunning = false;
    } else {
      unawaited(_listenOnce());
    }
  }

  void _setBackground(bool background) {
    if (!state.active) return;
    state = GuardianState(
      active: true,
      startedAt: state.startedAt,
      endsAt: state.endsAt,
      pausedForOtherFeature: state.pausedForOtherFeature,
      pausedInBackground: background,
      lastMatch: state.lastMatch,
    );
    if (background) {
      _restartTimer?.cancel();
      if (_passRunning) {
        _passRunning = false;
        unawaited(_ear.stop());
      }
    } else {
      unawaited(_listenOnce());
    }
  }

  /// Test seam: what the background listener does.
  @visibleForTesting
  void debugSetBackground(bool background) => _setBackground(background);
}

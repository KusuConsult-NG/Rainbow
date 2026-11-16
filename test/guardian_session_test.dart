import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/guardian/guardian_ear.dart';
import 'package:rainbow_app/core/guardian/guardian_keep_alive.dart';
import 'package:rainbow_app/core/guardian/guardian_provider.dart';
import 'package:rainbow_app/core/guardian/hausa_model.dart';
import 'package:rainbow_app/core/guardian/hausa_provider.dart';
import 'package:rainbow_app/features/guardian/guardian_screen.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A microphone that hears what the test says.
class _FakeEar implements GuardianEar {
  bool isSupported = true;
  bool micAllowed = true;
  bool listenWorks = true;
  bool background = false;
  int listens = 0;
  int stops = 0;
  int releases = 0;
  String? lastHausaDir;
  void Function(String, bool)? _words;
  void Function()? _ended;
  void Function(String reason)? _hausaLost;
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  @override
  bool get supported => isSupported;

  @override
  bool get listensInBackground => background;

  @override
  Future<void> release() async {
    releases++;
    await stop();
  }

  @override
  ValueListenable<bool> get otherFeatureBusy => busy;

  @override
  Future<bool> ensureMicrophone() async => micAllowed;

  @override
  Future<bool> listen({
    required void Function(String words, bool isFinal) onWords,
    required void Function() onEnded,
    String? hausaModelDir,
    void Function(String reason)? onHausaLost,
  }) async {
    if (!listenWorks) return false;
    lastHausaDir = hausaModelDir;
    _hausaLost = onHausaLost;
    listens++;
    _words = onWords;
    _ended = onEnded;
    return true;
  }

  @override
  Future<void> stop() async {
    stops++;
    final end = _ended;
    _ended = null;
    end?.call();
  }

  void say(String words, {bool isFinal = true}) => _words?.call(words, isFinal);

  /// The Hausa model failing, at load or while listening.
  void loseHausa(String reason) => _hausaLost?.call(reason);

  /// The recognizer ending a pass by itself, as it does after every pause.
  void passEnds() {
    final end = _ended;
    _ended = null;
    end?.call();
  }
}

/// Android's "Guardian is listening" service, without Android.
class _FakeKeepAlive implements GuardianKeepAlive {
  bool works = true;
  bool running = false;
  int starts = 0;
  String? title;
  String? stopLabel;
  void Function()? _stop;

  @override
  Future<bool> start({required String title, required String text, required String stopLabel}) async {
    starts++;
    this.title = title;
    this.stopLabel = stopLabel;
    running = works;
    return works;
  }

  @override
  Future<void> stop() async => running = false;

  @override
  void whenStopPressed(void Function()? callback) => _stop = callback;

  /// The person pressing Stop on the notification.
  void pressStop() => _stop?.call();
}

class _MemoryPhrases implements GuardianPhraseStore {
  String? phrase;
  @override
  Future<String?> read() async => phrase;
  @override
  Future<void> write(String? p) async => phrase = p;
}

class _RecordingEmergency extends EmergencyNotifier {
  static final List<(bool, String?)> raised = [];

  @override
  Future<void> startEmergency({bool silent = false, String? description}) async {
    if (state.isEmergencyActive) return;
    raised.add((silent, description));
    state = state.copyWith(isEmergencyActive: true, isSilent: silent);
  }
}

void main() {
  late _FakeEar ear;
  late _FakeKeepAlive keepAlive;
  late _MemoryPhrases phrases;
  late ProviderContainer c;
  late DateTime clock;
  late Directory modelRoot;
  String? hausaUrl;

  List<Override> overrides() => [
        guardianEarProvider.overrideWithValue(ear),
        guardianKeepAliveProvider.overrideWithValue(keepAlive),
        guardianPhraseStoreProvider.overrideWithValue(phrases),
        emergencyProvider.overrideWith(_RecordingEmergency.new),
        guardianHausaStoreProvider.overrideWith(
          (ref) async => HausaModelStore(root: modelRoot, manifestUrl: hausaUrl),
        ),
      ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _RecordingEmergency.raised.clear();
    ear = _FakeEar();
    keepAlive = _FakeKeepAlive();
    phrases = _MemoryPhrases();
    clock = DateTime(2026, 11, 14, 20);
    modelRoot = Directory.systemTemp.createTempSync('guardian_models');
    hausaUrl = null;
    c = ProviderContainer(overrides: overrides());
    c.read(guardianProvider.notifier).now = () => clock;
  });

  tearDown(() {
    c.dispose();
    if (modelRoot.existsSync()) modelRoot.deleteSync(recursive: true);
  });

  GuardianNotifier g() => c.read(guardianProvider.notifier);
  GuardianState s() => c.read(guardianProvider);

  testWidgets('a distress phrase sends ONE silent SOS naming the rule, and ends the session', (t) async {
    await g().start(const Duration(hours: 1));
    expect(s().listening, isTrue);
    expect(ear.listens, 1);

    ear.say("they're kidnapping", isFinal: false);
    ear.say("they're kidnapping me", isFinal: false);
    ear.say("they're kidnapping me", isFinal: true);
    await t.pump();

    expect(_RecordingEmergency.raised, [(true, 'Guardian: distress phrase heard (abduction)')]);
    expect(s().active, isFalse);
    expect(s().lastMatch?.rule, 'abduction');
    expect(ear.stops, 1);
  });

  testWidgets('the saved secret phrase sends, and HQ is not told the words', (t) async {
    phrases.phrase = 'The mangoes are ripe';
    await g().start(const Duration(hours: 1));
    ear.say('you know the mangoes are ripe now');
    await t.pump();
    expect(_RecordingEmergency.raised.single.$2, 'Guardian: secret phrase heard');
    expect(_RecordingEmergency.raised.single.$2, isNot(contains('mango')));
  });

  testWidgets('ordinary talk sends nothing and the session keeps listening', (t) async {
    await g().start(const Duration(hours: 1));
    ear.say('the movie was about a kidnapping');
    ear.say('can you help me with this bag');
    await t.pump();
    expect(_RecordingEmergency.raised, isEmpty);
    expect(s().listening, isTrue);
    await g().stop();
  });

  testWidgets('a pass that ends is restarted', (t) async {
    await g().start(const Duration(hours: 1));
    clock = clock.add(const Duration(seconds: 30));
    ear.passEnds();
    await t.pump(const Duration(seconds: 1));
    expect(ear.listens, 2);
    expect(s().listening, isTrue);
    await g().stop();
  });

  testWidgets('a recognizer that keeps stopping at once ends the session with a reason', (t) async {
    await g().start(const Duration(hours: 1));
    for (var i = 0; i < 5; i++) {
      ear.passEnds();
      await t.pump(const Duration(seconds: 5));
    }
    expect(s().active, isFalse);
    expect(s().problem, GuardianProblem.recognizerKeepsFailing);
  });

  testWidgets('it steps aside while a voice report dictates, then resumes', (t) async {
    await g().start(const Duration(hours: 1));
    ear.busy.value = true;
    expect(s().pausedForOtherFeature, isTrue);
    expect(s().listening, isFalse);
    await t.pump(const Duration(seconds: 5));
    expect(ear.listens, 1, reason: 'no restart while the other feature has the recognizer');

    ear.busy.value = false;
    await t.pump();
    expect(s().listening, isTrue);
    expect(ear.listens, 2);
    await g().stop();
  });

  testWidgets('it pauses in the background and resumes on screen', (t) async {
    await g().start(const Duration(hours: 1));
    g().debugSetBackground(true);
    await t.pump();
    expect(s().pausedInBackground, isTrue);
    expect(ear.stops, 1);
    // A late result from the stopped recognizer must not count.
    ear.say("they're kidnapping me");
    await t.pump();
    expect(_RecordingEmergency.raised, isEmpty);

    g().debugSetBackground(false);
    await t.pump();
    expect(s().listening, isTrue);
    expect(ear.listens, 2);
    await g().stop();
  });

  testWidgets('the session ends at the chosen time', (t) async {
    await g().start(const Duration(hours: 1));
    await t.pump(const Duration(minutes: 59));
    expect(s().active, isTrue);
    await t.pump(const Duration(minutes: 2));
    expect(s().active, isFalse);
    expect(s().problem, isNull);
  });

  testWidgets('a session is never longer than 8 hours', (t) async {
    await g().start(const Duration(hours: 30));
    expect(s().endsAt!.difference(s().startedAt!), const Duration(hours: 8));
    await g().stop();
  });

  testWidgets('words after Stop send nothing', (t) async {
    await g().start(const Duration(hours: 1));
    final say = ear._words!;
    await g().stop();
    say("they're kidnapping me", true);
    await t.pump();
    expect(_RecordingEmergency.raised, isEmpty);
  });

  testWidgets('a refused microphone is reported, and nothing listens', (t) async {
    ear.micAllowed = false;
    expect(await g().start(const Duration(hours: 1)), GuardianProblem.microphoneDenied);
    expect(s().active, isFalse);
    expect(ear.listens, 0);
  });

  testWidgets('a missing recognizer is reported instead of pretending', (t) async {
    ear.listenWorks = false;
    expect(await g().start(const Duration(hours: 1)), GuardianProblem.recognizerUnavailable);
    expect(s().active, isFalse);
  });

  testWidgets('the web build says Guardian needs the phone app', (t) async {
    ear.isSupported = false;
    expect(await g().start(const Duration(hours: 1)), GuardianProblem.unsupported);
  });

  group('phase 2: listening in the background', () {
    testWidgets('with an ear that can, it keeps listening off screen, behind a visible notification', (t) async {
      ear.background = true;
      await g().start(const Duration(hours: 1));
      expect(keepAlive.running, isTrue);
      expect(keepAlive.title, 'Guardian is listening');
      expect(keepAlive.stopLabel, 'Stop');

      g().debugSetBackground(true);
      await t.pump();
      expect(s().listening, isTrue, reason: 'no pause: the session is kept alive');
      expect(ear.stops, 0);

      ear.say("they're kidnapping me");
      await t.pump();
      expect(_RecordingEmergency.raised.single.$2, 'Guardian: distress phrase heard (abduction)');
      expect(keepAlive.running, isFalse, reason: 'the notification goes with the session');
    });

    testWidgets('Stop on the notification ends the session and frees the microphone', (t) async {
      ear.background = true;
      await g().start(const Duration(hours: 1));
      keepAlive.pressStop();
      await t.pump();
      expect(s().active, isFalse);
      expect(keepAlive.running, isFalse);
      expect(ear.releases, 1);
      expect(_RecordingEmergency.raised, isEmpty);
    });

    testWidgets('if the notification service cannot start, it pauses off screen as before', (t) async {
      ear.background = true;
      keepAlive.works = false;
      await g().start(const Duration(hours: 1));
      g().debugSetBackground(true);
      await t.pump();
      expect(s().pausedInBackground, isTrue);
      ear.say("they're kidnapping me");
      await t.pump();
      expect(_RecordingEmergency.raised, isEmpty, reason: 'a pause is a promise not to be listening');
      await g().stop();
    });

    testWidgets('an ear that cannot listen off screen never starts the notification', (t) async {
      await g().start(const Duration(hours: 1));
      expect(keepAlive.starts, 0);
      await g().stop();
    });

    testWidgets('a voice report takes the microphone: Guardian lets go of it, then takes it back', (t) async {
      ear.background = true;
      await g().start(const Duration(hours: 1));
      ear.busy.value = true;
      await t.pump();
      expect(ear.stops, 1, reason: 'the microphone is released for the dictation');
      expect(s().listening, isFalse);
      ear.busy.value = false;
      await t.pump();
      expect(ear.listens, 2);
      expect(s().listening, isTrue);
      await g().stop();
    });

    testWidgets('stopping the session frees the speech models', (t) async {
      await g().start(const Duration(hours: 1));
      await g().stop();
      expect(ear.releases, 1);
    });
  });

  group('phase 3: Hausa', () {
    /// A complete, verified Hausa model on disk, as HausaModelStore leaves one.
    String installHausa() {
      final d = Directory('${modelRoot.path}/hausa-202611150900')..createSync(recursive: true);
      for (final f in hausaModelFiles) {
        File('${d.path}/$f').writeAsStringSync('x');
      }
      File('${d.path}/.complete').writeAsStringSync('202611150900');
      return d.path;
    }

    Future<ProviderContainer> containerWith({required bool enabled}) async {
      hausaUrl = 'https://huggingface.co/example/guardian-hausa/resolve/main/manifest.json';
      SharedPreferences.setMockInitialValues({guardianHausaEnabledKey: enabled});
      c.dispose();
      c = ProviderContainer(overrides: overrides());
      c.read(guardianProvider.notifier).now = () => clock;
      c.read(guardianHausaProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return c;
    }

    testWidgets('with no model address configured, Hausa is not offered and nothing loads it', (t) async {
      await t.runAsync(() async {
        c.read(guardianHausaProvider);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      expect(c.read(guardianHausaProvider).status, HausaStatus.unavailable);
      await g().start(const Duration(hours: 1));
      expect(ear.lastHausaDir, isNull);
      await g().stop();
    });

    testWidgets('a downloaded model that is switched on is listened with', (t) async {
      final dir = installHausa();
      await t.runAsync(() => containerWith(enabled: true));
      expect(c.read(guardianHausaProvider).status, HausaStatus.ready);
      await g().start(const Duration(hours: 1));
      expect(ear.lastHausaDir, dir);
      await g().stop();
    });

    testWidgets('a downloaded model that is switched off is not', (t) async {
      installHausa();
      await t.runAsync(() => containerWith(enabled: false));
      await g().start(const Duration(hours: 1));
      expect(ear.lastHausaDir, isNull);
      await g().stop();
    });

    testWidgets('a Hausa call for help heard in a session sends a silent SOS', (t) async {
      installHausa();
      await t.runAsync(() => containerWith(enabled: true));
      await g().start(const Duration(hours: 1));
      ear.say('taimake ni suna son su kashe ni');
      await t.pump();
      expect(_RecordingEmergency.raised.single, (true, 'Guardian: distress phrase heard (threat to life)'));
    });

    // A broken optional download must never cost the person English
    // listening: the transcriber drops Hausa and reports it, and the session
    // carries on in English and says so.
    testWidgets('when the Hausa model fails, the session goes on in English and says so', (t) async {
      final dir = installHausa();
      await t.runAsync(() => containerWith(enabled: true));
      await g().start(const Duration(hours: 1));
      expect(ear.lastHausaDir, dir);

      ear.loseHausa('the Hausa model did not load');
      expect(c.read(guardianProvider).active, isTrue);
      expect(c.read(guardianProvider).hausaLost, isTrue);

      ear.say('they are trying to kill me');
      await t.pump();
      expect(_RecordingEmergency.raised.single.$2, 'Guardian: distress phrase heard (threat to life)');
    });

    testWidgets('after Hausa fails, later passes do not ask for it again', (t) async {
      installHausa();
      await t.runAsync(() => containerWith(enabled: true));
      await g().start(const Duration(hours: 1));
      ear.loseHausa('the Hausa model failed while listening');
      clock = clock.add(const Duration(minutes: 1));
      await ear.stop(); // the pass ends, and is restarted
      await t.pump(const Duration(seconds: 2));
      expect(ear.listens, greaterThanOrEqualTo(2));
      expect(ear.lastHausaDir, isNull);
      expect(c.read(guardianProvider).hausaLost, isTrue, reason: 'still said after a restart');
      await g().stop();
    });

    testWidgets('a pause keeps the Hausa-stopped notice', (t) async {
      installHausa();
      await t.runAsync(() => containerWith(enabled: true));
      await g().start(const Duration(hours: 1));
      ear.loseHausa('the Hausa model failed while listening');
      ear.busy.value = true;
      expect(c.read(guardianProvider).hausaLost, isTrue);
      ear.busy.value = false;
      expect(c.read(guardianProvider).hausaLost, isTrue);
      await g().stop();
    });

    testWidgets('a new session starts with Hausa again', (t) async {
      final dir = installHausa();
      await t.runAsync(() => containerWith(enabled: true));
      await g().start(const Duration(hours: 1));
      ear.loseHausa('the Hausa model failed while listening');
      await g().stop();
      expect(c.read(guardianProvider).hausaLost, isFalse);
      await g().start(const Duration(hours: 1));
      expect(ear.lastHausaDir, dir);
      await g().stop();
    });
  });

  group('the screen', () {
    Future<void> pumpScreen(WidgetTester t) async {
      await t.binding.setSurfaceSize(const Size(400, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(home: GuardianScreen()),
        ),
      );
      await t.pump();
    }

    testWidgets('shows the notice first, and the controls only after it is accepted', (t) async {
      await pumpScreen(t);
      expect(find.byKey(const ValueKey('guardian_start')), findsNothing);
      expect(find.textContaining('without asking you first'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('guardian_accept')));
      await t.pump();
      expect(find.byKey(const ValueKey('guardian_start')), findsOneWidget);
    });

    testWidgets('starting and stopping a session', (t) async {
      await c.read(guardianConsentProvider.notifier).accept();
      await pumpScreen(t);
      await t.tap(find.byKey(const ValueKey('guardian_length_2')));
      await t.tap(find.byKey(const ValueKey('guardian_start')));
      await t.pump();
      expect(s().active, isTrue);
      expect(s().endsAt!.difference(s().startedAt!), const Duration(hours: 2));
      expect(find.textContaining('Listening until'), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('guardian_stop')));
      await t.pump();
      expect(s().active, isFalse);
      expect(find.text('Guardian is off'), findsOneWidget);
    });

    testWidgets('with no Hausa model address, the screen says Hausa is not available yet', (t) async {
      await c.read(guardianConsentProvider.notifier).accept();
      await pumpScreen(t);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      expect(find.textContaining('cannot listen in Hausa yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('guardian_ha_download')), findsNothing);
    });

    testWidgets('a weak secret phrase is refused and a good one is saved', (t) async {
      await c.read(guardianConsentProvider.notifier).accept();
      await pumpScreen(t);
      await t.enterText(find.byKey(const ValueKey('guardian_phrase_field')), 'red mango');
      await t.tap(find.byKey(const ValueKey('guardian_phrase_save')));
      await t.pump();
      expect(find.text('Use at least three words.'), findsOneWidget);
      expect(phrases.phrase, isNull);

      await t.enterText(find.byKey(const ValueKey('guardian_phrase_field')), 'The mangoes are ripe');
      await t.tap(find.byKey(const ValueKey('guardian_phrase_save')));
      await t.pump();
      expect(phrases.phrase, 'The mangoes are ripe');
      expect(find.text('A secret phrase is set.'), findsOneWidget);
    });
  });
}

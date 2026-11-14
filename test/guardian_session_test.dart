import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/guardian/guardian_ear.dart';
import 'package:rainbow_app/core/guardian/guardian_provider.dart';
import 'package:rainbow_app/features/guardian/guardian_screen.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A microphone that hears what the test says.
class _FakeEar implements GuardianEar {
  bool isSupported = true;
  bool micAllowed = true;
  bool listenWorks = true;
  int listens = 0;
  int stops = 0;
  void Function(String, bool)? _words;
  void Function()? _ended;
  final ValueNotifier<bool> busy = ValueNotifier<bool>(false);

  @override
  bool get supported => isSupported;

  @override
  ValueListenable<bool> get otherFeatureBusy => busy;

  @override
  Future<bool> ensureMicrophone() async => micAllowed;

  @override
  Future<bool> listen({
    required void Function(String words, bool isFinal) onWords,
    required void Function() onEnded,
  }) async {
    if (!listenWorks) return false;
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

  /// The recognizer ending a pass by itself, as it does after every pause.
  void passEnds() {
    final end = _ended;
    _ended = null;
    end?.call();
  }
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
  late _MemoryPhrases phrases;
  late ProviderContainer c;
  late DateTime clock;

  List<Override> overrides() => [
        guardianEarProvider.overrideWithValue(ear),
        guardianPhraseStoreProvider.overrideWithValue(phrases),
        emergencyProvider.overrideWith(_RecordingEmergency.new),
      ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _RecordingEmergency.raised.clear();
    ear = _FakeEar();
    phrases = _MemoryPhrases();
    clock = DateTime(2026, 11, 14, 20);
    c = ProviderContainer(overrides: overrides());
    c.read(guardianProvider.notifier).now = () => clock;
  });

  tearDown(() => c.dispose());

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

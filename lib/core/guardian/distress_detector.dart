/// The rules that decide whether something heard during a Guardian session
/// sends a Silent SOS.
///
/// Plain Dart with no plugins, so every rule is unit-tested. The design is
/// deliberately strict: a false SOS takes a responder away from a real one,
/// so only two kinds of speech send anything —
///
/// 1. the user's own secret distress phrase, and
/// 2. a short list of unmistakable first-person calls for help.
///
/// A plea with no threat ("please leave me alone") only counts: a second one
/// within [DistressDetector.pleaWindow] sends the SOS. Talk ABOUT danger
/// ("the movie was about a kidnapping") and negated phrases ("nobody is
/// kidnapping me") send nothing.
///
/// English, and Nigerian Pidgin (phase 2). The recognizer on the phone is an
/// English model; Pidgin is close enough to English that it writes Pidgin
/// down in English spelling, so the Pidgin rules below are written against
/// what it produces: "dem wan kill me" usually arrives as "THEM WANT KILL ME"
/// or "THEY ONE KILL ME". Hausa needs its own model, planned for phase 3.
library;

/// What started a Guardian SOS.
enum GuardianTrigger {
  /// The user's own secret distress phrase.
  secretPhrase,

  /// One of the built-in distress rules.
  distressPhrase,
}

/// A detection: why Guardian decided to send.
class GuardianMatch {
  const GuardianMatch(this.trigger, this.rule);

  final GuardianTrigger trigger;

  /// Which rule matched, as a stable id — see [DistressDetector.ruleLabels].
  /// The words themselves are never reported: a secret phrase sent to the
  /// server would be readable by anyone with console access.
  final String rule;

  /// The one line HQ sees as the alert's description.
  String get description => trigger == GuardianTrigger.secretPhrase
      ? 'Guardian: secret phrase heard'
      : 'Guardian: distress phrase heard (${DistressDetector.ruleLabels[rule] ?? rule})';

  @override
  bool operator ==(Object other) =>
      other is GuardianMatch && other.trigger == trigger && other.rule == rule;

  @override
  int get hashCode => Object.hash(trigger, rule);

  @override
  String toString() => 'GuardianMatch(${trigger.name}, $rule)';
}

/// Why a proposed secret phrase was refused.
enum SecretPhraseProblem {
  /// Fewer than [DistressDetector.minSecretPhraseWords] words.
  tooShort,

  /// It would trip a built-in rule anyway, so it adds nothing — or it is
  /// mostly words people say all the time.
  tooCommon,
}

class DistressDetector {
  DistressDetector({
    String? secretPhrase,
    this.pleaWindow = const Duration(minutes: 2),
  }) : _secret = secretPhrase == null ? '' : normalize(secretPhrase);

  /// How close together two pleas must be to send an SOS.
  final Duration pleaWindow;

  final String _secret;
  DateTime? _lastPlea;

  static const int minSecretPhraseWords = 3;

  /// Human-readable names for the rule ids, shown to HQ.
  static const Map<String, String> ruleLabels = {
    'threat_to_life': 'threat to life',
    'weapon_plea': 'weapon and a plea',
    'abduction': 'abduction',
    'repeated_plea': 'repeated plea for help',
  };

  // ---------------------------------------------------------------------------
  // Rules. Written against normalize()d text: lower case, no punctuation, no
  // apostrophes ("they're" -> "theyre", "don't" -> "dont").

  static final List<(String, RegExp)> _strongRules = [
    (
      'threat_to_life',
      RegExp(r'\b(trying|going|want|wants|about) to (kill|shoot|stab|murder) me\b'),
    ),
    (
      'threat_to_life',
      RegExp(r'\b(dont|do not) (kill|shoot|stab) me\b'),
    ),
    (
      'threat_to_life',
      RegExp(r'\b(is|are|theyre|hes|shes|were) (killing|stabbing|shooting) me\b'),
    ),
    (
      'abduction',
      RegExp(r'\b(kidnapping|abducting) (me|us)\b'),
    ),
    (
      'abduction',
      RegExp(r'\b(im|i am|ive been|i have been|were|we are|weve been|we have been) (being )?(kidnapped|abducted)\b'),
    ),
    // Nigerian Pidgin, as the English recognizer writes it down. The verb
    // must follow the subject directly: "dem no wan kill me" ("they don't want
    // to kill me") has "no" in between and does not match. Not the future
    // "go", and not "e": "this work go kill me", "my oga go kill me if I
    // late", "e go kill me" are everyday exaggeration, not a threat.
    (
      'threat_to_life',
      RegExp(r'\b(dem|them|they|im|him|he|she|una) (wan|want|one|won|dey|day|the|don|done) (kill|shoot|stab|wound) (me|us)\b'),
    ),
    (
      // "abeg no kill me", "make una no shoot me": in Pidgin "no" before the
      // verb is the plea itself, "don't".
      'threat_to_life',
      RegExp(r'\b(abeg|a beg|i beg|please|make (una|you|dem|them)) (no|not) (kill|shoot|stab) (me|us)\b'),
    ),
    (
      'abduction',
      RegExp(r'\b(dem|them|they|kidnappers) (wan|want|one|won|don|done|dey|day|the|go) kidnap (me|us)\b'),
    ),
  ];

  static final RegExp _weapon =
      RegExp(r'\b(gun|guns|knife|knives|machete|matchet|cutlass|rifle|pistol|dagger|weapon)\b');
  static final RegExp _plea = RegExp(
    // Not a bare "please" or "abeg": "please pass the knife" is not a plea.
    r'\b(please dont|dont shoot|dont hurt|help me|help us|leave me|let me go|let us go|abeg no|no shoot|no wound)\b',
  );

  static final RegExp _weakPlea = RegExp(
    // Not a bare "help me": "can you help me with this bag", asked twice,
    // would add up to an SOS. The recognizer writes "someone" as "some one".
    // Pidgin: "abeg leave me", "comot for my body" (get off me), "help me o".
    r'\b(leave me alone|let me go|let us go|get off me|stop hurting me|some ?body help|some ?one help'
    r'|abeg leave me|leave me (o|oh)|comot for my body|comot (your|ya) hand|help me (o|oh)|abeg help me|make una help me)\b',
  );

  /// Words that report rather than call for help. Any of them in the same
  /// utterance switches the built-in rules off for it.
  static final RegExp _reporting = RegExp(
    r'\b(movie|movies|film|films|news|story|stories|book|novel|series|episode|song|game|heard that|yesterday|last night|last week|they said|he said|she said|imagine|pretend'
    // Pidgin: "dem talk say", "I hear say", "e happen yesterday".
    r'|talk say|hear say|dem talk|dem say)\b',
  );

  static const Set<String> _negations = {
    // Not a bare "no": "no no please don't shoot me" is a plea.
    'not', 'never', 'nobody', 'noone', 'isnt', 'arent', 'wasnt', 'werent',
  };

  /// Lower case, letters/digits/spaces only, apostrophes dropped, single
  /// spaces. Applied to what was heard and to the secret phrase alike.
  static String normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r"['’`]"), '')
      .replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAllMapped(_kidnapLike, _kidnapWord);

  // The recognizer sometimes mishears the one word that matters most:
  // "I AM BEING KIDNACKED" for "kidnapped", "KID NAPPING". Nothing else in
  // English starts with "kidna", so any such word is read as the kidnap word
  // its ending suggests. "ACHE HID NAPPING" is not touched.
  static final RegExp _kidnapLike = RegExp(r'\bkid ?na[a-z]*');
  static String _kidnapWord(Match m) {
    final w = m.group(0)!.replaceAll(' ', '');
    if (w.endsWith('ing')) return 'kidnapping';
    if (w.endsWith('ed') || w.endsWith('pt')) return 'kidnapped';
    if (w.endsWith('er') || w.endsWith('ers')) return 'kidnappers';
    return 'kidnap';
  }

  /// Whether [phrase] may be used as a secret phrase; null when it may.
  static SecretPhraseProblem? checkSecretPhrase(String phrase) {
    final words = normalize(phrase).split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length < minSecretPhraseWords) return SecretPhraseProblem.tooShort;
    final probe = DistressDetector();
    final text = words.join(' ');
    if (probe.hear(text, DateTime(2000), isFinal: true) != null ||
        _weakPlea.hasMatch(text)) {
      return SecretPhraseProblem.tooCommon;
    }
    // A phrase made only of everyday filler would be said by accident.
    if (words.every(_everyday.contains)) return SecretPhraseProblem.tooCommon;
    return null;
  }

  static const Set<String> _everyday = {
    'a', 'an', 'the', 'i', 'you', 'we', 'he', 'she', 'it', 'they', 'me', 'us',
    'is', 'are', 'am', 'was', 'be', 'do', 'dont', 'go', 'come', 'how', 'what',
    'yes', 'no', 'ok', 'okay', 'good', 'morning', 'night', 'afternoon',
    'evening', 'hello', 'hi', 'thank', 'thanks', 'please', 'to', 'and', 'of',
    'in', 'on', 'my', 'your', 'now', 'here', 'there', 'fine', 'well',
  };

  /// Feeds one recognized utterance. Returns the match that should send an
  /// SOS, or null.
  ///
  /// The recognizer reports a growing utterance several times before it is
  /// final. Strong rules and the secret phrase are checked on every report,
  /// so help is sent at the earliest moment; a weak plea is counted only on
  /// the final report, so one utterance counts once.
  GuardianMatch? hear(String heard, DateTime at, {required bool isFinal}) {
    final text = normalize(heard);
    if (text.isEmpty) return null;

    if (_secret.isNotEmpty && _containsPhrase(text, _secret)) {
      return const GuardianMatch(GuardianTrigger.secretPhrase, 'secret_phrase');
    }

    if (_reporting.hasMatch(text)) return null;

    for (final (rule, pattern) in _strongRules) {
      if (_matchesUnnegated(pattern, text)) {
        return GuardianMatch(GuardianTrigger.distressPhrase, rule);
      }
    }
    if (_matchesUnnegated(_weapon, text) && _matchesUnnegated(_plea, text)) {
      return const GuardianMatch(GuardianTrigger.distressPhrase, 'weapon_plea');
    }

    // Two different pleas in one breath ("somebody help, leave me alone, get
    // off me") is distress, not two requests: it sends at once.
    if (isFinal && _distinctUnnegated(_weakPlea, text) >= 2) {
      _lastPlea = null;
      return const GuardianMatch(GuardianTrigger.distressPhrase, 'repeated_plea');
    }

    if (isFinal && _matchesUnnegated(_weakPlea, text)) {
      final last = _lastPlea;
      _lastPlea = at;
      if (last != null && at.difference(last) <= pleaWindow) {
        _lastPlea = null;
        return const GuardianMatch(GuardianTrigger.distressPhrase, 'repeated_plea');
      }
    }
    return null;
  }

  /// Forgets a counted plea. Called when a session starts or ends.
  void reset() => _lastPlea = null;

  static bool _containsPhrase(String text, String phrase) =>
      RegExp('\\b${RegExp.escape(phrase)}\\b').hasMatch(text);

  /// How many different phrases of [pattern] occur in [text], unnegated.
  static int _distinctUnnegated(RegExp pattern, String text) => pattern
      .allMatches(text)
      .where((m) => !_negatedAt(text, m.start))
      .map((m) => m.group(0)!.replaceAll(' ', ''))
      .toSet()
      .length;

  static bool _negatedAt(String text, int start) {
    final before = text.substring(0, start).trim();
    final words = before.isEmpty ? const <String>[] : before.split(' ');
    final window = words.length <= 3 ? words : words.sublist(words.length - 3);
    return window.any(_negations.contains) || window.join(' ').endsWith('no one');
  }

  /// True when [pattern] matches somewhere in [text] with no negation among
  /// the three words before the match.
  static bool _matchesUnnegated(RegExp pattern, String text) =>
      pattern.allMatches(text).any((m) => !_negatedAt(text, m.start));
}

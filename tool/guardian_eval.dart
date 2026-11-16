// Measures Guardian on recordings, offline, with the same transcriber and
// detector the app uses.
//
//   dart run tool/guardian_eval.dart --models assets/guardian \
//       --labels recordings/labels.csv [--secret "the blue goat sings"] \
//       [--show-text] [--hausa-model path/to/downloaded/hausa]
//
// --hausa-model: a folder with the Hausa model (hausa-encoder.int8.onnx,
// hausa-decoder.int8.onnx, hausa-tokens.txt), as training/hausa/ exports it
// and the app downloads it. Each utterance is then transcribed by both.
//
// labels.csv, one recording per line, paths relative to the CSV:
//
//   file,expect
//   calls/kill_01.wav,sos         # must send an SOS (a distress phrase)
//   calls/secret_01.wav,secret    # must send an SOS (the secret phrase)
//   everyday/kitchen_01.wav,none  # must send nothing
//
// Recordings: WAV, mono, 16 kHz. Lines starting with # are ignored.
//
// It reports the two targets set for Guardian:
//   - the share of secret-phrase recordings caught (target: 9 in 10);
//   - false SOS per hour of everyday audio (target: no more than 1 in 50 h,
//     i.e. 0.02 per hour). That needs a lot of everyday audio to measure:
//     with under 50 hours of it, the report says the target is not yet
//     measurable rather than calling a zero a pass.
//
// Nothing here is sent anywhere, and recordings are only read.

import 'dart:io';
import 'dart:typed_data';

import 'package:rainbow_app/core/guardian/distress_detector.dart';
import 'package:rainbow_app/core/guardian/offline_transcriber.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main(List<String> args) {
  String? arg(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final models = arg('--models') ?? 'assets/guardian';
  final labels = arg('--labels');
  final secret = arg('--secret');
  final showText = args.contains('--show-text');
  final hausa = arg('--hausa-model');
  if (labels == null) {
    stderr.writeln('usage: dart run tool/guardian_eval.dart --labels labels.csv '
        '[--models assets/guardian] [--secret "phrase"] [--show-text]');
    exit(64);
  }

  sherpa.initBindings();
  final base = File(labels).parent.path;
  final rows = File(labels)
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#') && !l.startsWith('file,'))
      .map((l) => l.split('#').first.split(',').map((s) => s.trim()).toList())
      .toList();

  final results = <_Result>[];
  for (final row in rows) {
    if (row.length < 2) continue;
    final path = '$base/${row[0]}';
    final expect = row[1];
    results.add(_run(path, expect, models, secret, showText, hausa));
  }
  _report(results, secret != null);
}

class _Result {
  _Result(this.file, this.expect, this.seconds, this.match, this.texts);
  final String file;
  final String expect;
  final double seconds;
  final GuardianMatch? match;
  final List<String> texts;
  bool get sent => match != null;
}

_Result _run(String path, String expect, String models, String? secret, bool showText, String? hausa) {
  final wave = sherpa.readWave(path);
  if (wave.sampleRate != OfflineTranscriber.sampleRate) {
    stderr.writeln('$path: ${wave.sampleRate} Hz, needs 16000 Hz mono — skipped');
    return _Result(path, expect, 0, null, const []);
  }
  final detector = DistressDetector(secretPhrase: secret);
  final start = DateTime(2026);
  var at = start;
  GuardianMatch? match;
  final texts = <String>[];

  final t = OfflineTranscriber(
    GuardianModelFiles.inDirectory(models),
    hausaDir: hausa,
    // Said, not swallowed: an evaluation meant to include Hausa that quietly
    // measured English alone would report the wrong thing.
    onHausaLost: (reason) => stderr.writeln('$path: Hausa listening stopped ($reason); English only'),
    onText: (text) {
      texts.add(text);
      match ??= detector.hear(text, at, isFinal: true);
    },
  );
  // 100 ms at a time, as the microphone delivers it.
  const chunk = OfflineTranscriber.sampleRate ~/ 10;
  final samples = wave.samples;
  for (var i = 0; i < samples.length; i += chunk) {
    final end = i + chunk < samples.length ? i + chunk : samples.length;
    t.accept(Float32List.sublistView(samples, i, end));
    at = start.add(Duration(milliseconds: (end * 1000) ~/ OfflineTranscriber.sampleRate));
  }
  t.flush();
  t.free();

  final seconds = samples.length / OfflineTranscriber.sampleRate;
  if (showText) {
    stdout.writeln('${match != null ? 'SOS ' : '    '} [$expect] $path');
    for (final s in texts) {
      stdout.writeln('       "$s"');
    }
    if (match != null) stdout.writeln('       -> ${match!.description}');
  }
  return _Result(path, expect, seconds, match, texts);
}

void _report(List<_Result> rs, bool hasSecret) {
  String pct(int a, int b) => b == 0 ? 'n/a' : '$a/$b (${(100 * a / b).toStringAsFixed(0)}%)';

  final secret = rs.where((r) => r.expect == 'secret').toList();
  final sos = rs.where((r) => r.expect == 'sos').toList();
  final none = rs.where((r) => r.expect == 'none').toList();
  final caughtSecret = secret.where((r) => r.match?.trigger == GuardianTrigger.secretPhrase).length;
  final caughtSos = sos.where((r) => r.sent).length;
  final falseSos = none.where((r) => r.sent).toList();
  final everydayHours = none.fold<double>(0, (s, r) => s + r.seconds) / 3600;

  stdout.writeln('');
  stdout.writeln('Guardian evaluation — ${rs.length} recording(s)');
  if (secret.isNotEmpty) {
    stdout.writeln('  secret phrase caught:   ${pct(caughtSecret, secret.length)}'
        '   target 90%${hasSecret ? '' : '  (no --secret given: none can be caught)'}');
  }
  if (sos.isNotEmpty) {
    stdout.writeln('  distress phrase caught: ${pct(caughtSos, sos.length)}');
  }
  if (none.isNotEmpty) {
    final perHour = everydayHours == 0 ? 0 : falseSos.length / everydayHours;
    stdout.writeln('  false SOS:              ${falseSos.length} in '
        '${everydayHours.toStringAsFixed(2)} h of everyday audio '
        '(${perHour.toStringAsFixed(2)}/h; target 0.02/h)');
    if (everydayHours < 50 && falseSos.isEmpty) {
      stdout.writeln('                          not yet measurable: the target needs '
          'at least 50 h of everyday audio');
    }
    for (final r in falseSos) {
      stdout.writeln('    false SOS in ${r.file}: ${r.match!.description} — heard "${r.texts.join(' | ')}"');
    }
  }
  for (final r in [...secret, ...sos].where((r) => !r.sent)) {
    stdout.writeln('    missed ${r.file} — heard "${r.texts.join(' | ')}"');
  }
}

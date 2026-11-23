// Synthesises spoken phrases for `tool/guardian_eval.dart`, so Guardian can be
// measured end to end without a microphone, a handset or a recording studio.
//
//   dart run tool/guardian_make_test_speech.dart \
//       --tts path/to/vits-piper-en_US-amy-low --out path/to/corpus
//
// Then:
//
//   dart run tool/guardian_eval.dart --models assets/guardian \
//       --labels path/to/corpus/labels.csv --show-text
//
// WHY SYNTHETIC. The note at the top of offline_transcriber.dart records that
// the streaming model was rejected after being "measured on synthetic distress
// phrases", so this is how the current model was chosen in the first place —
// there was just nothing in the repository to reproduce it with. Real
// recordings of real people in real danger are the honest corpus and nobody
// has one; synthetic speech at least exercises the whole chain (VAD, the
// bundled zipformer, DistressDetector) rather than stopping at the rules.
//
// WHAT IT DOES NOT TELL YOU. One synthetic voice in a quiet room is the easiest
// input this pipeline will ever get. A pass here is a floor, not a field
// result: it says the chain works, not that it works in a market in Jos with a
// generator running. Accents, distance, panic and noise are not modelled, and
// the false-SOS rate still needs the 50 hours of everyday audio guardian_eval
// asks for.
//
// The TTS model is NOT in this repository — it is ~67 MB and only used here.
// sherpa-onnx publishes it:
//   https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-ljs.tar.bz2
//
// Use a voice that ships lexicon.txt (vits-ljs does). A piper voice ships
// espeak-ng-data instead and needs an espeak-ng frontend compiled into
// sherpa-onnx, which the prebuilt library here does not have: every phrase
// comes back silent. This script refuses to write silence rather than let a
// corpus of nothing be measured.
import 'dart:io';
import 'dart:typed_data';

import 'package:rainbow_app/core/guardian/offline_transcriber.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Resamples to the rate Guardian listens at.
///
/// guardian_eval.dart SKIPS any recording that is not 16 kHz, with a line on
/// stderr — so a corpus at the voice's own rate measures nothing and reports
/// no false alarms, which reads as a pass. vits-ljs is 22050 Hz.
///
/// A box filter over each output sample's input window, not point sampling:
/// decimating 22050 to 16000 by picking nearest samples aliases, and aliasing
/// is exactly the kind of damage that would make this report "Guardian did not
/// hear it" when the fault was in this file.
Float32List resample(Float32List input, int fromRate, int toRate) {
  if (fromRate == toRate) return input;
  final ratio = fromRate / toRate;
  final out = Float32List((input.length / ratio).floor());
  for (var i = 0; i < out.length; i++) {
    final start = i * ratio;
    final end = start + ratio;
    var from = start.floor();
    final to = end.ceil().clamp(0, input.length);
    if (from >= to) from = to - 1;
    var sum = 0.0;
    var n = 0;
    for (var j = from; j < to; j++) {
      sum += input[j];
      n++;
    }
    out[i] = n == 0 ? 0 : sum / n;
  }
  return out;
}

/// (file stem, what it says, what guardian_eval must report).
///
/// The `sos` lines are one per built-in rule family. The `none` lines are the
/// cases the detector's own notes say must stay silent: talk ABOUT danger, a
/// negated threat, a weapon with no plea, and a plea that is really a favour.
const List<(String, String, String)> phrases = [
  // Must raise an SOS.
  ('kill_01', 'They are trying to kill me.', 'sos'),
  ('kill_02', 'Please, do not shoot me.', 'sos'),
  ('kill_03', 'He is killing me.', 'sos'),
  ('abduct_01', 'They are kidnapping me.', 'sos'),
  ('abduct_02', 'I have been kidnapped.', 'sos'),
  // Must stay silent.
  ('none_01', 'Nobody is kidnapping me.', 'none'),
  ('none_02', 'The movie was about a kidnapping.', 'none'),
  ('none_03', 'Please pass the knife.', 'none'),
  ('none_04', 'Can you help me with this bag?', 'none'),
  ('none_05', 'I will be home by seven o clock.', 'none'),
];

String _arg(List<String> a, String name, {String? fallback}) {
  final i = a.indexOf(name);
  if (i >= 0 && i + 1 < a.length) return a[i + 1];
  if (fallback != null) return fallback;
  stderr.writeln('missing $name');
  exit(2);
}

void main(List<String> args) {
  final ttsDir = _arg(args, '--tts');
  final outDir = _arg(args, '--out');

  sherpa.initBindings();

  final onnx = Directory(ttsDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.onnx'))
      .toList();
  if (onnx.length != 1) {
    stderr.writeln('expected exactly one .onnx in $ttsDir, found '
        '${onnx.length} — see the header of this file');
    exit(2);
  }

  // TWO KINDS OF VITS VOICE, AND ONLY ONE OF THEM WORKS HERE. A piper voice
  // ships espeak-ng-data and needs an espeak-ng frontend compiled into
  // sherpa-onnx to turn words into phonemes; the prebuilt library this
  // project depends on does not carry one, and every phrase comes back as
  // zero samples. A voice that ships its own lexicon.txt needs no frontend.
  // Both layouts are accepted so the failure is a clear message rather than a
  // corpus of silence.
  final lexicon = File('$ttsDir/lexicon.txt');
  final dataDir = Directory('$ttsDir/espeak-ng-data');
  final tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: onnx.single.path,
          tokens: '$ttsDir/tokens.txt',
          lexicon: lexicon.existsSync() ? lexicon.path : '',
          dataDir: lexicon.existsSync()
              ? ''
              : (dataDir.existsSync() ? dataDir.path : ''),
        ),
        numThreads: 2,
      ),
    ),
  );

  Directory('$outDir/calls').createSync(recursive: true);
  final labels = StringBuffer('file,expect\n');

  for (final (stem, text, expect) in phrases) {
    final audio = tts.generate(text: text);

    // FAIL LOUDLY ON SILENCE. writeWave happily writes a header with no
    // samples, so the first run of this script reported "10 recording(s)"
    // while every one of them was empty: the piper voice needs an espeak-ng
    // frontend the prebuilt sherpa library does not carry, and said so only
    // on stderr. A corpus of silence would then have been measured, and
    // guardian_eval would have reported no false alarms — a pass, from
    // nothing. Exactly the shape of failure this whole exercise is about.
    final samples = audio.samples;
    final silent = samples.isEmpty ||
        !samples.any((s) => s.isFinite && s.abs() > 0.001);
    if (silent) {
      stderr.writeln(
        'the voice produced no audio for "$text" (${samples.length} samples). '
        'A corpus of silence measures nothing. Check the TTS model: a piper '
        'voice needs an espeak-ng frontend compiled into sherpa-onnx, and a '
        'model shipping its own lexicon.txt does not.',
      );
      exit(1);
    }

    final at16k =
        resample(samples, audio.sampleRate, OfflineTranscriber.sampleRate);
    final path = '$outDir/calls/$stem.wav';
    final ok = sherpa.writeWave(
      filename: path,
      samples: at16k,
      sampleRate: OfflineTranscriber.sampleRate,
    );
    if (!ok) {
      stderr.writeln('could not write $path');
      exit(1);
    }
    final seconds = at16k.length / OfflineTranscriber.sampleRate;
    labels.write('calls/$stem.wav,$expect\n');
    stdout.writeln('  ${seconds.toStringAsFixed(1)}s  [$expect]  "$text"');
  }

  tts.free();
  File('$outDir/labels.csv').writeAsStringSync(labels.toString());
  stdout.writeln('\n${phrases.length} recording(s) and labels.csv in $outDir');
  stdout.writeln('Written at ${OfflineTranscriber.sampleRate} Hz mono, which '
      'is what Guardian listens at.');
}

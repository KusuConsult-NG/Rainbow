// Checks a published Hausa model the way the app will, before the app is
// pointed at it.
//
//   dart run tool/verify_hausa_manifest.dart \
//     https://huggingface.co/<repo>/resolve/main/manifest.json
//
//   # and, once it passes, write the address into a .env:
//   dart run tool/verify_hausa_manifest.dart <url> --env .env
//
// It uses the app's own HausaModelStore (lib/core/guardian/hausa_model.dart),
// so there is one set of rules, not two: the manifest must parse exactly as
// the phone parses it, every file must download, and every size and SHA-256
// must match. Only then is the address written. A manifest that fails here
// would fail on every phone that taps *Download Hausa*.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:rainbow_app/core/guardian/hausa_model.dart';

/// The `.env` variable the app reads (lib/core/config/app_config.dart).
const envKey = 'GUARDIAN_HAUSA_MANIFEST_URL';

/// Above this word error rate publish.py refuses to upload, and the notebook
/// says not to publish.
const maxWer = 0.5;

/// What a check found. [problems] empty means the model is ready.
class Verdict {
  Verdict(this.manifest, this.problems, this.notes);
  final HausaModelManifest? manifest;
  final List<String> problems;
  final List<String> notes;
  bool get ok => problems.isEmpty;
}

/// Fetches, parses and downloads the model at [url] into [scratch], exactly
/// as a phone would.
Future<Verdict> verify(String url, Directory scratch, {http.Client? client}) async {
  final problems = <String>[];
  final notes = <String>[];
  if (!url.startsWith('https://')) {
    return Verdict(null, ['the address must start with https:// (the app offers Hausa only then)'], notes);
  }
  final store = HausaModelStore(root: scratch, manifestUrl: url, client: client);
  HausaModelManifest manifest;
  try {
    manifest = await store.fetchManifest();
  } on Object catch (e) {
    return Verdict(null, ['the manifest did not load as the app loads it: $e'], notes);
  }
  final wer = manifest.wer;
  if (wer == null) {
    problems.add('the manifest has no word error rate: it was not evaluated before publishing');
  } else if (wer > maxWer) {
    problems.add('word error $wer is above $maxWer: the model would miss most calls for help');
  } else if (wer > 0.30) {
    notes.add('word error $wer: usable for testing; expect missed calls (the notebook says add recordings)');
  }
  try {
    final dir = await store.download(manifest);
    if (await store.installed() != dir) problems.add('the download finished but is not marked complete');
  } on Object catch (e) {
    problems.add('a file did not download and verify as the app does it: $e');
  }
  return Verdict(manifest, problems, notes);
}

/// [env]'s text with [envKey] set to [url], replacing an existing line.
String withAddress(String env, String url) {
  final line = '$envKey=$url';
  final pattern = RegExp('^${RegExp.escape(envKey)}=.*\$', multiLine: true);
  if (pattern.hasMatch(env)) return env.replaceFirst(pattern, line);
  final sep = env.isEmpty || env.endsWith('\n') ? '' : '\n';
  return '$env$sep$line\n';
}

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final envAt = args.indexOf('--env');
  if (positional.isEmpty || (envAt >= 0 && envAt + 1 >= args.length)) {
    stderr.writeln('usage: dart run tool/verify_hausa_manifest.dart <manifest url> [--env <.env file>]');
    exit(64);
  }
  final url = positional.first;
  final envFile = envAt >= 0 ? File(args[envAt + 1]) : null;

  final scratch = Directory.systemTemp.createTempSync('hausa_verify_');
  try {
    stdout.writeln('checking $url');
    final v = await verify(url, scratch);
    final m = v.manifest;
    if (m != null) {
      stdout.writeln('  version ${m.version}, ${m.files.length} files, '
          '${(m.totalBytes / 1e6).toStringAsFixed(1)} MB, word error ${m.wer ?? "not given"}');
      for (final f in m.files) {
        stdout.writeln('    ${f.name}  ${f.size} bytes  ${f.sha256.substring(0, 12)}…');
      }
    }
    for (final n in v.notes) {
      stdout.writeln('  note: $n');
    }
    if (!v.ok) {
      for (final p in v.problems) {
        stderr.writeln('  PROBLEM: $p');
      }
      stderr.writeln('not ready: do not point the app at this address.');
      exit(1);
    }
    stdout.writeln('ready: every file downloaded and matched its size and SHA-256.');
    if (envFile != null) {
      final before = envFile.existsSync() ? envFile.readAsStringSync() : '';
      envFile.writeAsStringSync(withAddress(before, url));
      stdout.writeln('wrote $envKey to ${envFile.path}');
    } else {
      stdout.writeln('put this in the .env the app is built with:\n  $envKey=$url');
    }
  } finally {
    scratch.deleteSync(recursive: true);
  }
}

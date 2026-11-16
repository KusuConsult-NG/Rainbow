/// Guardian phase 3: the Hausa speech model, downloaded when a person
/// switches Hausa on.
///
/// The model is trained by training/hausa/ and published to Hugging Face with
/// a manifest.json beside it: the three file names, their sizes and SHA-256.
/// This reads that manifest from the address in `.env`
/// (GUARDIAN_HAUSA_MANIFEST_URL), downloads each file to a `.part`, checks its
/// size and hash, and only then puts it in place. A file that does not match
/// is deleted, never loaded: a truncated or altered model would mishear
/// distress, which is worse than not listening in Hausa at all.
///
/// Plain Dart (http, crypto, dart:io), so it is tested without a phone.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// What the app needs from a published model, in the order it uses them.
const List<String> hausaModelFiles = [
  'hausa-encoder.int8.onnx',
  'hausa-decoder.int8.onnx',
  'hausa-tokens.txt',
];

class HausaModelFile {
  const HausaModelFile(this.name, this.size, this.sha256);
  final String name;
  final int size;
  final String sha256;
}

class HausaModelManifest {
  const HausaModelManifest({required this.version, required this.files, this.wer});

  final String version;
  final List<HausaModelFile> files;

  /// Word error rate measured when it was published, if recorded.
  final double? wer;

  int get totalBytes => files.fold(0, (s, f) => s + f.size);

  /// Parses and checks a manifest. Throws [FormatException] for anything the
  /// app should not trust: another language, a missing or unexpected file, a
  /// name that could escape the model folder, or a malformed size or hash.
  static HausaModelManifest parse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const FormatException('the manifest is not JSON');
    }
    if (json is! Map<String, dynamic>) throw const FormatException('the manifest is not an object');
    if (json['language'] != 'ha') throw const FormatException('the manifest is not for Hausa');
    final version = json['version'];
    if (version is! String || !RegExp(r'^[0-9A-Za-z._-]{1,40}$').hasMatch(version)) {
      throw const FormatException('the manifest has no usable version');
    }
    final raw = json['files'];
    if (raw is! List) throw const FormatException('the manifest lists no files');
    final files = <HausaModelFile>[];
    for (final f in raw) {
      if (f is! Map<String, dynamic>) throw const FormatException('a file entry is not an object');
      final name = f['name'];
      final size = f['size'];
      final hash = f['sha256'];
      if (name is! String || !hausaModelFiles.contains(name)) {
        throw FormatException('unexpected file in the manifest: $name');
      }
      if (size is! int || size <= 0 || size > 1024 * 1024 * 1024) {
        throw FormatException('$name: size is not usable');
      }
      if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
        throw FormatException('$name: sha256 is not usable');
      }
      files.add(HausaModelFile(name, size, hash));
    }
    final names = files.map((f) => f.name).toSet();
    if (names.length != files.length || !names.containsAll(hausaModelFiles)) {
      throw const FormatException('the manifest does not list exactly the three model files');
    }
    final wer = json['wer'];
    return HausaModelManifest(
      version: version,
      files: files,
      wer: wer is num ? wer.toDouble() : null,
    );
  }
}

/// Downloads, verifies, finds and removes the Hausa model on disk.
class HausaModelStore {
  HausaModelStore({required this.root, required this.manifestUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// The folder models live under, e.g. <app support>/guardian_models.
  final Directory root;

  /// Where manifest.json is published. Null or empty: Hausa is not offered.
  final String? manifestUrl;
  final http.Client _client;

  bool get offered => (manifestUrl ?? '').startsWith('https://');

  Directory _dirFor(String version) => Directory('${root.path}/hausa-$version');

  /// The folder of a complete, verified model on this phone, or null.
  Future<String?> installed() async {
    if (!root.existsSync()) return null;
    for (final d in root.listSync().whereType<Directory>()) {
      final name = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!name.startsWith('hausa-')) continue;
      if (File('${d.path}/.complete').existsSync() &&
          hausaModelFiles.every((f) => File('${d.path}/$f').existsSync())) {
        return d.path;
      }
    }
    return null;
  }

  /// Reads the published manifest.
  Future<HausaModelManifest> fetchManifest() async {
    if (!offered) throw StateError('no Hausa model address is configured');
    final r = await _client.get(Uri.parse(manifestUrl!)).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw HttpException('manifest: HTTP ${r.statusCode}');
    return HausaModelManifest.parse(r.body);
  }

  /// Downloads every file of [m], verifying each. Reports progress as bytes
  /// done out of [HausaModelManifest.totalBytes]. Returns the model folder.
  /// On any failure nothing half-done is left behind, and the model already
  /// on the phone, even the same version, is only replaced once the new one
  /// is complete and verified.
  Future<String> download(HausaModelManifest m, {void Function(int done, int total)? onProgress}) async {
    final target = _dirFor(m.version);
    // Downloaded beside the installed model, never into it. This used to
    // delete the target first, so re-downloading the version already
    // installed and failing part-way left the phone with no Hausa at all.
    // installed() ignores this folder: it has no .complete until the swap.
    final dir = Directory('${target.path}.downloading');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final base = Uri.parse(manifestUrl!);
    var done = 0;
    try {
      for (final f in m.files) {
        final part = File('${dir.path}/${f.name}.part');
        final req = http.Request('GET', base.resolve(f.name));
        final res = await _client.send(req).timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) throw HttpException('${f.name}: HTTP ${res.statusCode}');
        final sink = part.openWrite();
        final hasher = _DigestSink<Digest>();
        final hashing = sha256.startChunkedConversion(hasher);
        var got = 0;
        try {
          await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
            got += chunk.length;
            if (got > f.size) throw HttpException('${f.name}: larger than the manifest says');
            sink.add(chunk);
            hashing.add(chunk);
            done += chunk.length;
            onProgress?.call(done, m.totalBytes);
          }
        } finally {
          await sink.close();
          hashing.close();
        }
        if (got != f.size) throw HttpException('${f.name}: got $got bytes, expected ${f.size}');
        final digest = hasher.events.single.toString();
        if (digest != f.sha256) throw HttpException('${f.name}: checksum does not match');
        part.renameSync('${dir.path}/${f.name}');
      }
      // Verified. Only now does the old copy of this version make way.
      if (target.existsSync()) target.deleteSync(recursive: true);
      dir.renameSync(target.path);
      File('${target.path}/.complete').writeAsStringSync(m.version);
    } on Object {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      rethrow;
    }
    for (final d in root.listSync().whereType<Directory>()) {
      if (d.path != target.path && d.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('hausa-')) {
        d.deleteSync(recursive: true);
      }
    }
    return target.path;
  }

  /// Removes every Hausa model from the phone.
  Future<void> remove() async {
    if (!root.existsSync()) return;
    for (final d in root.listSync().whereType<Directory>()) {
      if (d.uri.pathSegments.where((s) => s.isNotEmpty).last.startsWith('hausa-')) {
        d.deleteSync(recursive: true);
      }
    }
  }
}

/// Collects a chunked conversion's output (the digest).
class _DigestSink<T> implements Sink<T> {
  final List<T> events = [];
  @override
  void add(T event) => events.add(event);
  @override
  void close() {}
}

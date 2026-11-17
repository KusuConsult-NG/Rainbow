// tool/verify_hausa_manifest.dart is what stands between the GPU run's
// published model and every phone that taps *Download Hausa*. It must pass a
// good model, refuse every way a published one can be wrong, and write the
// address into .env only after passing.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../tool/verify_hausa_manifest.dart';

void main() {
  const url = 'https://huggingface.co/example/guardian-hausa/resolve/main/manifest.json';
  late Directory scratch;
  late Map<String, List<int>> files;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('verify_hausa_test');
    files = {
      'hausa-encoder.int8.onnx': List.filled(1000, 1),
      'hausa-decoder.int8.onnx': List.filled(3000, 2),
      'hausa-tokens.txt': utf8.encode('a 1\nb 2\n'),
    };
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  String manifest({Object? wer = 0.21, Map<String, String>? hashes, String language = 'ha'}) => jsonEncode({
        'version': '202611180900',
        'language': language,
        'wer': wer,
        'files': [
          for (final e in files.entries)
            {'name': e.key, 'size': e.value.length, 'sha256': hashes?[e.key] ?? sha256.convert(e.value).toString()},
        ],
      });

  http.Client serve(String body, [Map<String, List<int>>? served]) => MockClient.streaming((req, _) async {
        final name = req.url.pathSegments.last;
        if (name == 'manifest.json') return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
        final bytes = (served ?? files)[name];
        if (bytes == null) return http.StreamedResponse(const Stream.empty(), 404);
        return http.StreamedResponse(Stream.value(bytes), 200);
      });

  test('a good model is ready', () async {
    final v = await verify(url, scratch, client: serve(manifest()));
    expect(v.problems, isEmpty);
    expect(v.ok, isTrue);
    expect(v.manifest!.version, '202611180900');
  });

  test('a usable but weak model passes with a note', () async {
    final v = await verify(url, scratch, client: serve(manifest(wer: 0.42)));
    expect(v.ok, isTrue);
    expect(v.notes.single, contains('0.42'));
  });

  test('a model above the publishing limit is refused', () async {
    final v = await verify(url, scratch, client: serve(manifest(wer: 0.61)));
    expect(v.ok, isFalse);
    expect(v.problems.single, contains('above 0.5'));
  });

  test('a model nobody evaluated is refused', () async {
    final v = await verify(url, scratch, client: serve(manifest(wer: null)));
    expect(v.ok, isFalse);
    expect(v.problems.single, contains('no word error rate'));
  });

  test('a file whose checksum does not match is refused', () async {
    final v = await verify(url, scratch,
        client: serve(manifest(hashes: {'hausa-decoder.int8.onnx': 'a' * 64})));
    expect(v.ok, isFalse);
    expect(v.problems.single, contains('checksum'));
  });

  test('a missing file is refused', () async {
    final v = await verify(url, scratch,
        client: serve(manifest(), {...files}..remove('hausa-tokens.txt')));
    expect(v.ok, isFalse);
    expect(v.problems.single, contains('404'));
  });

  test('a manifest the app would not parse is refused', () async {
    final v = await verify(url, scratch, client: serve(manifest(language: 'yo')));
    expect(v.ok, isFalse);
    expect(v.problems.single, contains('not for Hausa'));
  });

  test('an address that is not https is refused before anything is fetched', () async {
    final v = await verify('http://example.com/manifest.json', scratch,
        client: MockClient((_) async => fail('fetched')));
    expect(v.ok, isFalse);
    expect(v.problems.single, contains('https://'));
  });

  group('writing the address into .env', () {
    test('replaces an empty line in place', () {
      const env = 'SUPABASE_URL=x\nGUARDIAN_HAUSA_MANIFEST_URL=\nOTHER=y\n';
      expect(withAddress(env, url), 'SUPABASE_URL=x\nGUARDIAN_HAUSA_MANIFEST_URL=$url\nOTHER=y\n');
    });

    test('replaces an old address', () {
      const env = 'GUARDIAN_HAUSA_MANIFEST_URL=https://old/manifest.json\n';
      expect(withAddress(env, url), 'GUARDIAN_HAUSA_MANIFEST_URL=$url\n');
    });

    test('adds the line when there is none', () {
      expect(withAddress('A=1', url), 'A=1\nGUARDIAN_HAUSA_MANIFEST_URL=$url\n');
      expect(withAddress('', url), 'GUARDIAN_HAUSA_MANIFEST_URL=$url\n');
    });
  });
}

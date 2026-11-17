import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rainbow_app/core/guardian/hausa_model.dart';

/// The Hausa model is downloaded, and a model that is not exactly what was
/// published must never be loaded: it would mishear distress.
void main() {
  const url = 'https://huggingface.co/example/guardian-hausa/resolve/main/manifest.json';
  late Directory root;
  late Map<String, List<int>> files;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hausa_model_test');
    files = {
      'hausa-encoder.int8.onnx': List.filled(1000, 1),
      'hausa-decoder.int8.onnx': List.filled(3000, 2),
      'hausa-tokens.txt': utf8.encode('a 1\nb 2\n'),
    };
  });
  tearDown(() => root.deleteSync(recursive: true));

  String manifestFor(Map<String, List<int>> f, {String language = 'ha', Map<String, String>? hashes}) =>
      jsonEncode({
        'version': '202611150900',
        'language': language,
        'wer': 0.21,
        'files': [
          for (final e in f.entries)
            {'name': e.key, 'size': e.value.length, 'sha256': hashes?[e.key] ?? sha256.convert(e.value).toString()},
        ],
      });

  http.Client serve(String manifest, Map<String, List<int>> f) => MockClient.streaming((req, _) async {
        final name = req.url.pathSegments.last;
        if (name == 'manifest.json') {
          return http.StreamedResponse(Stream.value(utf8.encode(manifest)), 200);
        }
        final body = f[name];
        if (body == null) return http.StreamedResponse(const Stream.empty(), 404);
        return http.StreamedResponse(Stream.fromIterable([body.sublist(0, body.length ~/ 2), body.sublist(body.length ~/ 2)]), 200);
      });

  test('a verified download is installed and found again', () async {
    final store = HausaModelStore(root: root, manifestUrl: url, client: serve(manifestFor(files), files));
    expect(await store.installed(), isNull);
    final m = await store.fetchManifest();
    expect(m.totalBytes, 1000 + 3000 + files['hausa-tokens.txt']!.length);
    expect(m.wer, 0.21);
    final progress = <int>[];
    final dir = await store.download(m, onProgress: (d, _) => progress.add(d));
    expect(progress.last, m.totalBytes);
    expect(await store.installed(), dir);
    expect(File('$dir/hausa-decoder.int8.onnx').lengthSync(), 3000);
  });

  // A re-download of the version already installed used to delete the working
  // model before the new copy had arrived, so a failed re-download left the
  // phone with no Hausa at all.
  test('a failed re-download of the same version keeps the working model', () async {
    final good = HausaModelStore(root: root, manifestUrl: url, client: serve(manifestFor(files), files));
    final dir = await good.download(await good.fetchManifest());

    final broken = Map.of(files)..['hausa-decoder.int8.onnx'] = List.filled(10, 9);
    final bad = HausaModelStore(root: root, manifestUrl: url, client: serve(manifestFor(files), broken));
    await expectLater(bad.download(await bad.fetchManifest()), throwsA(isA<HttpException>()));

    expect(await good.installed(), dir);
    expect(File('$dir/hausa-decoder.int8.onnx').lengthSync(), 3000);
    expect(root.listSync().whereType<Directory>().map((d) => d.path), [dir],
        reason: 'nothing half-done is left beside it');
  });

  test('a file whose checksum does not match is rejected and nothing is left', () async {
    final wrong = {'hausa-decoder.int8.onnx': 'f' * 64};
    final store = HausaModelStore(root: root, manifestUrl: url, client: serve(manifestFor(files, hashes: wrong), files));
    final m = await store.fetchManifest();
    await expectLater(store.download(m), throwsA(isA<HttpException>()));
    expect(await store.installed(), isNull);
    expect(root.listSync(), isEmpty);
  });

  test('a truncated file is rejected', () async {
    final short = Map.of(files)..['hausa-encoder.int8.onnx'] = List.filled(400, 1);
    final store = HausaModelStore(root: root, manifestUrl: url, client: serve(manifestFor(files), short));
    await expectLater(store.download(await store.fetchManifest()), throwsA(isA<HttpException>()));
    expect(await store.installed(), isNull);
  });

  test('a file larger than published is rejected as it arrives', () async {
    final long = Map.of(files)..['hausa-encoder.int8.onnx'] = List.filled(5000, 1);
    final store = HausaModelStore(root: root, manifestUrl: url, client: serve(manifestFor(files), long));
    await expectLater(store.download(await store.fetchManifest()), throwsA(isA<HttpException>()));
  });

  group('manifests the app refuses', () {
    test('another language', () {
      expect(() => HausaModelManifest.parse(manifestFor(files, language: 'yo')), throwsFormatException);
    });
    test('a name that could leave the model folder', () {
      final evil = {...files, '../evil.onnx': [1]};
      expect(() => HausaModelManifest.parse(manifestFor(evil)), throwsFormatException);
    });
    test('a missing model file', () {
      final partial = Map.of(files)..remove('hausa-tokens.txt');
      expect(() => HausaModelManifest.parse(manifestFor(partial)), throwsFormatException);
    });
    test('not JSON', () => expect(() => HausaModelManifest.parse('<html>'), throwsFormatException));
  });

  test('with no address configured, Hausa is not offered', () {
    expect(HausaModelStore(root: root, manifestUrl: '').offered, isFalse);
    expect(HausaModelStore(root: root, manifestUrl: 'http://insecure/manifest.json').offered, isFalse);
    expect(HausaModelStore(root: root, manifestUrl: url).offered, isTrue);
  });

  test('remove deletes it', () async {
    final store = HausaModelStore(root: root, manifestUrl: url, client: serve(manifestFor(files), files));
    await store.download(await store.fetchManifest());
    await store.remove();
    expect(await store.installed(), isNull);
  });
}

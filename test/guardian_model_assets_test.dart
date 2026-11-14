import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_app/core/guardian/offline_transcriber.dart';

/// The bundled speech models are what Guardian listens with. A file swapped
/// or truncated by accident would make Guardian deaf, or hear differently
/// from what was measured, with nothing failing until a real emergency.
void main() {
  final dir = Directory('assets/guardian');
  final licences = File('assets/guardian/LICENSES.md').readAsStringSync();
  final recorded = {
    for (final m in RegExp(r'^([0-9a-f]{64})  (\S+)$', multiLine: true).allMatches(licences))
      m.group(2)!: m.group(1)!,
  };

  test('every model file the transcriber loads is bundled', () {
    for (final name in GuardianModelFiles.all) {
      expect(File('${dir.path}/$name').existsSync(), isTrue, reason: name);
    }
  });

  test('every model file matches the checksum recorded with its licence', () {
    expect(recorded.keys.toSet(), GuardianModelFiles.all.toSet());
    for (final name in GuardianModelFiles.all) {
      final digest = sha256.convert(File('${dir.path}/$name').readAsBytesSync()).toString();
      expect(digest, recorded[name], reason: '$name changed: re-measure with tool/guardian_eval.dart, then update LICENSES.md');
    }
  });

  test('the folder is declared as an asset, so it ships in the app', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/guardian/'));
  });
}

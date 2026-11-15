/// Puts Guardian's bundled speech models where the native recognizer can
/// read them.
///
/// The recognizer opens files by path; Flutter assets are not files on a
/// phone. So the first time Guardian starts, the models are copied out of the
/// app bundle into the app's private support folder, and every later start
/// reuses them. A copy that was interrupted (the phone died half way) is
/// detected by size and redone, never used.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rainbow_app/core/guardian/offline_transcriber.dart';

class GuardianModels {
  GuardianModels._();

  /// Bump when the bundled models change, so old copies are not reused.
  static const String version = 'en-small-2023-06-26';

  static Future<String>? _ready;

  /// The folder holding the models, copying them there first if needed.
  /// Throws if they cannot be put in place.
  static Future<String> install() =>
      _ready ??= _install().catchError((Object e, StackTrace s) {
        _ready = null; // Let the next start try again.
        Error.throwWithStackTrace(e, s);
      });

  static Future<String> _install() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/guardian_models/$version');
    await dir.create(recursive: true);
    for (final name in GuardianModelFiles.all) {
      final data = await rootBundle.load('assets/guardian/$name');
      final file = File('${dir.path}/$name');
      if (file.existsSync() && file.lengthSync() == data.lengthInBytes) {
        continue;
      }
      final part = File('${file.path}.part');
      await part.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await part.rename(file.path);
    }
    // Earlier model versions are dead weight once this one is in place.
    await for (final old in dir.parent.list()) {
      if (old is Directory && old.path != dir.path) {
        try {
          await old.delete(recursive: true);
        } on Object catch (_) {}
      }
    }
    return dir.path;
  }
}

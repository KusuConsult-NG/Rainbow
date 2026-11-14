// Runs before every test file (Flutter's test config hook).
//
// WHY: 29 widget tests failed with "An animation is still running even after
// the widget tree was disposed". Nothing in those screens was animating. The
// app styles its text with google_fonts, which loads the bundled Outfit and
// Inter files (assets/google_fonts/) asynchronously the first time a weight is
// used. The load finished AFTER a short test had ended, the engine announced
// the new fonts, and the text widgets scheduled a relayout on a tree that no
// longer existed — which the test binding reports as a failure.
//
// So every weight the app uses is loaded once, here, before any test runs.
// Later uses find it already loaded, nothing arrives late, and the tests test
// what they were written to test.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Same as main.dart: the fonts are bundled, never fetched.
  GoogleFonts.config.allowRuntimeFetching = false;

  // The weights bundled in assets/google_fonts/, for both families.
  const weights = [
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
    FontWeight.w700,
    FontWeight.w800,
    FontWeight.w900,
  ];
  for (final w in weights) {
    GoogleFonts.outfit(fontWeight: w);
    GoogleFonts.inter(fontWeight: w);
  }
  try {
    await GoogleFonts.pendingFonts();
  } on Object catch (e) {
    // A weight that is not bundled. Tests still run; the screen that asks for
    // it falls back to the nearest weight, as it would on a phone.
    debugPrint('[test config] a font did not preload: $e');
  }

  await testMain();
}

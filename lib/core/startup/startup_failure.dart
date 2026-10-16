// WHY THIS FILE EXISTS: the blank page.
//
// An installed release APK opened to a featureless pale page and stopped
// there. Not a crash — the process stayed up, nothing moved, and no error
// was shown. That is not a mystery once you read what Flutter does with an
// exception thrown during `build()` in a RELEASE build:
//
//   * `ErrorWidget.builder` defaults to `_defaultErrorWidgetBuilder`, which
//     composes its message INSIDE `assert(() { ... }())`
//     (flutter/lib/src/widgets/framework.dart:5680-5692). Asserts are
//     stripped from a release build, so `message` stays `''`.
//   * `RenderErrorBox('')` therefore sets `_paragraph = null`
//     (flutter/lib/src/rendering/error.dart:37-60) and paints no text at all.
//   * What it does paint is `backgroundColor`, which outside an assert is
//     `const Color(0xF0C0C0C0)` — pale grey (error.dart:112-117, 156).
//
// So in release, ANY exception from ANY `build()` in the tree renders a
// silent pale rectangle. In debug the same exception gives the familiar red
// panel with the message on it, which is why this was invisible in testing
// and total in the field.
//
// This app cannot ship that. A citizen holding a phone during an emergency
// gets no instruction from a blank page — not even "something is broken, try
// again". Everything here exists to make sure the first frame always says
// something a person can act on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rainbow_app/core/theme/app_colors.dart';
import 'package:rainbow_app/shared/localization/translations.dart';


/// Runs one start-up step and refuses to let it stop the app from starting.
///
/// `main()` used to do its platform work as a straight run of statements
/// inside `runZonedGuarded`, with `runApp` last. A throw from any step — a
/// plugin that failed to register, a platform channel that rejected a call —
/// jumped to the zone handler, which logged it. `runApp` was then never
/// reached, no Flutter frame was ever produced, and the window kept showing
/// the launch background: a blank page, permanently.
///
/// Every step that is not needed to draw the first frame goes through here.
/// [label] names the step in the log so a failure is identifiable without a
/// stack trace.
Future<void> runStartupStep(
  String label,
  Future<void> Function() body,
) async {
  try {
    await body();
  } catch (error, stackTrace) {
    debugPrint('⚠️ [STARTUP] $label failed: $error');
    debugPrintStack(stackTrace: stackTrace, label: label);
  }
}

/// Runs a step the app cannot be built without, in bounded time.
///
/// Returns null on success, or what went wrong — a [TimeoutException] when the
/// step simply never finished.
///
/// The distinction matters because the first version of this file bounded
/// every OPTIONAL step and left the one required step — `SupabaseConfig.init`
/// — in a bare try/catch, on the reasoning that it does no network I/O and so
/// cannot hang. A try/catch catches a throw. It does not catch a step that
/// never completes, and a step that never completes before `runApp` is the
/// same blank page as one that throws: no Flutter frame is ever produced.
///
/// `Supabase.initialize` does not reach the network, but it does read local
/// storage and call platform channels, and the browser harness showed a way
/// for that to stall: clearing the origin's storage while initialization was
/// reading it. "It cannot hang" was an argument, not a bound.
Future<Object?> runRequiredStartupStep(
  String label,
  Future<void> Function() body, {
  required Duration limit,
}) async {
  try {
    await body().timeout(limit);
    return null;
  } catch (error, stackTrace) {
    debugPrint('🔥 [STARTUP] $label failed: $error');
    debugPrintStack(stackTrace: stackTrace, label: label);
    return error;
  }
}

/// Replaces Flutter's silent release error box with a screen that talks.
///
/// Call this before `runApp`. After it, an exception thrown during any
/// `build()` anywhere in the tree renders [StartupFailureScreen] carrying the
/// exception's own text — which survives a release build, unlike the default
/// builder's message — instead of the pale rectangle described above.
void installReadableErrorWidget() {
  ErrorWidget.builder = (details) => StartupFailureScreen(
        error: details.exception,
        stage: 'drawing the screen',
      );
}

/// The screen shown when the app cannot start, or when a `build()` threw.
///
/// Deliberately built from the smallest possible set of widgets. It is
/// installed as [ErrorWidget.builder], so it can be asked to render in place
/// of ANY widget in the tree — including above `MaterialApp`, where there is
/// no `Theme`, no `Directionality`, no `MediaQuery` and no `Material`. Nothing
/// here needs an inherited widget, and the one asset it loads has an
/// `errorBuilder`, because a screen whose job is to report a failure must not
/// be able to fail.
class StartupFailureScreen extends StatelessWidget {
  /// Creates the failure screen.
  ///
  /// [stage] names what the app was doing, in a few words, and is shown to the
  /// user. [onRetry] adds a retry control; omit it where retrying cannot help,
  /// such as a broken widget tree.
  const StartupFailureScreen({
    required this.error,
    required this.stage,
    this.onRetry,
    super.key,
  });

  /// The thing that went wrong. Its `toString()` is shown verbatim so the user
  /// has something concrete to report, and so a log is not the only record.
  final Object error;

  /// What the app was doing when it failed, in a few words.
  final String stage;

  /// Called when the user asks to try again, or null for no retry control.
  final VoidCallback? onRetry;

  /// How deeply this screen is currently nested inside itself.
  ///
  /// If this screen were ever to throw while rendering, Flutter would ask
  /// [ErrorWidget.builder] for a replacement and get this screen again, for
  /// ever. One level down it falls back to a bare coloured box with text,
  /// which cannot fail.
  static int _depth = 0;

  @override
  Widget build(BuildContext context) {
    if (_depth > 0) return _bareFallback();
    _depth++;
    try {
      return _full();
    } finally {
      _depth--;
    }
  }

  Widget _bareFallback() => const Directionality(
        textDirection: TextDirection.ltr,
        // No Center, no Column: this fallback must lay out under ANY
        // constraints, including the unbounded ones it could be handed if it
        // replaced a widget inside a Row or a scroll view.
        child: ColoredBox(
          color: AppColors.background,
          child: Text(
            'Plateau Eye could not start.',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
        ),
      );

  Widget _full() {
    const title = TextStyle(
      color: AppColors.primary,
      fontSize: 22,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );
    const subtitle = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 13,
      height: 1.4,
    );
    const body = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 15,
      height: 1.45,
    );
    const detail = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 11,
      height: 1.4,
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: AppColors.background,
        child: Padding(
          // Hard-coded rather than taken from MediaQuery: this screen can be
          // asked to draw above the widget that provides it.
          padding: const EdgeInsets.fromLTRB(28, 88, 28, 40),
          child: Column(
            // `min`, so the screen still lays out if it is asked to draw
            // somewhere with no bounded height to fill.
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 96,
                child: Image.asset(
                  'assets/images/app_icon_large.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                Translations.get('startup_failed_title', AppLanguage.english),
                style: title,
              ),
              const SizedBox(height: 8),
              // The same sentence in Hausa and Pidgin. A person who reads
              // neither English nor a blank page should still learn that the
              // app is broken rather than that their phone is.
              Text(
                '${Translations.get('startup_failed_title', AppLanguage.hausa)}'
                '  ·  '
                '${Translations.get(
                  'startup_failed_title',
                  AppLanguage.pidgin,
                )}',
                style: subtitle,
              ),
              const SizedBox(height: 24),
              Text(
                Translations.get('startup_failed_body', AppLanguage.english),
                style: body,
              ),
              const SizedBox(height: 20),
              Text('Failed while $stage.', style: detail),
              const SizedBox(height: 6),
              Text('$error', style: detail),
              if (onRetry != null) ...[
                const SizedBox(height: 32),
                _RetryControl(onRetry: onRetry!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tap target that needs no `Material` ancestor.
class _RetryControl extends StatelessWidget {
  const _RetryControl({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
          child: Text(
            Translations.get('startup_failed_retry', AppLanguage.english),
            style: const TextStyle(
              color: AppColors.onPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

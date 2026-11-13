/// Triple-tap detection for the SOS control.
///
/// One tap sent a Silent SOS, which is how a phone in a pocket files an
/// emergency. Three deliberate taps inside a short window is the gesture now,
/// on every surface that carries an SOS control — the bottom bar, the home
/// screen and the lock screen — and one or two taps transmit nothing.
///
/// Pure, so the rule can be tested without a widget: the caller supplies the
/// time of each tap.
library;

/// How long the three taps may take, first to third.
const Duration sosTapWindow = Duration(seconds: 3);

/// Taps needed to send.
const int sosTapsRequired = 3;

class TripleTapDetector {
  TripleTapDetector({
    this.window = sosTapWindow,
    this.required = sosTapsRequired,
  });

  final Duration window;
  final int required;

  final List<DateTime> _taps = <DateTime>[];

  /// Taps currently counting towards an activation.
  int get count => _taps.length;

  /// Records a tap at [at]. Returns true on the tap that completes the
  /// gesture, and starts again from nothing after it — a fourth tap is the
  /// first of a new sequence, never a second activation.
  bool tap(DateTime at) {
    _taps
      ..removeWhere((t) => at.difference(t) > window || t.isAfter(at))
      ..add(at);
    if (_taps.length < required) return false;
    _taps.clear();
    return true;
  }

  void reset() => _taps.clear();
}

/// Volume Down pressed three times raises a Silent SOS.
///
/// WHAT THIS DOES AND DOES NOT COVER. Flutter is handed hardware key presses
/// only while the app is open and on screen. So this works with Plateau Eye in
/// the foreground — screen on, any screen of the app — and NOT with the app in
/// the background, the phone locked, or the screen off. Reaching those states
/// on Android needs an accessibility service, which Google Play restricts; on
/// iPhone it is not available to ordinary apps at all.
///
/// OFF BY DEFAULT. Pressing Volume Down three times quickly is also how people
/// turn a phone down, so a user who wants it switches it on in Settings.
///
/// The press is never consumed: the volume still changes, as it would for
/// anyone watching, and the SOS is sent silently behind it.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/sos/triple_tap.dart';
import 'package:rainbow_app/providers/auth_provider.dart';
import 'package:rainbow_app/providers/emergency_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String volumeSosPreferenceKey = 'volume_sos_enabled';

final volumeSosEnabledProvider =
    StateNotifierProvider<VolumeSosSetting, bool>((ref) => VolumeSosSetting());

class VolumeSosSetting extends StateNotifier<bool> {
  VolumeSosSetting() : super(false) {
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = prefs.getBool(volumeSosPreferenceKey) ?? false;
    } on Object catch (_) {
      // Unreadable preference: stay off, which is the safe default.
    }
  }

  Future<void> set(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(volumeSosPreferenceKey, enabled);
    } on Object catch (_) {}
  }
}

/// Listens for Volume Down anywhere in the app. Wraps the whole app once.
class VolumeSosListener extends ConsumerStatefulWidget {
  const VolumeSosListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<VolumeSosListener> createState() => _VolumeSosListenerState();
}

class _VolumeSosListenerState extends ConsumerState<VolumeSosListener> {
  // Its own count, not the screen's: two taps on the SOS button and one
  // volume press are not three deliberate presses of anything.
  final TripleTapDetector _presses = TripleTapDetector();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    // Down only: holding the key sends repeats, and a held key is not three
    // presses.
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.audioVolumeDown) return false;
    if (!ref.read(volumeSosEnabledProvider)) return false;
    if (ref.read(authProvider).user == null) return false;
    if (ref.read(emergencyProvider).isEmergencyActive) {
      _presses.reset();
      return false;
    }
    if (_presses.tap(DateTime.now())) {
      unawaited(HapticFeedback.selectionClick());
      unawaited(
        ref.read(emergencyProvider.notifier).startEmergency(silent: true),
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Watched here so the saved setting is read at start-up. Read lazily on
    // the first key press instead, it was still loading, and that press
    // counted for nothing.
    ref.watch(volumeSosEnabledProvider);
    return widget.child;
  }
}

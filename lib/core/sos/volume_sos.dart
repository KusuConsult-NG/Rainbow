/// Volume Down pressed three times raises a Silent SOS.
///
/// WHAT THIS DOES AND DOES NOT COVER. Flutter is handed hardware key presses
/// only while the app is open and on screen, so [VolumeSosListener] covers
/// Plateau Eye in the foreground — screen on, any screen of the app.
///
/// WITH THE PHONE LOCKED, OR THE APP OFF SCREEN: Android only, and only once
/// the person has also switched on "Plateau Eye: Volume Down SOS" in Android's
/// Accessibility settings (VolumeSosAccessibilityService.kt). That service
/// counts the presses natively and hands the SOS here ([VolumeSosLockScreen]),
/// so it goes through the same [EmergencyNotifier.startEmergency]. Google Play
/// restricts accessibility services that are not disability tools: publishing
/// there needs its declaration form and the in-app disclosure Settings shows.
/// Whether presses reach it with the screen fully OFF depends on the phone;
/// locked with the screen on, they do. iPhone offers ordinary apps no way to
/// do this at all.
///
/// OFF BY DEFAULT. Pressing Volume Down three times quickly is also how people
/// turn a phone down, so a user who wants it switches it on in Settings.
///
/// The press is never consumed: the volume still changes, as it would for
/// anyone watching, and the SOS is sent silently behind it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// The Android accessibility service's side of Volume Down ×3: whether it is
/// switched on, where to switch it on, and the presses it hands over.
class VolumeSosLockScreen {
  VolumeSosLockScreen({MethodChannel? channel, bool? supported})
      : _channel = channel ?? const MethodChannel(channelName),
        supported = supported ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static const String channelName = 'com.operationrainbow.app/volume_sos';

  /// A press handed over later than this is not sent: whoever pressed it has
  /// had two minutes to be helped some other way, and an SOS arriving from
  /// nowhere long afterwards sends a responder to where they no longer are.
  static const Duration pendingLimit = Duration(minutes: 2);

  final MethodChannel _channel;

  /// Android. Elsewhere there is no service and every call is a no-op.
  final bool supported;

  /// Whether the person has switched the service on in Accessibility settings.
  Future<bool> isServiceEnabled() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// Opens Android's Accessibility settings, where the service is switched on.
  Future<bool> openSettings() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('openAccessibilitySettings') ?? false;
    } on Object catch (_) {
      return false;
    }
  }

  /// How long ago a press arrived that has not been sent, taking it; null for
  /// none. Set when the service had to start the app to deliver it.
  Future<Duration?> takePending() async {
    if (!supported) return null;
    try {
      final ms = await _channel.invokeMethod<int>('takePending') ?? -1;
      return ms < 0 ? null : Duration(milliseconds: ms);
    } on Object catch (_) {
      return null;
    }
  }

  /// [onPress] runs for each Volume Down ×3 the service hands over while the
  /// app is running.
  void listen(Future<void> Function() onPress) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      // Acknowledged at once: from here the press is Dart's to send, and the
      // native side must not hold it as pending while sign-in is restored.
      if (call.method == 'trigger') unawaited(onPress());
      return null;
    });
  }

  void stop() {
    if (supported) _channel.setMethodCallHandler(null);
  }
}

final volumeSosLockScreenProvider =
    Provider<VolumeSosLockScreen>((ref) => VolumeSosLockScreen());

/// Listens for Volume Down anywhere in the app. Wraps the whole app once.
class VolumeSosListener extends ConsumerStatefulWidget {
  const VolumeSosListener({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<VolumeSosListener> createState() => _VolumeSosListenerState();
}

/// How long a locked-phone press waits for the saved sign-in to be restored.
@visibleForTesting
Duration signInWait = const Duration(seconds: 30);

class _VolumeSosListenerState extends ConsumerState<VolumeSosListener> {
  // Its own count, not the screen's: two taps on the SOS button and one
  // volume press are not three deliberate presses of anything.
  final TripleTapDetector _presses = TripleTapDetector();

  late final VolumeSosLockScreen _lockScreen = ref.read(volumeSosLockScreenProvider);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _lockScreen.listen(_fromService);
    // A press that had to start the app to be delivered.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_takePending()));
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _lockScreen.stop();
    super.dispose();
  }

  Future<void> _takePending() async {
    final age = await _lockScreen.takePending();
    if (age == null || !mounted) return;
    if (age > VolumeSosLockScreen.pendingLimit) {
      debugPrint('[VOLUME_SOS] a locked-phone press ${age.inSeconds} s old was not sent');
      return;
    }
    await _fromService();
  }

  /// Volume Down ×3 from the accessibility service. The service has already
  /// checked the setting, from the same saved value: at a cold start this
  /// screen's copy may not have loaded yet, and must not drop the press.
  Future<void> _fromService() async {
    if (!await _signedIn() || !mounted) {
      debugPrint('[VOLUME_SOS] locked-phone press with nobody signed in: not sent');
      return;
    }
    if (ref.read(emergencyProvider).isEmergencyActive) return;
    unawaited(ref.read(emergencyProvider.notifier).startEmergency(silent: true));
  }

  /// Whether somebody is signed in, waiting for a session still being
  /// restored at start-up, for at most [signInWait].
  Future<bool> _signedIn() async {
    bool? answer(AuthState a) => a.isLoading ? null : a.user != null;
    final now = answer(ref.read(authProvider));
    if (now != null) return now;
    final done = Completer<bool>();
    final sub = ref.listenManual<AuthState>(authProvider, (_, next) {
      final a = answer(next);
      if (a != null && !done.isCompleted) done.complete(a);
    });
    try {
      return await done.future.timeout(signInWait, onTimeout: () => false);
    } finally {
      sub.close();
    }
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

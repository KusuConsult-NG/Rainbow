/// This phone's place in the Bluetooth mesh: when it relays, and how what it
/// carries reaches HQ.
///
/// Everything below this — the radio, chunking, the relay's rules, the gossip
/// schedule — decides HOW the mesh works. This decides WHEN this phone takes
/// part, which is the one question that was still open in
/// docs/OFFLINE_CHANNELS_DESIGN.md ("does a phone relay strangers' alerts by
/// default?"). The answer built here is the one that document recommended:
///
///  * **Responders relay by default.** Carrying emergency traffic is part of
///    the job, and their phones are the ones most often near an incident.
///  * **Citizens opt in**, from Settings, with an explanation. Carrying somebody
///    else's emergency costs battery and is not legally neutral everywhere, so
///    it is not switched on behind a person's back.
///  * **Anyone's OWN emergency uses the mesh regardless.** A citizen who has not
///    opted in still gets the radio switched on for 30 minutes when one of their
///    reports fails to reach HQ, renewed while it is still carrying something —
///    but only if Bluetooth has worked on this phone before. A permission
///    prompt in the middle of an SOS is a door in front of a panic button.
///
/// ## Reaching HQ
///
/// Every phone in the mesh is also a way out of it. Whenever this phone holds
/// envelopes and can reach HQ, it uploads them to `/api/mesh/ingest` — after
/// accepting one, on a timer, and when the app comes back to the foreground —
/// and stops carrying exactly the ones HQ says it is finished with.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:rainbow_app/core/config/app_config.dart';
import 'package:rainbow_app/core/mesh/ble_mesh_transport.dart';
import 'package:rainbow_app/core/mesh/ble_radio.dart';
import 'package:rainbow_app/core/mesh/mesh_node.dart';
import 'package:rainbow_app/core/mesh/mesh_relay.dart';
import 'package:rainbow_app/core/mesh/mesh_uplink.dart';
import 'package:rainbow_app/core/mesh/method_channel_ble_radio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this phone may relay for others: decided here, stored per device.
const String meshRelayPreferenceKey = 'mesh_relay_enabled';

/// Set once the radio has started successfully on this phone, so an emergency
/// knows Bluetooth will not have to ask for anything.
const String meshHasRunPreferenceKey = 'mesh_has_run';

/// How long the radio stays on for a person's own failed report.
const Duration meshEmergencyWindow = Duration(minutes: 30);

/// How many times that window renews while the phone still holds envelopes:
/// six hours, a quarter of the age at which an envelope expires anyway.
const int meshMaxEmergencyWindows = 12;

/// The relaying default, before a person has chosen.
bool meshRelayDefault({required bool isResponder}) => isResponder;

/// Asks for, or checks, what the platform needs before the radio may start.
typedef MeshPermissionCheck = Future<bool> Function({required bool ask});

/// Runs the mesh for this phone.
class MeshService with WidgetsBindingObserver {
  /// Creates a service. Everything platform-facing is injectable for tests.
  MeshService({
    BleRadio Function()? radioFactory,
    http.Client? httpClient,
    MeshPermissionCheck? permissions,
    String? Function()? hqBaseUrl,
    Future<SharedPreferences> Function()? preferences,
    this.uplinkInterval = const Duration(minutes: 2),
    this.peerSettle = const Duration(milliseconds: 50),
  })  : _radioFactory = radioFactory ?? MethodChannelBleRadio.new,
        _http = httpClient ?? http.Client(),
        _permissions = permissions ?? platformMeshPermissions,
        _hqBaseUrl = hqBaseUrl ?? _configuredHqBaseUrl,
        _preferences = preferences ?? SharedPreferences.getInstance;

  /// The app's instance.
  static final MeshService instance = MeshService();

  /// How often a running node tries to upload what it holds.
  final Duration uplinkInterval;

  /// The pause between a peer arriving and offering it everything held, so the
  /// transport has registered the link before anything is written to it.
  final Duration peerSettle;

  final BleRadio Function() _radioFactory;
  final http.Client _http;
  final MeshPermissionCheck _permissions;
  final String? Function() _hqBaseUrl;
  final Future<SharedPreferences> Function() _preferences;

  bool? _isResponder;
  MeshNode? _node;
  BleRadio? _radio;
  StreamSubscription<BlePeerEvent>? _peerSub;
  Timer? _uplinkTimer;
  Timer? _windowTimer;
  int _windowsUsed = 0;
  bool _starting = false;
  bool _uploading = false;
  bool _observing = false;

  /// Whether this phone is in the mesh right now.
  bool get isRunning => _node?.isRelaying ?? false;

  /// The running node, for the offline escalation path; null when stopped.
  MeshNode? get node => isRunning ? _node : null;

  /// Whether a signed-in person is attached.
  bool get isSignedIn => _isResponder != null;

  /// Whether this person relays for others, by their choice or the default.
  Future<bool> relayEnabled() async {
    final prefs = await _preferences();
    return prefs.getBool(meshRelayPreferenceKey) ??
        meshRelayDefault(isResponder: _isResponder ?? false);
  }

  /// Records the person's choice and acts on it. Returns whether the mesh is
  /// running afterwards — false when switched on but Bluetooth was refused.
  // ignore: avoid_positional_boolean_parameters, Mirrors a switch's onChanged.
  Future<bool> setRelayEnabled(bool enabled) async {
    final prefs = await _preferences();
    await prefs.setBool(meshRelayPreferenceKey, enabled);
    if (enabled) return start(ask: true);
    _windowTimer?.cancel();
    _windowTimer = null;
    await stop();
    return false;
  }

  /// Called once a session and a role exist.
  Future<void> onSignedIn({required bool isResponder}) async {
    _isResponder = isResponder;
    _observe();
    try {
      if (await relayEnabled()) await start(ask: isResponder);
    } on Object catch (e) {
      debugPrint('[MESH] could not start at sign-in: $e');
    }
  }

  /// Called on sign-out, or when the session ends. Stops, and forgets what it
  /// was carrying: a phone should not keep relaying for somebody who has left.
  Future<void> onSignedOut() async {
    _isResponder = null;
    _windowTimer?.cancel();
    _windowTimer = null;
    _windowsUsed = 0;
    await stop();
  }

  /// The node to hand a failed report to, starting the radio for a while if it
  /// is not already running. Null when the mesh cannot be used without asking
  /// the person for something in the middle of an emergency.
  Future<MeshNode?> nodeForEmergency() async {
    if (_isResponder == null) return null;
    if (isRunning) return _node;
    try {
      final prefs = await _preferences();
      if (!(prefs.getBool(meshHasRunPreferenceKey) ?? false)) return null;
      if (!await start(ask: false)) return null;
      _windowsUsed = 0;
      _armEmergencyWindow();
      return _node;
    } on Object catch (e) {
      debugPrint('[MESH] could not start for an emergency: $e');
      return null;
    }
  }

  void _armEmergencyWindow() {
    _windowTimer?.cancel();
    _windowTimer = Timer(meshEmergencyWindow, () => unawaited(_emergencyWindowEnded()));
  }

  Future<void> _emergencyWindowEnded() async {
    _windowTimer = null;
    if (!isRunning) return;
    if (await relayEnabled()) return; // They opted in meanwhile: keep relaying.
    _windowsUsed++;
    final stillCarrying = _node?.relay.pending.isNotEmpty ?? false;
    if (stillCarrying && _windowsUsed < meshMaxEmergencyWindows) {
      _armEmergencyWindow();
      return;
    }
    await stop();
  }

  /// Starts the radio and the node. [ask] allows a permission prompt.
  Future<bool> start({required bool ask}) async {
    if (isRunning) return true;
    if (_starting || _isResponder == null) return false;
    _starting = true;
    try {
      if (!await _permissions(ask: ask)) return false;
      final radio = _radioFactory();
      final node = MeshNode(
        relay: MeshRelay(),
        transport: BleMeshTransport(radio),
        onEnvelope: (_) => unawaited(uplink()),
      );
      try {
        await node.start();
      } on Object catch (e) {
        // Bluetooth off, refused, or absent. Said, not thrown: the app works
        // without the mesh, it just has one fewer way out.
        debugPrint('[MESH] radio did not start: $e');
        await _release(node, radio);
        return false;
      }
      if (_isResponder == null) {
        // Signed out while the permission prompt or the radio was starting.
        await _release(node, radio);
        return false;
      }
      _node = node;
      _radio = radio;
      // Offering on arrival is the whole mechanism by which an alert crosses a
      // crowd. Delayed a moment so the transport has the link before this does.
      _peerSub = radio.peers.where((event) => event.connected).listen((_) {
        unawaited(Future<void>.delayed(peerSettle, () => _node?.gossip()));
      });
      _uplinkTimer = Timer.periodic(uplinkInterval, (_) => unawaited(uplink()));
      final prefs = await _preferences();
      await prefs.setBool(meshHasRunPreferenceKey, true);
      unawaited(uplink());
      return true;
    } finally {
      _starting = false;
    }
  }

  /// Stops the radio and drops everything held.
  Future<void> stop() async {
    _uplinkTimer?.cancel();
    _uplinkTimer = null;
    await _peerSub?.cancel();
    _peerSub = null;
    final node = _node;
    final radio = _radio;
    _node = null;
    _radio = null;
    if (node != null) await _release(node, radio);
  }

  Future<void> _release(MeshNode node, BleRadio? radio) async {
    try {
      await node.stop();
    } on Object catch (e) {
      debugPrint('[MESH] stopping the node: $e');
    }
    if (radio is MethodChannelBleRadio) {
      try {
        await radio.dispose();
      } on Object catch (e) {
        debugPrint('[MESH] releasing the radio: $e');
      }
    }
  }

  /// Uploads what this phone holds to HQ. Returns how many envelopes HQ
  /// finished with. Failing is normal — no network is why the mesh exists — so
  /// every failure is a quiet zero and the envelopes stay held.
  Future<int> uplink() async {
    final node = _node;
    if (node == null || _uploading) return 0;
    final base = _hqBaseUrl();
    if (base == null) return 0;
    final pending = node.relay.pending;
    if (pending.isEmpty) return 0;
    _uploading = true;
    try {
      final response = await _http
          .post(
            Uri.parse('$base/api/mesh/ingest'),
            headers: const {'content-type': 'application/json'},
            body: meshIngestBody(pending),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return 0;
      final done = meshIngestDone(response.body);
      done.forEach(node.delivered);
      return done.length;
    } on Object catch (_) {
      return 0;
    } finally {
      _uploading = false;
    }
  }

  void _observe() {
    if (_observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } on Object catch (_) {
      // No binding (a plain unit test). Nothing to observe.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _isResponder == null) return;
    unawaited(_onResumed());
  }

  Future<void> _onResumed() async {
    try {
      // Bluetooth may have been switched on since, or the network back.
      if (!isRunning && await relayEnabled()) await start(ask: false);
      await uplink();
    } on Object catch (e) {
      debugPrint('[MESH] resume: $e');
    }
  }
}

String? _configuredHqBaseUrl() {
  try {
    return AppConfig.hqApiBaseUrl;
  } on Object catch (_) {
    return null;
  }
}

/// What the platform needs before the radio may start.
///
/// * **Android 12+** needs the three Bluetooth runtime permissions. Below 12
///   they are granted at install and the scan rides on location, which the app
///   already holds for SOS tracking; the native side checks that.
/// * **iOS** asks by itself the first time the radio starts, and a refusal comes
///   back from the native `start` as PERMISSION_DENIED. permission_handler's
///   Bluetooth support is compiled out in the Podfile, so it is not asked here.
Future<bool> platformMeshPermissions({required bool ask}) async {
  if (kIsWeb) return false;
  if (defaultTargetPlatform == TargetPlatform.iOS) return true;
  if (defaultTargetPlatform != TargetPlatform.android) return false;
  const needed = [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.bluetoothAdvertise,
  ];
  var granted = true;
  for (final permission in needed) {
    if (!(await permission.status).isGranted) granted = false;
  }
  if (granted) return true;
  if (!ask) return false;
  final answers = await needed.request();
  return answers.values.every((status) => status.isGranted);
}

/// The Guardian screen's view of the downloadable Hausa model: whether it is
/// offered, downloaded, downloading, and switched on.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainbow_app/core/config/app_config.dart';
import 'package:rainbow_app/core/guardian/guardian_models.dart';
import 'package:rainbow_app/core/guardian/hausa_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String guardianHausaEnabledKey = 'guardian_hausa_enabled_v1';

enum HausaStatus {
  /// No model address is configured in this build.
  unavailable,
  notDownloaded,
  downloading,
  ready,

  /// The last download failed; nothing from it was kept.
  failed,
}

class HausaState {
  const HausaState({
    this.status = HausaStatus.unavailable,
    this.dir,
    this.enabled = false,
    this.progress = 0,
    this.sizeBytes,
  });

  final HausaStatus status;

  /// The installed model's folder, when [status] is ready.
  final String? dir;

  /// Whether the person wants Guardian to listen in Hausa.
  final bool enabled;

  /// 0..1 while downloading.
  final double progress;

  /// How big the download is, once the manifest has been read.
  final int? sizeBytes;

  /// The folder to listen with, or null when Hausa is not in use.
  String? get listeningDir => status == HausaStatus.ready && enabled ? dir : null;

  HausaState copyWith({HausaStatus? status, String? dir, bool? enabled, double? progress, int? sizeBytes}) =>
      HausaState(
        status: status ?? this.status,
        dir: dir ?? this.dir,
        enabled: enabled ?? this.enabled,
        progress: progress ?? this.progress,
        sizeBytes: sizeBytes ?? this.sizeBytes,
      );
}

/// Where the model is kept and fetched from. Overridden in tests.
final guardianHausaStoreProvider = FutureProvider<HausaModelStore>((ref) async => HausaModelStore(
      root: await GuardianModels.root(),
      manifestUrl: AppConfig.guardianHausaManifestUrl,
    ));

final guardianHausaProvider =
    StateNotifierProvider<GuardianHausa, HausaState>((ref) => GuardianHausa(ref));

class GuardianHausa extends StateNotifier<HausaState> {
  GuardianHausa(this._ref) : super(const HausaState()) {
    unawaited(_load());
  }

  final Ref _ref;
  HausaModelManifest? _manifest;

  Future<HausaModelStore> get _store => _ref.read(guardianHausaStoreProvider.future);

  Future<void> _load() async {
    try {
      final store = await _store;
      if (!store.offered) return;
      final dir = await store.installed();
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      state = HausaState(
        status: dir == null ? HausaStatus.notDownloaded : HausaStatus.ready,
        dir: dir,
        enabled: dir != null && (prefs.getBool(guardianHausaEnabledKey) ?? false),
      );
    } on Object catch (_) {
      // Unavailable is the honest answer if the store cannot even be read.
    }
  }

  /// Reads the published manifest so the screen can say how big it is.
  Future<void> checkSize() async {
    if (state.status != HausaStatus.notDownloaded && state.status != HausaStatus.failed) return;
    try {
      final m = _manifest ??= await (await _store).fetchManifest();
      if (mounted) state = state.copyWith(sizeBytes: m.totalBytes);
    } on Object catch (_) {
      // The size is a courtesy; the download says if the address is broken.
    }
  }

  /// Downloads and verifies the model, then switches Hausa on.
  Future<bool> download() async {
    if (state.status == HausaStatus.downloading) return false;
    state = state.copyWith(status: HausaStatus.downloading, progress: 0);
    try {
      final store = await _store;
      final m = _manifest ??= await store.fetchManifest();
      final dir = await store.download(m, onProgress: (done, total) {
        if (mounted) state = state.copyWith(progress: total == 0 ? 0 : done / total);
      });
      await _savePref(true);
      if (mounted) {
        state = HausaState(status: HausaStatus.ready, dir: dir, enabled: true, sizeBytes: m.totalBytes);
      }
      return true;
    } on Object catch (_) {
      _manifest = null; // Read it afresh next time: it may have been republished.
      if (mounted) state = state.copyWith(status: HausaStatus.failed, progress: 0);
      return false;
    }
  }

  Future<void> setEnabled(bool on) async {
    if (state.status != HausaStatus.ready) return;
    state = state.copyWith(enabled: on);
    await _savePref(on);
  }

  Future<void> remove() async {
    await (await _store).remove();
    await _savePref(false);
    if (mounted) state = HausaState(status: HausaStatus.notDownloaded, sizeBytes: state.sizeBytes);
  }

  Future<void> _savePref(bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(guardianHausaEnabledKey, on);
    } on Object catch (_) {}
  }
}

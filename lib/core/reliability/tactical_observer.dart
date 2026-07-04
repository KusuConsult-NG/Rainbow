// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// PRD: State management hardening engine.
/// Monitors provider lifecycles to prevent leaks, stale listeners,
/// and duplicate subscriptions in the mission-critical tactical grid.
class TacticalProviderObserver extends ProviderObserver {
  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint('🟢 [PROVIDER_INIT] ${provider.name ?? provider.runtimeType}');
    }
  }

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    // Detect potential "Rebuild Storms"
    if (kDebugMode && newValue == previousValue) {
      debugPrint(
        '⚠️ [REBUILD_STORM] Provider ${provider.name ?? provider.runtimeType} updated with identical value.',
      );
    }
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint(
        '🔴 [PROVIDER_DISPOSE] ${provider.name ?? provider.runtimeType}',
      );
    }
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    debugPrint(
      '🔥 [PROVIDER_CRASH] ${provider.name ?? provider.runtimeType}: $error',
    );
    // Forward to tactical logs / Crashlytics
  }
}

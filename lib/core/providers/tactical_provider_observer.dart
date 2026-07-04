// ignore_for_file: lines_longer_than_80_chars, Large data or UI definitions exceed limit
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Documentation for this public member.

class TacticalProviderObserver extends ProviderObserver {
  /// Documentation for this public member.
  const TacticalProviderObserver();

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint(
        '🔄 [RIVERPOD_UPDATE] ${provider.name ?? provider.runtimeType}: $newValue',
      );
    }
  }

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    if (kDebugMode) {
      debugPrint('➕ [RIVERPOD_ADD] ${provider.name ?? provider.runtimeType}');
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
      '🔥 [RIVERPOD_FAIL] ${provider.name ?? provider.runtimeType}: $error',
    );
  }
}

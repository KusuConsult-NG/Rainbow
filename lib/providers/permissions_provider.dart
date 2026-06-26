import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Documentation for this public member.

final permissionsProvider =
    NotifierProvider<PermissionsNotifier, PermissionsState>(
  PermissionsNotifier.new,
);

/// Documentation for this public member.

class PermissionsState {
  /// Documentation for this public member.
  const PermissionsState({
    this.location = true,
    this.sms = false,
    this.audio = false,
    this.persistence = true,
  });

  /// Documentation for this public member.
  final bool location;

  /// Documentation for this public member.
  final bool sms;

  /// Documentation for this public member.
  final bool audio;

  /// Documentation for this public member.
  final bool persistence;

  /// Documentation for this public member.

  PermissionsState copyWith({
    bool? location,
    bool? sms,
    bool? audio,
    bool? persistence,
  }) {
    return PermissionsState(
      location: location ?? this.location,
      sms: sms ?? this.sms,
      audio: audio ?? this.audio,
      persistence: persistence ?? this.persistence,
    );
  }
}

/// Documentation for this public member.

class PermissionsNotifier extends Notifier<PermissionsState> {
  @override
  PermissionsState build() => const PermissionsState();

  /// Documentation for this public member.

  void toggle(String key) {
    switch (key) {
      case 'location':
        state = state.copyWith(location: !state.location);
      case 'sms':
        state = state.copyWith(sms: !state.sms);
      case 'audio':
        state = state.copyWith(audio: !state.audio);
      case 'persistence':
        state = state.copyWith(persistence: !state.persistence);
    }
  }

  /// Documentation for this public member.

  void grantAll() {
    state = const PermissionsState(
      sms: true,
      audio: true,
    );
  }
}

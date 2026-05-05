import 'package:flutter_riverpod/flutter_riverpod.dart';

final permissionsProvider = NotifierProvider<PermissionsNotifier, PermissionsState>(PermissionsNotifier.new);

class PermissionsState {
  final bool location;
  final bool sms;
  final bool audio;
  final bool persistence;

  const PermissionsState({
    this.location = true,
    this.sms = false,
    this.audio = false,
    this.persistence = true,
  });

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

class PermissionsNotifier extends Notifier<PermissionsState> {
  @override
  PermissionsState build() => const PermissionsState();

  void toggle(String key) {
    switch (key) {
      case 'location':
        state = state.copyWith(location: !state.location);
        break;
      case 'sms':
        state = state.copyWith(sms: !state.sms);
        break;
      case 'audio':
        state = state.copyWith(audio: !state.audio);
        break;
      case 'persistence':
        state = state.copyWith(persistence: !state.persistence);
        break;
    }
  }

  void grantAll() {
    state = const PermissionsState(
      location: true,
      sms: true,
      audio: true,
      persistence: true,
    );
  }
}

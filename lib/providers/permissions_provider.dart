import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the phone has actually granted, for the setup screen to show.
///
/// These were four switches that started at "location on, persistence on"
/// before anything had been asked, and toggling them changed nothing: GRANT
/// CLEARANCE requested all four regardless. Now they are read from the phone
/// and only ever say what the phone said. Everything starts false — nothing is
/// granted until the phone says so.
final permissionsProvider =
    NotifierProvider<PermissionsNotifier, PermissionsState>(
  PermissionsNotifier.new,
);

class PermissionsState {
  const PermissionsState({
    this.location = false,
    this.sms = false,
    this.audio = false,
    this.persistence = false,
  });

  final bool location;
  final bool sms;
  final bool audio;
  final bool persistence;

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

  /// Records what the phone reported. Only the values given change.
  void record({bool? location, bool? sms, bool? audio, bool? persistence}) {
    state = state.copyWith(
      location: location,
      sms: sms,
      audio: audio,
      persistence: persistence,
    );
  }
}

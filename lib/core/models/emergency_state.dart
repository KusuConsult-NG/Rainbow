/// Documentation for this public member.
class EmergencyState {
  /// Documentation for this public member.
  const EmergencyState({
    this.isEmergencyActive = false,
    this.startTime,
    this.alertId,
    this.errorMessage,
    this.isSilent = false,
    this.sendFinished = false,
  });

  /// Documentation for this public member.
  final bool isEmergencyActive;

  /// Documentation for this public member.
  final DateTime? startTime;

  /// Documentation for this public member.
  final String? alertId;

  /// Documentation for this public member.
  final String? errorMessage;

  /// Raised by the triple tap, which leaves the user on the screen they were
  /// on. The UI shows a discreet marker instead of the emergency screen.
  final bool isSilent;

  /// The first attempt to file the alert has returned, whichever way it went.
  /// With [alertId] still null afterwards, HQ has NOT confirmed the alert: it
  /// was queued on the phone or refused. The screen must say so rather than
  /// claim HQ was notified.
  final bool sendFinished;

  /// Documentation for this public member.

  EmergencyState copyWith({
    bool? isEmergencyActive,
    DateTime? startTime,
    String? alertId,
    String? errorMessage,
    bool? isSilent,
    bool? sendFinished,
  }) {
    return EmergencyState(
      isEmergencyActive: isEmergencyActive ?? this.isEmergencyActive,
      startTime: startTime ?? this.startTime,
      alertId: alertId ?? this.alertId,
      errorMessage: errorMessage ?? this.errorMessage,
      isSilent: isSilent ?? this.isSilent,
      sendFinished: sendFinished ?? this.sendFinished,
    );
  }

  /// Documentation for this public member.

  int get elapsedSeconds {
    if (startTime == null) return 0;
    return DateTime.now().difference(startTime!).inSeconds;
  }

  /// Documentation for this public member.

  String get formattedTime {
    if (startTime == null) return '00:00';
    final diff = DateTime.now().difference(startTime!);
    final m = diff.inMinutes.toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

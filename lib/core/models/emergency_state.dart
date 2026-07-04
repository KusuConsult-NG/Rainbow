/// Documentation for this public member.
class EmergencyState {
  /// Documentation for this public member.
  const EmergencyState({
    this.isEmergencyActive = false,
    this.startTime,
    this.alertId,
    this.errorMessage,
  });

  /// Documentation for this public member.
  final bool isEmergencyActive;

  /// Documentation for this public member.
  final DateTime? startTime;

  /// Documentation for this public member.
  final String? alertId;

  /// Documentation for this public member.
  final String? errorMessage;

  /// Documentation for this public member.

  EmergencyState copyWith({
    bool? isEmergencyActive,
    DateTime? startTime,
    String? alertId,
    String? errorMessage,
  }) {
    return EmergencyState(
      isEmergencyActive: isEmergencyActive ?? this.isEmergencyActive,
      startTime: startTime ?? this.startTime,
      alertId: alertId ?? this.alertId,
      errorMessage: errorMessage ?? this.errorMessage,
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

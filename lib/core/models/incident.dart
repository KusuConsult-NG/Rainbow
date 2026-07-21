import 'package:freezed_annotation/freezed_annotation.dart';

part 'incident.freezed.dart';
part 'incident.g.dart';

/// Documentation for this public member.

enum IncidentStatus {
  /// Documentation for this public member.
  open,

  /// Documentation for this public member.
  dispatched,

  /// Documentation for this public member.
  acknowledged,

  /// Documentation for this public member.
  onRoute,

  /// Documentation for this public member.
  onSite,

  /// Documentation for this public member.
  resolved,

  /// Documentation for this public member.
  duress,

  /// Documentation for this public member.
  cancelled
}

/// Documentation for this public member.

@freezed
abstract class Incident with _$Incident {
  /// Documentation for this public member.
  const factory Incident({
    required String id,
    required String type,
    required String description,
    required double lat,
    required double lng,
    required String reportedBy,
    @Default('OPEN')
    String
        status, // Using String for Firestore compatibility but validated by IncidentStatus
    @Default('MEDIUM') String priority,
    @Default(false) bool isCritical,
    String? assignedToUid,
    String? assignedToName,
    String? dispatchedByUid,
    String? geoLga,
    String? geoWard,
    String? geoPu,
    @Default([]) List<String> attachments,
    @Default('COMPLETED') String syncStatus,
    @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
    DateTime? reportedAt,
    @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
    DateTime? dispatchedAt,
    @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
    DateTime? resolvedAt,
  }) = _Incident;

  /// Documentation for this public member.

  factory Incident.fromJson(Map<String, dynamic> json) =>
      _$IncidentFromJson(json);

  // Helper for Supabase Timestamps
  static DateTime? _timestampFromJson(dynamic timestamp) {
    if (timestamp is String) return DateTime.tryParse(timestamp);
    return null;
  }

  static dynamic _timestampToJson(DateTime? date) {
    if (date == null) return null;
    return date.toIso8601String();
  }
}

// Sealed class for Incident States (Reliability Enforcement)
/// Documentation for this public member.
@freezed
sealed class IncidentState with _$IncidentState {
  /// Documentation for this public member.
  const factory IncidentState.initial() = _Initial;

  /// Documentation for this public member.
  const factory IncidentState.loading() = _Loading;

  /// Documentation for this public member.
  const factory IncidentState.success(List<Incident> incidents) = _Success;

  /// Documentation for this public member.
  const factory IncidentState.failure(String message) = _Failure;
}

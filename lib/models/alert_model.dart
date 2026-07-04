// ignore_for_file: invalid_annotation_target
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'alert_model.freezed.dart';
part 'alert_model.g.dart';

/// Documentation for this public member.

enum AlertStatus {
  /// Documentation for this public member.
  @JsonValue('OPEN')
  open,

  /// Documentation for this public member.
  @JsonValue('ACTIVE')
  active,

  /// Documentation for this public member.
  @JsonValue('DURESS')
  duress,

  /// Documentation for this public member.
  @JsonValue('ACKNOWLEDGED')
  acknowledged,

  /// Documentation for this public member.
  @JsonValue('RESOLVED')
  resolved,

  /// Documentation for this public member.
  @JsonValue('CANCELLED')
  cancelled,
}

/// Documentation for this public member.

enum AlertPriority {
  /// Documentation for this public member.
  @JsonValue('CRITICAL')
  critical,

  /// Documentation for this public member.
  @JsonValue('HIGH')
  high,

  /// Documentation for this public member.
  @JsonValue('MEDIUM')
  medium,

  /// Documentation for this public member.
  @JsonValue('LOW')
  low,
}

/// Documentation for this public member.

@freezed
abstract class AlertModel with _$AlertModel {
  /// Documentation for this public member.
  const factory AlertModel({
    required String id,
    required String type,
    required String description,
    required double lat,
    required double lng,
    required String reportedBy,
    @JsonKey(
      name: 'reportedAt',
      fromJson: _timestampFromJson,
      toJson: _timestampToJson,
    )
    required DateTime reportedAt,
    @Default(AlertStatus.open) AlertStatus status,
    @Default(AlertPriority.medium) AlertPriority priority,
    @JsonKey(name: 'assigned_to')
    @Default('POLLING_UNIT')
    String assignedToRole,
    @JsonKey(
      name: 'acknowledgedAt',
      fromJson: _timestampFromJsonNullable,
      toJson: _timestampToJsonNullable,
    )
    DateTime? acknowledgedAt,
    @JsonKey(
      name: 'resolvedAt',
      fromJson: _timestampFromJsonNullable,
      toJson: _timestampToJsonNullable,
    )
    DateTime? resolvedAt,
    String? assignedToUid,
    @JsonKey(name: 'resolved_by') String? resolvedBy,
    @Default([]) List<String> updateLogs,
    String? lga,
    String? ward,
    String? pu,
  }) = _AlertModel;

  /// Documentation for this public member.

  factory AlertModel.fromJson(Map<String, dynamic> json) =>
      _$AlertModelFromJson(json);

  /// Documentation for this public member.

  factory AlertModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) throw Exception('Document data was null');
    return AlertModel.fromJson({
      ...data,
      'id': doc.id,
    });
  }
}

DateTime _timestampFromJson(dynamic timestamp) {
  if (timestamp is Timestamp) return timestamp.toDate();
  if (timestamp is String) return DateTime.parse(timestamp);
  return DateTime.now();
}

Timestamp _timestampToJson(DateTime date) => Timestamp.fromDate(date);

DateTime? _timestampFromJsonNullable(dynamic timestamp) {
  if (timestamp == null) return null;
  return _timestampFromJson(timestamp);
}

Timestamp? _timestampToJsonNullable(DateTime? date) =>
    date != null ? Timestamp.fromDate(date) : null;

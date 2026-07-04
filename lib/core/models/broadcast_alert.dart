// ignore_for_file: invalid_annotation_target
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'broadcast_alert.freezed.dart';
part 'broadcast_alert.g.dart';

/// Documentation for this public member.

@freezed
abstract class BroadcastAlert with _$BroadcastAlert {
  /// Documentation for this public member.
  const factory BroadcastAlert({
    required String id,
    required String message,
    @Default('INFO') String severity, // INFO, MEDIUM, HIGH, CRITICAL
    @Default(true) bool active,
    String? targetLga,
    String? targetWard,
    String? targetPu,
    @Default('ALL') String targetAudience, // ALL, STAFF, USER
    @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
    DateTime? createdAt,
    @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
    DateTime? expiresAt,
    List<String>? acknowledgedBy, // List of UIDs
  }) = _BroadcastAlert;

  /// Documentation for this public member.

  factory BroadcastAlert.fromJson(Map<String, dynamic> json) =>
      _$BroadcastAlertFromJson(json);
}

DateTime? _timestampFromJson(dynamic timestamp) {
  if (timestamp is Timestamp) return timestamp.toDate();
  if (timestamp is String) return DateTime.tryParse(timestamp);
  return null;
}

dynamic _timestampToJson(DateTime? date) {
  if (date == null) return null;
  return Timestamp.fromDate(date);
}

import 'package:freezed_annotation/freezed_annotation.dart';

part 'broadcast_alert.freezed.dart';
part 'broadcast_alert.g.dart';

@freezed
abstract class BroadcastAlert with _$BroadcastAlert {
  const factory BroadcastAlert({
    required String id,
    required String message,
    @Default('INFO') String severity,
    @Default(true) bool active,
    String? targetLga,
    String? targetWard,
    String? targetPu,
    @Default('ALL') String targetAudience,
    @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
    DateTime? createdAt,
    @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
    DateTime? expiresAt,
    List<String>? acknowledgedBy,
  }) = _BroadcastAlert;

  factory BroadcastAlert.fromJson(Map<String, dynamic> json) =>
      _$BroadcastAlertFromJson(json);
}

DateTime? _timestampFromJson(dynamic date) {
  if (date is String) return DateTime.tryParse(date);
  return null;
}

dynamic _timestampToJson(DateTime? date) {
  return date?.toIso8601String();
}

DateTime? _dateTimeFromJson(dynamic date) => _timestampFromJson(date);
dynamic _dateTimeToJson(DateTime? date) => _timestampToJson(date);

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'broadcast_alert.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_BroadcastAlert _$BroadcastAlertFromJson(Map<String, dynamic> json) =>
    _BroadcastAlert(
      id: json['id'] as String,
      message: json['message'] as String,
      severity: json['severity'] as String? ?? 'INFO',
      active: json['active'] as bool? ?? true,
      targetLga: json['targetLga'] as String?,
      targetWard: json['targetWard'] as String?,
      targetPu: json['targetPu'] as String?,
      targetAudience: json['targetAudience'] as String? ?? 'ALL',
      createdAt: _timestampFromJson(json['createdAt']),
      expiresAt: _timestampFromJson(json['expiresAt']),
      acknowledgedBy: (json['acknowledgedBy'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$BroadcastAlertToJson(_BroadcastAlert instance) =>
    <String, dynamic>{
      'id': instance.id,
      'message': instance.message,
      'severity': instance.severity,
      'active': instance.active,
      'targetLga': instance.targetLga,
      'targetWard': instance.targetWard,
      'targetPu': instance.targetPu,
      'targetAudience': instance.targetAudience,
      'createdAt': _timestampToJson(instance.createdAt),
      'expiresAt': _timestampToJson(instance.expiresAt),
      'acknowledgedBy': instance.acknowledgedBy,
    };

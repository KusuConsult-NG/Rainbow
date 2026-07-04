// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'alert_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AlertModel _$AlertModelFromJson(Map<String, dynamic> json) => _AlertModel(
      id: json['id'] as String,
      type: json['type'] as String,
      description: json['description'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      reportedBy: json['reportedBy'] as String,
      reportedAt: _timestampFromJson(json['reportedAt']),
      status: $enumDecodeNullable(_$AlertStatusEnumMap, json['status']) ??
          AlertStatus.open,
      priority: $enumDecodeNullable(_$AlertPriorityEnumMap, json['priority']) ??
          AlertPriority.medium,
      assignedToRole: json['assigned_to'] as String? ?? 'POLLING_UNIT',
      acknowledgedAt: _timestampFromJsonNullable(json['acknowledgedAt']),
      resolvedAt: _timestampFromJsonNullable(json['resolvedAt']),
      assignedToUid: json['assignedToUid'] as String?,
      resolvedBy: json['resolved_by'] as String?,
      updateLogs: (json['updateLogs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      lga: json['lga'] as String?,
      ward: json['ward'] as String?,
      pu: json['pu'] as String?,
    );

Map<String, dynamic> _$AlertModelToJson(_AlertModel instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'description': instance.description,
      'lat': instance.lat,
      'lng': instance.lng,
      'reportedBy': instance.reportedBy,
      'reportedAt': _timestampToJson(instance.reportedAt),
      'status': _$AlertStatusEnumMap[instance.status]!,
      'priority': _$AlertPriorityEnumMap[instance.priority]!,
      'assigned_to': instance.assignedToRole,
      'acknowledgedAt': _timestampToJsonNullable(instance.acknowledgedAt),
      'resolvedAt': _timestampToJsonNullable(instance.resolvedAt),
      'assignedToUid': instance.assignedToUid,
      'resolved_by': instance.resolvedBy,
      'updateLogs': instance.updateLogs,
      'lga': instance.lga,
      'ward': instance.ward,
      'pu': instance.pu,
    };

const _$AlertStatusEnumMap = {
  AlertStatus.open: 'OPEN',
  AlertStatus.active: 'ACTIVE',
  AlertStatus.duress: 'DURESS',
  AlertStatus.acknowledged: 'ACKNOWLEDGED',
  AlertStatus.resolved: 'RESOLVED',
  AlertStatus.cancelled: 'CANCELLED',
};

const _$AlertPriorityEnumMap = {
  AlertPriority.critical: 'CRITICAL',
  AlertPriority.high: 'HIGH',
  AlertPriority.medium: 'MEDIUM',
  AlertPriority.low: 'LOW',
};

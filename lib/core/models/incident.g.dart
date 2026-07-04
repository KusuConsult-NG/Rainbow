// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'incident.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Incident _$IncidentFromJson(Map<String, dynamic> json) => _Incident(
      id: json['id'] as String,
      type: json['type'] as String,
      description: json['description'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      reportedBy: json['reportedBy'] as String,
      status: json['status'] as String? ?? 'OPEN',
      priority: json['priority'] as String? ?? 'MEDIUM',
      isCritical: json['isCritical'] as bool? ?? false,
      assignedToUid: json['assignedToUid'] as String?,
      assignedToName: json['assignedToName'] as String?,
      dispatchedByUid: json['dispatchedByUid'] as String?,
      geoLga: json['geoLga'] as String?,
      geoWard: json['geoWard'] as String?,
      geoPu: json['geoPu'] as String?,
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      syncStatus: json['syncStatus'] as String? ?? 'COMPLETED',
      reportedAt: json['reportedAt'] == null
          ? null
          : DateTime.parse(json['reportedAt'] as String),
      dispatchedAt: json['dispatchedAt'] == null
          ? null
          : DateTime.parse(json['dispatchedAt'] as String),
      resolvedAt: json['resolvedAt'] == null
          ? null
          : DateTime.parse(json['resolvedAt'] as String),
    );

Map<String, dynamic> _$IncidentToJson(_Incident instance) => <String, dynamic>{
      'id': instance.id,
      'type': instance.type,
      'description': instance.description,
      'lat': instance.lat,
      'lng': instance.lng,
      'reportedBy': instance.reportedBy,
      'status': instance.status,
      'priority': instance.priority,
      'isCritical': instance.isCritical,
      'assignedToUid': instance.assignedToUid,
      'assignedToName': instance.assignedToName,
      'dispatchedByUid': instance.dispatchedByUid,
      'geoLga': instance.geoLga,
      'geoWard': instance.geoWard,
      'geoPu': instance.geoPu,
      'attachments': instance.attachments,
      'syncStatus': instance.syncStatus,
      'reportedAt': instance.reportedAt?.toIso8601String(),
      'dispatchedAt': instance.dispatchedAt?.toIso8601String(),
      'resolvedAt': instance.resolvedAt?.toIso8601String(),
    };

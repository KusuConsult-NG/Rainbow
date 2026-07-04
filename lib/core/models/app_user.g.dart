// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AppUser _$AppUserFromJson(Map<String, dynamic> json) => _AppUser(
      uid: json['uid'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String,
      phone: json['phone'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      isStaff: json['isStaff'] as bool? ?? false,
      role: json['role'] as String? ?? 'USER',
      geoLgas:
          (json['geoLgas'] as List<dynamic>?)?.map((e) => e as String).toList(),
      geoWards: (json['geoWards'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      geoPus:
          (json['geoPus'] as List<dynamic>?)?.map((e) => e as String).toList(),
      lastActive: json['lastActive'] == null
          ? null
          : DateTime.parse(json['lastActive'] as String),
      active: json['active'] as bool? ?? true,
    );

Map<String, dynamic> _$AppUserToJson(_AppUser instance) => <String, dynamic>{
      'uid': instance.uid,
      'email': instance.email,
      'displayName': instance.displayName,
      'phone': instance.phone,
      'avatarUrl': instance.avatarUrl,
      'isStaff': instance.isStaff,
      'role': instance.role,
      'geoLgas': instance.geoLgas,
      'geoWards': instance.geoWards,
      'geoPus': instance.geoPus,
      'lastActive': instance.lastActive?.toIso8601String(),
      'active': instance.active,
    };

// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_user.freezed.dart';
part 'app_user.g.dart';

/// Documentation for this public member.

@freezed
abstract class AppUser with _$AppUser {
  /// Documentation for this public member.
  const factory AppUser({
    required String uid,
    required String email,
    required String displayName,
    String? phone,
    String? avatarUrl,
    @Default(false) bool isStaff,
    @Default('USER')
    String role, // USER, UNIT_COMMAND, WARD_COMMAND, LGA_COMMAND, HQ_OFFICER
    List<String>? geoLgas,
    List<String>? geoWards,
    List<String>? geoPus,
    @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
    DateTime? lastActive,
    @Default(true) bool active,
  }) = _AppUser;

  /// Documentation for this public member.

  factory AppUser.fromJson(Map<String, dynamic> json) =>
      _$AppUserFromJson(json);

  static DateTime? _timestampFromJson(dynamic timestamp) {
    if (timestamp is String) return DateTime.tryParse(timestamp);
    if (timestamp is int) return DateTime.fromMillisecondsSinceEpoch(timestamp);
    return null;
  }

  static dynamic _timestampToJson(DateTime? date) {
    if (date == null) return null;
    return date.toIso8601String();
  }
}

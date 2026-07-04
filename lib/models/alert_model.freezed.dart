// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'alert_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AlertModel {
  String get id;
  String get type;
  String get description;
  double get lat;
  double get lng;
  String get reportedBy;
  @JsonKey(
      name: 'reportedAt',
      fromJson: _timestampFromJson,
      toJson: _timestampToJson)
  DateTime get reportedAt;
  AlertStatus get status;
  AlertPriority get priority;
  @JsonKey(name: 'assigned_to')
  String get assignedToRole;
  @JsonKey(
      name: 'acknowledgedAt',
      fromJson: _timestampFromJsonNullable,
      toJson: _timestampToJsonNullable)
  DateTime? get acknowledgedAt;
  @JsonKey(
      name: 'resolvedAt',
      fromJson: _timestampFromJsonNullable,
      toJson: _timestampToJsonNullable)
  DateTime? get resolvedAt;
  String? get assignedToUid;
  @JsonKey(name: 'resolved_by')
  String? get resolvedBy;
  List<String> get updateLogs;
  String? get lga;
  String? get ward;
  String? get pu;

  /// Create a copy of AlertModel
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AlertModelCopyWith<AlertModel> get copyWith =>
      _$AlertModelCopyWithImpl<AlertModel>(this as AlertModel, _$identity);

  /// Serializes this AlertModel to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AlertModel &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.lat, lat) || other.lat == lat) &&
            (identical(other.lng, lng) || other.lng == lng) &&
            (identical(other.reportedBy, reportedBy) ||
                other.reportedBy == reportedBy) &&
            (identical(other.reportedAt, reportedAt) ||
                other.reportedAt == reportedAt) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.priority, priority) ||
                other.priority == priority) &&
            (identical(other.assignedToRole, assignedToRole) ||
                other.assignedToRole == assignedToRole) &&
            (identical(other.acknowledgedAt, acknowledgedAt) ||
                other.acknowledgedAt == acknowledgedAt) &&
            (identical(other.resolvedAt, resolvedAt) ||
                other.resolvedAt == resolvedAt) &&
            (identical(other.assignedToUid, assignedToUid) ||
                other.assignedToUid == assignedToUid) &&
            (identical(other.resolvedBy, resolvedBy) ||
                other.resolvedBy == resolvedBy) &&
            const DeepCollectionEquality()
                .equals(other.updateLogs, updateLogs) &&
            (identical(other.lga, lga) || other.lga == lga) &&
            (identical(other.ward, ward) || other.ward == ward) &&
            (identical(other.pu, pu) || other.pu == pu));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      type,
      description,
      lat,
      lng,
      reportedBy,
      reportedAt,
      status,
      priority,
      assignedToRole,
      acknowledgedAt,
      resolvedAt,
      assignedToUid,
      resolvedBy,
      const DeepCollectionEquality().hash(updateLogs),
      lga,
      ward,
      pu);

  @override
  String toString() {
    return 'AlertModel(id: $id, type: $type, description: $description, lat: $lat, lng: $lng, reportedBy: $reportedBy, reportedAt: $reportedAt, status: $status, priority: $priority, assignedToRole: $assignedToRole, acknowledgedAt: $acknowledgedAt, resolvedAt: $resolvedAt, assignedToUid: $assignedToUid, resolvedBy: $resolvedBy, updateLogs: $updateLogs, lga: $lga, ward: $ward, pu: $pu)';
  }
}

/// @nodoc
abstract mixin class $AlertModelCopyWith<$Res> {
  factory $AlertModelCopyWith(
          AlertModel value, $Res Function(AlertModel) _then) =
      _$AlertModelCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String type,
      String description,
      double lat,
      double lng,
      String reportedBy,
      @JsonKey(
          name: 'reportedAt',
          fromJson: _timestampFromJson,
          toJson: _timestampToJson)
      DateTime reportedAt,
      AlertStatus status,
      AlertPriority priority,
      @JsonKey(name: 'assigned_to') String assignedToRole,
      @JsonKey(
          name: 'acknowledgedAt',
          fromJson: _timestampFromJsonNullable,
          toJson: _timestampToJsonNullable)
      DateTime? acknowledgedAt,
      @JsonKey(
          name: 'resolvedAt',
          fromJson: _timestampFromJsonNullable,
          toJson: _timestampToJsonNullable)
      DateTime? resolvedAt,
      String? assignedToUid,
      @JsonKey(name: 'resolved_by') String? resolvedBy,
      List<String> updateLogs,
      String? lga,
      String? ward,
      String? pu});
}

/// @nodoc
class _$AlertModelCopyWithImpl<$Res> implements $AlertModelCopyWith<$Res> {
  _$AlertModelCopyWithImpl(this._self, this._then);

  final AlertModel _self;
  final $Res Function(AlertModel) _then;

  /// Create a copy of AlertModel
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? description = null,
    Object? lat = null,
    Object? lng = null,
    Object? reportedBy = null,
    Object? reportedAt = null,
    Object? status = null,
    Object? priority = null,
    Object? assignedToRole = null,
    Object? acknowledgedAt = freezed,
    Object? resolvedAt = freezed,
    Object? assignedToUid = freezed,
    Object? resolvedBy = freezed,
    Object? updateLogs = null,
    Object? lga = freezed,
    Object? ward = freezed,
    Object? pu = freezed,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      lat: null == lat
          ? _self.lat
          : lat // ignore: cast_nullable_to_non_nullable
              as double,
      lng: null == lng
          ? _self.lng
          : lng // ignore: cast_nullable_to_non_nullable
              as double,
      reportedBy: null == reportedBy
          ? _self.reportedBy
          : reportedBy // ignore: cast_nullable_to_non_nullable
              as String,
      reportedAt: null == reportedAt
          ? _self.reportedAt
          : reportedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _self.status
          : status // ignore: cast_nullable_to_non_nullable
              as AlertStatus,
      priority: null == priority
          ? _self.priority
          : priority // ignore: cast_nullable_to_non_nullable
              as AlertPriority,
      assignedToRole: null == assignedToRole
          ? _self.assignedToRole
          : assignedToRole // ignore: cast_nullable_to_non_nullable
              as String,
      acknowledgedAt: freezed == acknowledgedAt
          ? _self.acknowledgedAt
          : acknowledgedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      resolvedAt: freezed == resolvedAt
          ? _self.resolvedAt
          : resolvedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      assignedToUid: freezed == assignedToUid
          ? _self.assignedToUid
          : assignedToUid // ignore: cast_nullable_to_non_nullable
              as String?,
      resolvedBy: freezed == resolvedBy
          ? _self.resolvedBy
          : resolvedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      updateLogs: null == updateLogs
          ? _self.updateLogs
          : updateLogs // ignore: cast_nullable_to_non_nullable
              as List<String>,
      lga: freezed == lga
          ? _self.lga
          : lga // ignore: cast_nullable_to_non_nullable
              as String?,
      ward: freezed == ward
          ? _self.ward
          : ward // ignore: cast_nullable_to_non_nullable
              as String?,
      pu: freezed == pu
          ? _self.pu
          : pu // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// Adds pattern-matching-related methods to [AlertModel].
extension AlertModelPatterns on AlertModel {
  /// A variant of `map` that fallback to returning `orElse`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>(
    TResult Function(_AlertModel value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AlertModel() when $default != null:
        return $default(_that);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// Callbacks receives the raw object, upcasted.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case final Subclass2 value:
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult map<TResult extends Object?>(
    TResult Function(_AlertModel value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AlertModel():
        return $default(_that);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `map` that fallback to returning `null`.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case final Subclass value:
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>(
    TResult? Function(_AlertModel value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AlertModel() when $default != null:
        return $default(_that);
      case _:
        return null;
    }
  }

  /// A variant of `when` that fallback to an `orElse` callback.
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return orElse();
  /// }
  /// ```

  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>(
    TResult Function(
            String id,
            String type,
            String description,
            double lat,
            double lng,
            String reportedBy,
            @JsonKey(
                name: 'reportedAt',
                fromJson: _timestampFromJson,
                toJson: _timestampToJson)
            DateTime reportedAt,
            AlertStatus status,
            AlertPriority priority,
            @JsonKey(name: 'assigned_to') String assignedToRole,
            @JsonKey(
                name: 'acknowledgedAt',
                fromJson: _timestampFromJsonNullable,
                toJson: _timestampToJsonNullable)
            DateTime? acknowledgedAt,
            @JsonKey(
                name: 'resolvedAt',
                fromJson: _timestampFromJsonNullable,
                toJson: _timestampToJsonNullable)
            DateTime? resolvedAt,
            String? assignedToUid,
            @JsonKey(name: 'resolved_by') String? resolvedBy,
            List<String> updateLogs,
            String? lga,
            String? ward,
            String? pu)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AlertModel() when $default != null:
        return $default(
            _that.id,
            _that.type,
            _that.description,
            _that.lat,
            _that.lng,
            _that.reportedBy,
            _that.reportedAt,
            _that.status,
            _that.priority,
            _that.assignedToRole,
            _that.acknowledgedAt,
            _that.resolvedAt,
            _that.assignedToUid,
            _that.resolvedBy,
            _that.updateLogs,
            _that.lga,
            _that.ward,
            _that.pu);
      case _:
        return orElse();
    }
  }

  /// A `switch`-like method, using callbacks.
  ///
  /// As opposed to `map`, this offers destructuring.
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case Subclass2(:final field2):
  ///     return ...;
  /// }
  /// ```

  @optionalTypeArgs
  TResult when<TResult extends Object?>(
    TResult Function(
            String id,
            String type,
            String description,
            double lat,
            double lng,
            String reportedBy,
            @JsonKey(
                name: 'reportedAt',
                fromJson: _timestampFromJson,
                toJson: _timestampToJson)
            DateTime reportedAt,
            AlertStatus status,
            AlertPriority priority,
            @JsonKey(name: 'assigned_to') String assignedToRole,
            @JsonKey(
                name: 'acknowledgedAt',
                fromJson: _timestampFromJsonNullable,
                toJson: _timestampToJsonNullable)
            DateTime? acknowledgedAt,
            @JsonKey(
                name: 'resolvedAt',
                fromJson: _timestampFromJsonNullable,
                toJson: _timestampToJsonNullable)
            DateTime? resolvedAt,
            String? assignedToUid,
            @JsonKey(name: 'resolved_by') String? resolvedBy,
            List<String> updateLogs,
            String? lga,
            String? ward,
            String? pu)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AlertModel():
        return $default(
            _that.id,
            _that.type,
            _that.description,
            _that.lat,
            _that.lng,
            _that.reportedBy,
            _that.reportedAt,
            _that.status,
            _that.priority,
            _that.assignedToRole,
            _that.acknowledgedAt,
            _that.resolvedAt,
            _that.assignedToUid,
            _that.resolvedBy,
            _that.updateLogs,
            _that.lga,
            _that.ward,
            _that.pu);
      case _:
        throw StateError('Unexpected subclass');
    }
  }

  /// A variant of `when` that fallback to returning `null`
  ///
  /// It is equivalent to doing:
  /// ```dart
  /// switch (sealedClass) {
  ///   case Subclass(:final field):
  ///     return ...;
  ///   case _:
  ///     return null;
  /// }
  /// ```

  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>(
    TResult? Function(
            String id,
            String type,
            String description,
            double lat,
            double lng,
            String reportedBy,
            @JsonKey(
                name: 'reportedAt',
                fromJson: _timestampFromJson,
                toJson: _timestampToJson)
            DateTime reportedAt,
            AlertStatus status,
            AlertPriority priority,
            @JsonKey(name: 'assigned_to') String assignedToRole,
            @JsonKey(
                name: 'acknowledgedAt',
                fromJson: _timestampFromJsonNullable,
                toJson: _timestampToJsonNullable)
            DateTime? acknowledgedAt,
            @JsonKey(
                name: 'resolvedAt',
                fromJson: _timestampFromJsonNullable,
                toJson: _timestampToJsonNullable)
            DateTime? resolvedAt,
            String? assignedToUid,
            @JsonKey(name: 'resolved_by') String? resolvedBy,
            List<String> updateLogs,
            String? lga,
            String? ward,
            String? pu)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AlertModel() when $default != null:
        return $default(
            _that.id,
            _that.type,
            _that.description,
            _that.lat,
            _that.lng,
            _that.reportedBy,
            _that.reportedAt,
            _that.status,
            _that.priority,
            _that.assignedToRole,
            _that.acknowledgedAt,
            _that.resolvedAt,
            _that.assignedToUid,
            _that.resolvedBy,
            _that.updateLogs,
            _that.lga,
            _that.ward,
            _that.pu);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _AlertModel implements AlertModel {
  const _AlertModel(
      {required this.id,
      required this.type,
      required this.description,
      required this.lat,
      required this.lng,
      required this.reportedBy,
      @JsonKey(
          name: 'reportedAt',
          fromJson: _timestampFromJson,
          toJson: _timestampToJson)
      required this.reportedAt,
      this.status = AlertStatus.open,
      this.priority = AlertPriority.medium,
      @JsonKey(name: 'assigned_to') this.assignedToRole = 'POLLING_UNIT',
      @JsonKey(
          name: 'acknowledgedAt',
          fromJson: _timestampFromJsonNullable,
          toJson: _timestampToJsonNullable)
      this.acknowledgedAt,
      @JsonKey(
          name: 'resolvedAt',
          fromJson: _timestampFromJsonNullable,
          toJson: _timestampToJsonNullable)
      this.resolvedAt,
      this.assignedToUid,
      @JsonKey(name: 'resolved_by') this.resolvedBy,
      final List<String> updateLogs = const [],
      this.lga,
      this.ward,
      this.pu})
      : _updateLogs = updateLogs;
  factory _AlertModel.fromJson(Map<String, dynamic> json) =>
      _$AlertModelFromJson(json);

  @override
  final String id;
  @override
  final String type;
  @override
  final String description;
  @override
  final double lat;
  @override
  final double lng;
  @override
  final String reportedBy;
  @override
  @JsonKey(
      name: 'reportedAt',
      fromJson: _timestampFromJson,
      toJson: _timestampToJson)
  final DateTime reportedAt;
  @override
  @JsonKey()
  final AlertStatus status;
  @override
  @JsonKey()
  final AlertPriority priority;
  @override
  @JsonKey(name: 'assigned_to')
  final String assignedToRole;
  @override
  @JsonKey(
      name: 'acknowledgedAt',
      fromJson: _timestampFromJsonNullable,
      toJson: _timestampToJsonNullable)
  final DateTime? acknowledgedAt;
  @override
  @JsonKey(
      name: 'resolvedAt',
      fromJson: _timestampFromJsonNullable,
      toJson: _timestampToJsonNullable)
  final DateTime? resolvedAt;
  @override
  final String? assignedToUid;
  @override
  @JsonKey(name: 'resolved_by')
  final String? resolvedBy;
  final List<String> _updateLogs;
  @override
  @JsonKey()
  List<String> get updateLogs {
    if (_updateLogs is EqualUnmodifiableListView) return _updateLogs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_updateLogs);
  }

  @override
  final String? lga;
  @override
  final String? ward;
  @override
  final String? pu;

  /// Create a copy of AlertModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AlertModelCopyWith<_AlertModel> get copyWith =>
      __$AlertModelCopyWithImpl<_AlertModel>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$AlertModelToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AlertModel &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.lat, lat) || other.lat == lat) &&
            (identical(other.lng, lng) || other.lng == lng) &&
            (identical(other.reportedBy, reportedBy) ||
                other.reportedBy == reportedBy) &&
            (identical(other.reportedAt, reportedAt) ||
                other.reportedAt == reportedAt) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.priority, priority) ||
                other.priority == priority) &&
            (identical(other.assignedToRole, assignedToRole) ||
                other.assignedToRole == assignedToRole) &&
            (identical(other.acknowledgedAt, acknowledgedAt) ||
                other.acknowledgedAt == acknowledgedAt) &&
            (identical(other.resolvedAt, resolvedAt) ||
                other.resolvedAt == resolvedAt) &&
            (identical(other.assignedToUid, assignedToUid) ||
                other.assignedToUid == assignedToUid) &&
            (identical(other.resolvedBy, resolvedBy) ||
                other.resolvedBy == resolvedBy) &&
            const DeepCollectionEquality()
                .equals(other._updateLogs, _updateLogs) &&
            (identical(other.lga, lga) || other.lga == lga) &&
            (identical(other.ward, ward) || other.ward == ward) &&
            (identical(other.pu, pu) || other.pu == pu));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      type,
      description,
      lat,
      lng,
      reportedBy,
      reportedAt,
      status,
      priority,
      assignedToRole,
      acknowledgedAt,
      resolvedAt,
      assignedToUid,
      resolvedBy,
      const DeepCollectionEquality().hash(_updateLogs),
      lga,
      ward,
      pu);

  @override
  String toString() {
    return 'AlertModel(id: $id, type: $type, description: $description, lat: $lat, lng: $lng, reportedBy: $reportedBy, reportedAt: $reportedAt, status: $status, priority: $priority, assignedToRole: $assignedToRole, acknowledgedAt: $acknowledgedAt, resolvedAt: $resolvedAt, assignedToUid: $assignedToUid, resolvedBy: $resolvedBy, updateLogs: $updateLogs, lga: $lga, ward: $ward, pu: $pu)';
  }
}

/// @nodoc
abstract mixin class _$AlertModelCopyWith<$Res>
    implements $AlertModelCopyWith<$Res> {
  factory _$AlertModelCopyWith(
          _AlertModel value, $Res Function(_AlertModel) _then) =
      __$AlertModelCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String type,
      String description,
      double lat,
      double lng,
      String reportedBy,
      @JsonKey(
          name: 'reportedAt',
          fromJson: _timestampFromJson,
          toJson: _timestampToJson)
      DateTime reportedAt,
      AlertStatus status,
      AlertPriority priority,
      @JsonKey(name: 'assigned_to') String assignedToRole,
      @JsonKey(
          name: 'acknowledgedAt',
          fromJson: _timestampFromJsonNullable,
          toJson: _timestampToJsonNullable)
      DateTime? acknowledgedAt,
      @JsonKey(
          name: 'resolvedAt',
          fromJson: _timestampFromJsonNullable,
          toJson: _timestampToJsonNullable)
      DateTime? resolvedAt,
      String? assignedToUid,
      @JsonKey(name: 'resolved_by') String? resolvedBy,
      List<String> updateLogs,
      String? lga,
      String? ward,
      String? pu});
}

/// @nodoc
class __$AlertModelCopyWithImpl<$Res> implements _$AlertModelCopyWith<$Res> {
  __$AlertModelCopyWithImpl(this._self, this._then);

  final _AlertModel _self;
  final $Res Function(_AlertModel) _then;

  /// Create a copy of AlertModel
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? description = null,
    Object? lat = null,
    Object? lng = null,
    Object? reportedBy = null,
    Object? reportedAt = null,
    Object? status = null,
    Object? priority = null,
    Object? assignedToRole = null,
    Object? acknowledgedAt = freezed,
    Object? resolvedAt = freezed,
    Object? assignedToUid = freezed,
    Object? resolvedBy = freezed,
    Object? updateLogs = null,
    Object? lga = freezed,
    Object? ward = freezed,
    Object? pu = freezed,
  }) {
    return _then(_AlertModel(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _self.type
          : type // ignore: cast_nullable_to_non_nullable
              as String,
      description: null == description
          ? _self.description
          : description // ignore: cast_nullable_to_non_nullable
              as String,
      lat: null == lat
          ? _self.lat
          : lat // ignore: cast_nullable_to_non_nullable
              as double,
      lng: null == lng
          ? _self.lng
          : lng // ignore: cast_nullable_to_non_nullable
              as double,
      reportedBy: null == reportedBy
          ? _self.reportedBy
          : reportedBy // ignore: cast_nullable_to_non_nullable
              as String,
      reportedAt: null == reportedAt
          ? _self.reportedAt
          : reportedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      status: null == status
          ? _self.status
          : status // ignore: cast_nullable_to_non_nullable
              as AlertStatus,
      priority: null == priority
          ? _self.priority
          : priority // ignore: cast_nullable_to_non_nullable
              as AlertPriority,
      assignedToRole: null == assignedToRole
          ? _self.assignedToRole
          : assignedToRole // ignore: cast_nullable_to_non_nullable
              as String,
      acknowledgedAt: freezed == acknowledgedAt
          ? _self.acknowledgedAt
          : acknowledgedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      resolvedAt: freezed == resolvedAt
          ? _self.resolvedAt
          : resolvedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      assignedToUid: freezed == assignedToUid
          ? _self.assignedToUid
          : assignedToUid // ignore: cast_nullable_to_non_nullable
              as String?,
      resolvedBy: freezed == resolvedBy
          ? _self.resolvedBy
          : resolvedBy // ignore: cast_nullable_to_non_nullable
              as String?,
      updateLogs: null == updateLogs
          ? _self._updateLogs
          : updateLogs // ignore: cast_nullable_to_non_nullable
              as List<String>,
      lga: freezed == lga
          ? _self.lga
          : lga // ignore: cast_nullable_to_non_nullable
              as String?,
      ward: freezed == ward
          ? _self.ward
          : ward // ignore: cast_nullable_to_non_nullable
              as String?,
      pu: freezed == pu
          ? _self.pu
          : pu // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

// dart format on

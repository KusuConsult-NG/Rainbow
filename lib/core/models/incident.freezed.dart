// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'incident.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Incident {
  String get id;
  String get type;
  String get description;
  double get lat;
  double get lng;
  String get reportedBy;
  String
      get status; // Using String for Firestore compatibility but validated by IncidentStatus
  String get priority;
  bool get isCritical;
  String? get assignedToUid;
  String? get assignedToName;
  String? get dispatchedByUid;
  String? get geoLga;
  String? get geoWard;
  String? get geoPu;
  List<String> get attachments;
  String get syncStatus;
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  DateTime? get reportedAt;
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  DateTime? get dispatchedAt;
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  DateTime? get resolvedAt;

  /// Create a copy of Incident
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $IncidentCopyWith<Incident> get copyWith =>
      _$IncidentCopyWithImpl<Incident>(this as Incident, _$identity);

  /// Serializes this Incident to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is Incident &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.lat, lat) || other.lat == lat) &&
            (identical(other.lng, lng) || other.lng == lng) &&
            (identical(other.reportedBy, reportedBy) ||
                other.reportedBy == reportedBy) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.priority, priority) ||
                other.priority == priority) &&
            (identical(other.isCritical, isCritical) ||
                other.isCritical == isCritical) &&
            (identical(other.assignedToUid, assignedToUid) ||
                other.assignedToUid == assignedToUid) &&
            (identical(other.assignedToName, assignedToName) ||
                other.assignedToName == assignedToName) &&
            (identical(other.dispatchedByUid, dispatchedByUid) ||
                other.dispatchedByUid == dispatchedByUid) &&
            (identical(other.geoLga, geoLga) || other.geoLga == geoLga) &&
            (identical(other.geoWard, geoWard) || other.geoWard == geoWard) &&
            (identical(other.geoPu, geoPu) || other.geoPu == geoPu) &&
            const DeepCollectionEquality()
                .equals(other.attachments, attachments) &&
            (identical(other.syncStatus, syncStatus) ||
                other.syncStatus == syncStatus) &&
            (identical(other.reportedAt, reportedAt) ||
                other.reportedAt == reportedAt) &&
            (identical(other.dispatchedAt, dispatchedAt) ||
                other.dispatchedAt == dispatchedAt) &&
            (identical(other.resolvedAt, resolvedAt) ||
                other.resolvedAt == resolvedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        type,
        description,
        lat,
        lng,
        reportedBy,
        status,
        priority,
        isCritical,
        assignedToUid,
        assignedToName,
        dispatchedByUid,
        geoLga,
        geoWard,
        geoPu,
        const DeepCollectionEquality().hash(attachments),
        syncStatus,
        reportedAt,
        dispatchedAt,
        resolvedAt
      ]);

  @override
  String toString() {
    return 'Incident(id: $id, type: $type, description: $description, lat: $lat, lng: $lng, reportedBy: $reportedBy, status: $status, priority: $priority, isCritical: $isCritical, assignedToUid: $assignedToUid, assignedToName: $assignedToName, dispatchedByUid: $dispatchedByUid, geoLga: $geoLga, geoWard: $geoWard, geoPu: $geoPu, attachments: $attachments, syncStatus: $syncStatus, reportedAt: $reportedAt, dispatchedAt: $dispatchedAt, resolvedAt: $resolvedAt)';
  }
}

/// @nodoc
abstract mixin class $IncidentCopyWith<$Res> {
  factory $IncidentCopyWith(Incident value, $Res Function(Incident) _then) =
      _$IncidentCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String type,
      String description,
      double lat,
      double lng,
      String reportedBy,
      String status,
      String priority,
      bool isCritical,
      String? assignedToUid,
      String? assignedToName,
      String? dispatchedByUid,
      String? geoLga,
      String? geoWard,
      String? geoPu,
      List<String> attachments,
      String syncStatus,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? reportedAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? dispatchedAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? resolvedAt});
}

/// @nodoc
class _$IncidentCopyWithImpl<$Res> implements $IncidentCopyWith<$Res> {
  _$IncidentCopyWithImpl(this._self, this._then);

  final Incident _self;
  final $Res Function(Incident) _then;

  /// Create a copy of Incident
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
    Object? status = null,
    Object? priority = null,
    Object? isCritical = null,
    Object? assignedToUid = freezed,
    Object? assignedToName = freezed,
    Object? dispatchedByUid = freezed,
    Object? geoLga = freezed,
    Object? geoWard = freezed,
    Object? geoPu = freezed,
    Object? attachments = null,
    Object? syncStatus = null,
    Object? reportedAt = freezed,
    Object? dispatchedAt = freezed,
    Object? resolvedAt = freezed,
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
      status: null == status
          ? _self.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      priority: null == priority
          ? _self.priority
          : priority // ignore: cast_nullable_to_non_nullable
              as String,
      isCritical: null == isCritical
          ? _self.isCritical
          : isCritical // ignore: cast_nullable_to_non_nullable
              as bool,
      assignedToUid: freezed == assignedToUid
          ? _self.assignedToUid
          : assignedToUid // ignore: cast_nullable_to_non_nullable
              as String?,
      assignedToName: freezed == assignedToName
          ? _self.assignedToName
          : assignedToName // ignore: cast_nullable_to_non_nullable
              as String?,
      dispatchedByUid: freezed == dispatchedByUid
          ? _self.dispatchedByUid
          : dispatchedByUid // ignore: cast_nullable_to_non_nullable
              as String?,
      geoLga: freezed == geoLga
          ? _self.geoLga
          : geoLga // ignore: cast_nullable_to_non_nullable
              as String?,
      geoWard: freezed == geoWard
          ? _self.geoWard
          : geoWard // ignore: cast_nullable_to_non_nullable
              as String?,
      geoPu: freezed == geoPu
          ? _self.geoPu
          : geoPu // ignore: cast_nullable_to_non_nullable
              as String?,
      attachments: null == attachments
          ? _self.attachments
          : attachments // ignore: cast_nullable_to_non_nullable
              as List<String>,
      syncStatus: null == syncStatus
          ? _self.syncStatus
          : syncStatus // ignore: cast_nullable_to_non_nullable
              as String,
      reportedAt: freezed == reportedAt
          ? _self.reportedAt
          : reportedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      dispatchedAt: freezed == dispatchedAt
          ? _self.dispatchedAt
          : dispatchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      resolvedAt: freezed == resolvedAt
          ? _self.resolvedAt
          : resolvedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// Adds pattern-matching-related methods to [Incident].
extension IncidentPatterns on Incident {
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
    TResult Function(_Incident value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Incident() when $default != null:
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
    TResult Function(_Incident value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Incident():
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
    TResult? Function(_Incident value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Incident() when $default != null:
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
            String status,
            String priority,
            bool isCritical,
            String? assignedToUid,
            String? assignedToName,
            String? dispatchedByUid,
            String? geoLga,
            String? geoWard,
            String? geoPu,
            List<String> attachments,
            String syncStatus,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? reportedAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? dispatchedAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? resolvedAt)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Incident() when $default != null:
        return $default(
            _that.id,
            _that.type,
            _that.description,
            _that.lat,
            _that.lng,
            _that.reportedBy,
            _that.status,
            _that.priority,
            _that.isCritical,
            _that.assignedToUid,
            _that.assignedToName,
            _that.dispatchedByUid,
            _that.geoLga,
            _that.geoWard,
            _that.geoPu,
            _that.attachments,
            _that.syncStatus,
            _that.reportedAt,
            _that.dispatchedAt,
            _that.resolvedAt);
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
            String status,
            String priority,
            bool isCritical,
            String? assignedToUid,
            String? assignedToName,
            String? dispatchedByUid,
            String? geoLga,
            String? geoWard,
            String? geoPu,
            List<String> attachments,
            String syncStatus,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? reportedAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? dispatchedAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? resolvedAt)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Incident():
        return $default(
            _that.id,
            _that.type,
            _that.description,
            _that.lat,
            _that.lng,
            _that.reportedBy,
            _that.status,
            _that.priority,
            _that.isCritical,
            _that.assignedToUid,
            _that.assignedToName,
            _that.dispatchedByUid,
            _that.geoLga,
            _that.geoWard,
            _that.geoPu,
            _that.attachments,
            _that.syncStatus,
            _that.reportedAt,
            _that.dispatchedAt,
            _that.resolvedAt);
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
            String status,
            String priority,
            bool isCritical,
            String? assignedToUid,
            String? assignedToName,
            String? dispatchedByUid,
            String? geoLga,
            String? geoWard,
            String? geoPu,
            List<String> attachments,
            String syncStatus,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? reportedAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? dispatchedAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? resolvedAt)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _Incident() when $default != null:
        return $default(
            _that.id,
            _that.type,
            _that.description,
            _that.lat,
            _that.lng,
            _that.reportedBy,
            _that.status,
            _that.priority,
            _that.isCritical,
            _that.assignedToUid,
            _that.assignedToName,
            _that.dispatchedByUid,
            _that.geoLga,
            _that.geoWard,
            _that.geoPu,
            _that.attachments,
            _that.syncStatus,
            _that.reportedAt,
            _that.dispatchedAt,
            _that.resolvedAt);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _Incident implements Incident {
  const _Incident(
      {required this.id,
      required this.type,
      required this.description,
      required this.lat,
      required this.lng,
      required this.reportedBy,
      this.status = 'OPEN',
      this.priority = 'MEDIUM',
      this.isCritical = false,
      this.assignedToUid,
      this.assignedToName,
      this.dispatchedByUid,
      this.geoLga,
      this.geoWard,
      this.geoPu,
      final List<String> attachments = const [],
      this.syncStatus = 'COMPLETED',
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      this.reportedAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      this.dispatchedAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      this.resolvedAt})
      : _attachments = attachments;
  factory _Incident.fromJson(Map<String, dynamic> json) =>
      _$IncidentFromJson(json);

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
  @JsonKey()
  final String status;
// Using String for Firestore compatibility but validated by IncidentStatus
  @override
  @JsonKey()
  final String priority;
  @override
  @JsonKey()
  final bool isCritical;
  @override
  final String? assignedToUid;
  @override
  final String? assignedToName;
  @override
  final String? dispatchedByUid;
  @override
  final String? geoLga;
  @override
  final String? geoWard;
  @override
  final String? geoPu;
  final List<String> _attachments;
  @override
  @JsonKey()
  List<String> get attachments {
    if (_attachments is EqualUnmodifiableListView) return _attachments;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_attachments);
  }

  @override
  @JsonKey()
  final String syncStatus;
  @override
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  final DateTime? reportedAt;
  @override
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  final DateTime? dispatchedAt;
  @override
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  final DateTime? resolvedAt;

  /// Create a copy of Incident
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$IncidentCopyWith<_Incident> get copyWith =>
      __$IncidentCopyWithImpl<_Incident>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$IncidentToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Incident &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.lat, lat) || other.lat == lat) &&
            (identical(other.lng, lng) || other.lng == lng) &&
            (identical(other.reportedBy, reportedBy) ||
                other.reportedBy == reportedBy) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.priority, priority) ||
                other.priority == priority) &&
            (identical(other.isCritical, isCritical) ||
                other.isCritical == isCritical) &&
            (identical(other.assignedToUid, assignedToUid) ||
                other.assignedToUid == assignedToUid) &&
            (identical(other.assignedToName, assignedToName) ||
                other.assignedToName == assignedToName) &&
            (identical(other.dispatchedByUid, dispatchedByUid) ||
                other.dispatchedByUid == dispatchedByUid) &&
            (identical(other.geoLga, geoLga) || other.geoLga == geoLga) &&
            (identical(other.geoWard, geoWard) || other.geoWard == geoWard) &&
            (identical(other.geoPu, geoPu) || other.geoPu == geoPu) &&
            const DeepCollectionEquality()
                .equals(other._attachments, _attachments) &&
            (identical(other.syncStatus, syncStatus) ||
                other.syncStatus == syncStatus) &&
            (identical(other.reportedAt, reportedAt) ||
                other.reportedAt == reportedAt) &&
            (identical(other.dispatchedAt, dispatchedAt) ||
                other.dispatchedAt == dispatchedAt) &&
            (identical(other.resolvedAt, resolvedAt) ||
                other.resolvedAt == resolvedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        type,
        description,
        lat,
        lng,
        reportedBy,
        status,
        priority,
        isCritical,
        assignedToUid,
        assignedToName,
        dispatchedByUid,
        geoLga,
        geoWard,
        geoPu,
        const DeepCollectionEquality().hash(_attachments),
        syncStatus,
        reportedAt,
        dispatchedAt,
        resolvedAt
      ]);

  @override
  String toString() {
    return 'Incident(id: $id, type: $type, description: $description, lat: $lat, lng: $lng, reportedBy: $reportedBy, status: $status, priority: $priority, isCritical: $isCritical, assignedToUid: $assignedToUid, assignedToName: $assignedToName, dispatchedByUid: $dispatchedByUid, geoLga: $geoLga, geoWard: $geoWard, geoPu: $geoPu, attachments: $attachments, syncStatus: $syncStatus, reportedAt: $reportedAt, dispatchedAt: $dispatchedAt, resolvedAt: $resolvedAt)';
  }
}

/// @nodoc
abstract mixin class _$IncidentCopyWith<$Res>
    implements $IncidentCopyWith<$Res> {
  factory _$IncidentCopyWith(_Incident value, $Res Function(_Incident) _then) =
      __$IncidentCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String type,
      String description,
      double lat,
      double lng,
      String reportedBy,
      String status,
      String priority,
      bool isCritical,
      String? assignedToUid,
      String? assignedToName,
      String? dispatchedByUid,
      String? geoLga,
      String? geoWard,
      String? geoPu,
      List<String> attachments,
      String syncStatus,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? reportedAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? dispatchedAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? resolvedAt});
}

/// @nodoc
class __$IncidentCopyWithImpl<$Res> implements _$IncidentCopyWith<$Res> {
  __$IncidentCopyWithImpl(this._self, this._then);

  final _Incident _self;
  final $Res Function(_Incident) _then;

  /// Create a copy of Incident
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
    Object? status = null,
    Object? priority = null,
    Object? isCritical = null,
    Object? assignedToUid = freezed,
    Object? assignedToName = freezed,
    Object? dispatchedByUid = freezed,
    Object? geoLga = freezed,
    Object? geoWard = freezed,
    Object? geoPu = freezed,
    Object? attachments = null,
    Object? syncStatus = null,
    Object? reportedAt = freezed,
    Object? dispatchedAt = freezed,
    Object? resolvedAt = freezed,
  }) {
    return _then(_Incident(
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
      status: null == status
          ? _self.status
          : status // ignore: cast_nullable_to_non_nullable
              as String,
      priority: null == priority
          ? _self.priority
          : priority // ignore: cast_nullable_to_non_nullable
              as String,
      isCritical: null == isCritical
          ? _self.isCritical
          : isCritical // ignore: cast_nullable_to_non_nullable
              as bool,
      assignedToUid: freezed == assignedToUid
          ? _self.assignedToUid
          : assignedToUid // ignore: cast_nullable_to_non_nullable
              as String?,
      assignedToName: freezed == assignedToName
          ? _self.assignedToName
          : assignedToName // ignore: cast_nullable_to_non_nullable
              as String?,
      dispatchedByUid: freezed == dispatchedByUid
          ? _self.dispatchedByUid
          : dispatchedByUid // ignore: cast_nullable_to_non_nullable
              as String?,
      geoLga: freezed == geoLga
          ? _self.geoLga
          : geoLga // ignore: cast_nullable_to_non_nullable
              as String?,
      geoWard: freezed == geoWard
          ? _self.geoWard
          : geoWard // ignore: cast_nullable_to_non_nullable
              as String?,
      geoPu: freezed == geoPu
          ? _self.geoPu
          : geoPu // ignore: cast_nullable_to_non_nullable
              as String?,
      attachments: null == attachments
          ? _self._attachments
          : attachments // ignore: cast_nullable_to_non_nullable
              as List<String>,
      syncStatus: null == syncStatus
          ? _self.syncStatus
          : syncStatus // ignore: cast_nullable_to_non_nullable
              as String,
      reportedAt: freezed == reportedAt
          ? _self.reportedAt
          : reportedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      dispatchedAt: freezed == dispatchedAt
          ? _self.dispatchedAt
          : dispatchedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      resolvedAt: freezed == resolvedAt
          ? _self.resolvedAt
          : resolvedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
mixin _$IncidentState {
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is IncidentState);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'IncidentState()';
  }
}

/// @nodoc
class $IncidentStateCopyWith<$Res> {
  $IncidentStateCopyWith(IncidentState _, $Res Function(IncidentState) __);
}

/// Adds pattern-matching-related methods to [IncidentState].
extension IncidentStatePatterns on IncidentState {
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
  TResult maybeMap<TResult extends Object?>({
    TResult Function(_Initial value)? initial,
    TResult Function(_Loading value)? loading,
    TResult Function(_Success value)? success,
    TResult Function(_Failure value)? failure,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Initial() when initial != null:
        return initial(_that);
      case _Loading() when loading != null:
        return loading(_that);
      case _Success() when success != null:
        return success(_that);
      case _Failure() when failure != null:
        return failure(_that);
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
  TResult map<TResult extends Object?>({
    required TResult Function(_Initial value) initial,
    required TResult Function(_Loading value) loading,
    required TResult Function(_Success value) success,
    required TResult Function(_Failure value) failure,
  }) {
    final _that = this;
    switch (_that) {
      case _Initial():
        return initial(_that);
      case _Loading():
        return loading(_that);
      case _Success():
        return success(_that);
      case _Failure():
        return failure(_that);
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
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(_Initial value)? initial,
    TResult? Function(_Loading value)? loading,
    TResult? Function(_Success value)? success,
    TResult? Function(_Failure value)? failure,
  }) {
    final _that = this;
    switch (_that) {
      case _Initial() when initial != null:
        return initial(_that);
      case _Loading() when loading != null:
        return loading(_that);
      case _Success() when success != null:
        return success(_that);
      case _Failure() when failure != null:
        return failure(_that);
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
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? initial,
    TResult Function()? loading,
    TResult Function(List<Incident> incidents)? success,
    TResult Function(String message)? failure,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _Initial() when initial != null:
        return initial();
      case _Loading() when loading != null:
        return loading();
      case _Success() when success != null:
        return success(_that.incidents);
      case _Failure() when failure != null:
        return failure(_that.message);
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
  TResult when<TResult extends Object?>({
    required TResult Function() initial,
    required TResult Function() loading,
    required TResult Function(List<Incident> incidents) success,
    required TResult Function(String message) failure,
  }) {
    final _that = this;
    switch (_that) {
      case _Initial():
        return initial();
      case _Loading():
        return loading();
      case _Success():
        return success(_that.incidents);
      case _Failure():
        return failure(_that.message);
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
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? initial,
    TResult? Function()? loading,
    TResult? Function(List<Incident> incidents)? success,
    TResult? Function(String message)? failure,
  }) {
    final _that = this;
    switch (_that) {
      case _Initial() when initial != null:
        return initial();
      case _Loading() when loading != null:
        return loading();
      case _Success() when success != null:
        return success(_that.incidents);
      case _Failure() when failure != null:
        return failure(_that.message);
      case _:
        return null;
    }
  }
}

/// @nodoc

class _Initial implements IncidentState {
  const _Initial();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _Initial);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'IncidentState.initial()';
  }
}

/// @nodoc

class _Loading implements IncidentState {
  const _Loading();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _Loading);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'IncidentState.loading()';
  }
}

/// @nodoc

class _Success implements IncidentState {
  const _Success(final List<Incident> incidents) : _incidents = incidents;

  final List<Incident> _incidents;
  List<Incident> get incidents {
    if (_incidents is EqualUnmodifiableListView) return _incidents;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_incidents);
  }

  /// Create a copy of IncidentState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$SuccessCopyWith<_Success> get copyWith =>
      __$SuccessCopyWithImpl<_Success>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Success &&
            const DeepCollectionEquality()
                .equals(other._incidents, _incidents));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, const DeepCollectionEquality().hash(_incidents));

  @override
  String toString() {
    return 'IncidentState.success(incidents: $incidents)';
  }
}

/// @nodoc
abstract mixin class _$SuccessCopyWith<$Res>
    implements $IncidentStateCopyWith<$Res> {
  factory _$SuccessCopyWith(_Success value, $Res Function(_Success) _then) =
      __$SuccessCopyWithImpl;
  @useResult
  $Res call({List<Incident> incidents});
}

/// @nodoc
class __$SuccessCopyWithImpl<$Res> implements _$SuccessCopyWith<$Res> {
  __$SuccessCopyWithImpl(this._self, this._then);

  final _Success _self;
  final $Res Function(_Success) _then;

  /// Create a copy of IncidentState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? incidents = null,
  }) {
    return _then(_Success(
      null == incidents
          ? _self._incidents
          : incidents // ignore: cast_nullable_to_non_nullable
              as List<Incident>,
    ));
  }
}

/// @nodoc

class _Failure implements IncidentState {
  const _Failure(this.message);

  final String message;

  /// Create a copy of IncidentState
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$FailureCopyWith<_Failure> get copyWith =>
      __$FailureCopyWithImpl<_Failure>(this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _Failure &&
            (identical(other.message, message) || other.message == message));
  }

  @override
  int get hashCode => Object.hash(runtimeType, message);

  @override
  String toString() {
    return 'IncidentState.failure(message: $message)';
  }
}

/// @nodoc
abstract mixin class _$FailureCopyWith<$Res>
    implements $IncidentStateCopyWith<$Res> {
  factory _$FailureCopyWith(_Failure value, $Res Function(_Failure) _then) =
      __$FailureCopyWithImpl;
  @useResult
  $Res call({String message});
}

/// @nodoc
class __$FailureCopyWithImpl<$Res> implements _$FailureCopyWith<$Res> {
  __$FailureCopyWithImpl(this._self, this._then);

  final _Failure _self;
  final $Res Function(_Failure) _then;

  /// Create a copy of IncidentState
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? message = null,
  }) {
    return _then(_Failure(
      null == message
          ? _self.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on

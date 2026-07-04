// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'broadcast_alert.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$BroadcastAlert {
  String get id;
  String get message;
  String get severity; // INFO, MEDIUM, HIGH, CRITICAL
  bool get active;
  String? get targetLga;
  String? get targetWard;
  String? get targetPu;
  String get targetAudience; // ALL, STAFF, USER
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  DateTime? get createdAt;
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  DateTime? get expiresAt;
  List<String>? get acknowledgedBy;

  /// Create a copy of BroadcastAlert
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $BroadcastAlertCopyWith<BroadcastAlert> get copyWith =>
      _$BroadcastAlertCopyWithImpl<BroadcastAlert>(
          this as BroadcastAlert, _$identity);

  /// Serializes this BroadcastAlert to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is BroadcastAlert &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.severity, severity) ||
                other.severity == severity) &&
            (identical(other.active, active) || other.active == active) &&
            (identical(other.targetLga, targetLga) ||
                other.targetLga == targetLga) &&
            (identical(other.targetWard, targetWard) ||
                other.targetWard == targetWard) &&
            (identical(other.targetPu, targetPu) ||
                other.targetPu == targetPu) &&
            (identical(other.targetAudience, targetAudience) ||
                other.targetAudience == targetAudience) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.expiresAt, expiresAt) ||
                other.expiresAt == expiresAt) &&
            const DeepCollectionEquality()
                .equals(other.acknowledgedBy, acknowledgedBy));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      message,
      severity,
      active,
      targetLga,
      targetWard,
      targetPu,
      targetAudience,
      createdAt,
      expiresAt,
      const DeepCollectionEquality().hash(acknowledgedBy));

  @override
  String toString() {
    return 'BroadcastAlert(id: $id, message: $message, severity: $severity, active: $active, targetLga: $targetLga, targetWard: $targetWard, targetPu: $targetPu, targetAudience: $targetAudience, createdAt: $createdAt, expiresAt: $expiresAt, acknowledgedBy: $acknowledgedBy)';
  }
}

/// @nodoc
abstract mixin class $BroadcastAlertCopyWith<$Res> {
  factory $BroadcastAlertCopyWith(
          BroadcastAlert value, $Res Function(BroadcastAlert) _then) =
      _$BroadcastAlertCopyWithImpl;
  @useResult
  $Res call(
      {String id,
      String message,
      String severity,
      bool active,
      String? targetLga,
      String? targetWard,
      String? targetPu,
      String targetAudience,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? createdAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? expiresAt,
      List<String>? acknowledgedBy});
}

/// @nodoc
class _$BroadcastAlertCopyWithImpl<$Res>
    implements $BroadcastAlertCopyWith<$Res> {
  _$BroadcastAlertCopyWithImpl(this._self, this._then);

  final BroadcastAlert _self;
  final $Res Function(BroadcastAlert) _then;

  /// Create a copy of BroadcastAlert
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? message = null,
    Object? severity = null,
    Object? active = null,
    Object? targetLga = freezed,
    Object? targetWard = freezed,
    Object? targetPu = freezed,
    Object? targetAudience = null,
    Object? createdAt = freezed,
    Object? expiresAt = freezed,
    Object? acknowledgedBy = freezed,
  }) {
    return _then(_self.copyWith(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      message: null == message
          ? _self.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      severity: null == severity
          ? _self.severity
          : severity // ignore: cast_nullable_to_non_nullable
              as String,
      active: null == active
          ? _self.active
          : active // ignore: cast_nullable_to_non_nullable
              as bool,
      targetLga: freezed == targetLga
          ? _self.targetLga
          : targetLga // ignore: cast_nullable_to_non_nullable
              as String?,
      targetWard: freezed == targetWard
          ? _self.targetWard
          : targetWard // ignore: cast_nullable_to_non_nullable
              as String?,
      targetPu: freezed == targetPu
          ? _self.targetPu
          : targetPu // ignore: cast_nullable_to_non_nullable
              as String?,
      targetAudience: null == targetAudience
          ? _self.targetAudience
          : targetAudience // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: freezed == createdAt
          ? _self.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      expiresAt: freezed == expiresAt
          ? _self.expiresAt
          : expiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      acknowledgedBy: freezed == acknowledgedBy
          ? _self.acknowledgedBy
          : acknowledgedBy // ignore: cast_nullable_to_non_nullable
              as List<String>?,
    ));
  }
}

/// Adds pattern-matching-related methods to [BroadcastAlert].
extension BroadcastAlertPatterns on BroadcastAlert {
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
    TResult Function(_BroadcastAlert value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _BroadcastAlert() when $default != null:
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
    TResult Function(_BroadcastAlert value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BroadcastAlert():
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
    TResult? Function(_BroadcastAlert value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BroadcastAlert() when $default != null:
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
            String message,
            String severity,
            bool active,
            String? targetLga,
            String? targetWard,
            String? targetPu,
            String targetAudience,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? createdAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? expiresAt,
            List<String>? acknowledgedBy)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _BroadcastAlert() when $default != null:
        return $default(
            _that.id,
            _that.message,
            _that.severity,
            _that.active,
            _that.targetLga,
            _that.targetWard,
            _that.targetPu,
            _that.targetAudience,
            _that.createdAt,
            _that.expiresAt,
            _that.acknowledgedBy);
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
            String message,
            String severity,
            bool active,
            String? targetLga,
            String? targetWard,
            String? targetPu,
            String targetAudience,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? createdAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? expiresAt,
            List<String>? acknowledgedBy)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BroadcastAlert():
        return $default(
            _that.id,
            _that.message,
            _that.severity,
            _that.active,
            _that.targetLga,
            _that.targetWard,
            _that.targetPu,
            _that.targetAudience,
            _that.createdAt,
            _that.expiresAt,
            _that.acknowledgedBy);
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
            String message,
            String severity,
            bool active,
            String? targetLga,
            String? targetWard,
            String? targetPu,
            String targetAudience,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? createdAt,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? expiresAt,
            List<String>? acknowledgedBy)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _BroadcastAlert() when $default != null:
        return $default(
            _that.id,
            _that.message,
            _that.severity,
            _that.active,
            _that.targetLga,
            _that.targetWard,
            _that.targetPu,
            _that.targetAudience,
            _that.createdAt,
            _that.expiresAt,
            _that.acknowledgedBy);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _BroadcastAlert implements BroadcastAlert {
  const _BroadcastAlert(
      {required this.id,
      required this.message,
      this.severity = 'INFO',
      this.active = true,
      this.targetLga,
      this.targetWard,
      this.targetPu,
      this.targetAudience = 'ALL',
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      this.createdAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      this.expiresAt,
      final List<String>? acknowledgedBy})
      : _acknowledgedBy = acknowledgedBy;
  factory _BroadcastAlert.fromJson(Map<String, dynamic> json) =>
      _$BroadcastAlertFromJson(json);

  @override
  final String id;
  @override
  final String message;
  @override
  @JsonKey()
  final String severity;
// INFO, MEDIUM, HIGH, CRITICAL
  @override
  @JsonKey()
  final bool active;
  @override
  final String? targetLga;
  @override
  final String? targetWard;
  @override
  final String? targetPu;
  @override
  @JsonKey()
  final String targetAudience;
// ALL, STAFF, USER
  @override
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  final DateTime? createdAt;
  @override
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  final DateTime? expiresAt;
  final List<String>? _acknowledgedBy;
  @override
  List<String>? get acknowledgedBy {
    final value = _acknowledgedBy;
    if (value == null) return null;
    if (_acknowledgedBy is EqualUnmodifiableListView) return _acknowledgedBy;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  /// Create a copy of BroadcastAlert
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$BroadcastAlertCopyWith<_BroadcastAlert> get copyWith =>
      __$BroadcastAlertCopyWithImpl<_BroadcastAlert>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$BroadcastAlertToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _BroadcastAlert &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.severity, severity) ||
                other.severity == severity) &&
            (identical(other.active, active) || other.active == active) &&
            (identical(other.targetLga, targetLga) ||
                other.targetLga == targetLga) &&
            (identical(other.targetWard, targetWard) ||
                other.targetWard == targetWard) &&
            (identical(other.targetPu, targetPu) ||
                other.targetPu == targetPu) &&
            (identical(other.targetAudience, targetAudience) ||
                other.targetAudience == targetAudience) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.expiresAt, expiresAt) ||
                other.expiresAt == expiresAt) &&
            const DeepCollectionEquality()
                .equals(other._acknowledgedBy, _acknowledgedBy));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      message,
      severity,
      active,
      targetLga,
      targetWard,
      targetPu,
      targetAudience,
      createdAt,
      expiresAt,
      const DeepCollectionEquality().hash(_acknowledgedBy));

  @override
  String toString() {
    return 'BroadcastAlert(id: $id, message: $message, severity: $severity, active: $active, targetLga: $targetLga, targetWard: $targetWard, targetPu: $targetPu, targetAudience: $targetAudience, createdAt: $createdAt, expiresAt: $expiresAt, acknowledgedBy: $acknowledgedBy)';
  }
}

/// @nodoc
abstract mixin class _$BroadcastAlertCopyWith<$Res>
    implements $BroadcastAlertCopyWith<$Res> {
  factory _$BroadcastAlertCopyWith(
          _BroadcastAlert value, $Res Function(_BroadcastAlert) _then) =
      __$BroadcastAlertCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String id,
      String message,
      String severity,
      bool active,
      String? targetLga,
      String? targetWard,
      String? targetPu,
      String targetAudience,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? createdAt,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? expiresAt,
      List<String>? acknowledgedBy});
}

/// @nodoc
class __$BroadcastAlertCopyWithImpl<$Res>
    implements _$BroadcastAlertCopyWith<$Res> {
  __$BroadcastAlertCopyWithImpl(this._self, this._then);

  final _BroadcastAlert _self;
  final $Res Function(_BroadcastAlert) _then;

  /// Create a copy of BroadcastAlert
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? id = null,
    Object? message = null,
    Object? severity = null,
    Object? active = null,
    Object? targetLga = freezed,
    Object? targetWard = freezed,
    Object? targetPu = freezed,
    Object? targetAudience = null,
    Object? createdAt = freezed,
    Object? expiresAt = freezed,
    Object? acknowledgedBy = freezed,
  }) {
    return _then(_BroadcastAlert(
      id: null == id
          ? _self.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      message: null == message
          ? _self.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      severity: null == severity
          ? _self.severity
          : severity // ignore: cast_nullable_to_non_nullable
              as String,
      active: null == active
          ? _self.active
          : active // ignore: cast_nullable_to_non_nullable
              as bool,
      targetLga: freezed == targetLga
          ? _self.targetLga
          : targetLga // ignore: cast_nullable_to_non_nullable
              as String?,
      targetWard: freezed == targetWard
          ? _self.targetWard
          : targetWard // ignore: cast_nullable_to_non_nullable
              as String?,
      targetPu: freezed == targetPu
          ? _self.targetPu
          : targetPu // ignore: cast_nullable_to_non_nullable
              as String?,
      targetAudience: null == targetAudience
          ? _self.targetAudience
          : targetAudience // ignore: cast_nullable_to_non_nullable
              as String,
      createdAt: freezed == createdAt
          ? _self.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      expiresAt: freezed == expiresAt
          ? _self.expiresAt
          : expiresAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      acknowledgedBy: freezed == acknowledgedBy
          ? _self._acknowledgedBy
          : acknowledgedBy // ignore: cast_nullable_to_non_nullable
              as List<String>?,
    ));
  }
}

// dart format on

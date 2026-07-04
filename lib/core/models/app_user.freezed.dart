// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_user.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$AppUser {
  String get uid;
  String get email;
  String get displayName;
  String? get phone;
  String? get avatarUrl;
  bool get isStaff;
  String get role; // USER, UNIT_COMMAND, WARD_COMMAND, LGA_COMMAND, HQ_OFFICER
  List<String>? get geoLgas;
  List<String>? get geoWards;
  List<String>? get geoPus;
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  DateTime? get lastActive;
  bool get active;

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $AppUserCopyWith<AppUser> get copyWith =>
      _$AppUserCopyWithImpl<AppUser>(this as AppUser, _$identity);

  /// Serializes this AppUser to a JSON map.
  Map<String, dynamic> toJson();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is AppUser &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.phone, phone) || other.phone == phone) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.isStaff, isStaff) || other.isStaff == isStaff) &&
            (identical(other.role, role) || other.role == role) &&
            const DeepCollectionEquality().equals(other.geoLgas, geoLgas) &&
            const DeepCollectionEquality().equals(other.geoWards, geoWards) &&
            const DeepCollectionEquality().equals(other.geoPus, geoPus) &&
            (identical(other.lastActive, lastActive) ||
                other.lastActive == lastActive) &&
            (identical(other.active, active) || other.active == active));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uid,
      email,
      displayName,
      phone,
      avatarUrl,
      isStaff,
      role,
      const DeepCollectionEquality().hash(geoLgas),
      const DeepCollectionEquality().hash(geoWards),
      const DeepCollectionEquality().hash(geoPus),
      lastActive,
      active);

  @override
  String toString() {
    return 'AppUser(uid: $uid, email: $email, displayName: $displayName, phone: $phone, avatarUrl: $avatarUrl, isStaff: $isStaff, role: $role, geoLgas: $geoLgas, geoWards: $geoWards, geoPus: $geoPus, lastActive: $lastActive, active: $active)';
  }
}

/// @nodoc
abstract mixin class $AppUserCopyWith<$Res> {
  factory $AppUserCopyWith(AppUser value, $Res Function(AppUser) _then) =
      _$AppUserCopyWithImpl;
  @useResult
  $Res call(
      {String uid,
      String email,
      String displayName,
      String? phone,
      String? avatarUrl,
      bool isStaff,
      String role,
      List<String>? geoLgas,
      List<String>? geoWards,
      List<String>? geoPus,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? lastActive,
      bool active});
}

/// @nodoc
class _$AppUserCopyWithImpl<$Res> implements $AppUserCopyWith<$Res> {
  _$AppUserCopyWithImpl(this._self, this._then);

  final AppUser _self;
  final $Res Function(AppUser) _then;

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uid = null,
    Object? email = null,
    Object? displayName = null,
    Object? phone = freezed,
    Object? avatarUrl = freezed,
    Object? isStaff = null,
    Object? role = null,
    Object? geoLgas = freezed,
    Object? geoWards = freezed,
    Object? geoPus = freezed,
    Object? lastActive = freezed,
    Object? active = null,
  }) {
    return _then(_self.copyWith(
      uid: null == uid
          ? _self.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      email: null == email
          ? _self.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _self.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
      phone: freezed == phone
          ? _self.phone
          : phone // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarUrl: freezed == avatarUrl
          ? _self.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      isStaff: null == isStaff
          ? _self.isStaff
          : isStaff // ignore: cast_nullable_to_non_nullable
              as bool,
      role: null == role
          ? _self.role
          : role // ignore: cast_nullable_to_non_nullable
              as String,
      geoLgas: freezed == geoLgas
          ? _self.geoLgas
          : geoLgas // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      geoWards: freezed == geoWards
          ? _self.geoWards
          : geoWards // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      geoPus: freezed == geoPus
          ? _self.geoPus
          : geoPus // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      lastActive: freezed == lastActive
          ? _self.lastActive
          : lastActive // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      active: null == active
          ? _self.active
          : active // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// Adds pattern-matching-related methods to [AppUser].
extension AppUserPatterns on AppUser {
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
    TResult Function(_AppUser value)? $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AppUser() when $default != null:
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
    TResult Function(_AppUser value) $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AppUser():
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
    TResult? Function(_AppUser value)? $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AppUser() when $default != null:
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
            String uid,
            String email,
            String displayName,
            String? phone,
            String? avatarUrl,
            bool isStaff,
            String role,
            List<String>? geoLgas,
            List<String>? geoWards,
            List<String>? geoPus,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? lastActive,
            bool active)?
        $default, {
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case _AppUser() when $default != null:
        return $default(
            _that.uid,
            _that.email,
            _that.displayName,
            _that.phone,
            _that.avatarUrl,
            _that.isStaff,
            _that.role,
            _that.geoLgas,
            _that.geoWards,
            _that.geoPus,
            _that.lastActive,
            _that.active);
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
            String uid,
            String email,
            String displayName,
            String? phone,
            String? avatarUrl,
            bool isStaff,
            String role,
            List<String>? geoLgas,
            List<String>? geoWards,
            List<String>? geoPus,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? lastActive,
            bool active)
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AppUser():
        return $default(
            _that.uid,
            _that.email,
            _that.displayName,
            _that.phone,
            _that.avatarUrl,
            _that.isStaff,
            _that.role,
            _that.geoLgas,
            _that.geoWards,
            _that.geoPus,
            _that.lastActive,
            _that.active);
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
            String uid,
            String email,
            String displayName,
            String? phone,
            String? avatarUrl,
            bool isStaff,
            String role,
            List<String>? geoLgas,
            List<String>? geoWards,
            List<String>? geoPus,
            @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
            DateTime? lastActive,
            bool active)?
        $default,
  ) {
    final _that = this;
    switch (_that) {
      case _AppUser() when $default != null:
        return $default(
            _that.uid,
            _that.email,
            _that.displayName,
            _that.phone,
            _that.avatarUrl,
            _that.isStaff,
            _that.role,
            _that.geoLgas,
            _that.geoWards,
            _that.geoPus,
            _that.lastActive,
            _that.active);
      case _:
        return null;
    }
  }
}

/// @nodoc
@JsonSerializable()
class _AppUser implements AppUser {
  const _AppUser(
      {required this.uid,
      required this.email,
      required this.displayName,
      this.phone,
      this.avatarUrl,
      this.isStaff = false,
      this.role = 'USER',
      final List<String>? geoLgas,
      final List<String>? geoWards,
      final List<String>? geoPus,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      this.lastActive,
      this.active = true})
      : _geoLgas = geoLgas,
        _geoWards = geoWards,
        _geoPus = geoPus;
  factory _AppUser.fromJson(Map<String, dynamic> json) =>
      _$AppUserFromJson(json);

  @override
  final String uid;
  @override
  final String email;
  @override
  final String displayName;
  @override
  final String? phone;
  @override
  final String? avatarUrl;
  @override
  @JsonKey()
  final bool isStaff;
  @override
  @JsonKey()
  final String role;
// USER, UNIT_COMMAND, WARD_COMMAND, LGA_COMMAND, HQ_OFFICER
  final List<String>? _geoLgas;
// USER, UNIT_COMMAND, WARD_COMMAND, LGA_COMMAND, HQ_OFFICER
  @override
  List<String>? get geoLgas {
    final value = _geoLgas;
    if (value == null) return null;
    if (_geoLgas is EqualUnmodifiableListView) return _geoLgas;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  final List<String>? _geoWards;
  @override
  List<String>? get geoWards {
    final value = _geoWards;
    if (value == null) return null;
    if (_geoWards is EqualUnmodifiableListView) return _geoWards;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  final List<String>? _geoPus;
  @override
  List<String>? get geoPus {
    final value = _geoPus;
    if (value == null) return null;
    if (_geoPus is EqualUnmodifiableListView) return _geoPus;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(value);
  }

  @override
  @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
  final DateTime? lastActive;
  @override
  @JsonKey()
  final bool active;

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  _$AppUserCopyWith<_AppUser> get copyWith =>
      __$AppUserCopyWithImpl<_AppUser>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$AppUserToJson(
      this,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _AppUser &&
            (identical(other.uid, uid) || other.uid == uid) &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.displayName, displayName) ||
                other.displayName == displayName) &&
            (identical(other.phone, phone) || other.phone == phone) &&
            (identical(other.avatarUrl, avatarUrl) ||
                other.avatarUrl == avatarUrl) &&
            (identical(other.isStaff, isStaff) || other.isStaff == isStaff) &&
            (identical(other.role, role) || other.role == role) &&
            const DeepCollectionEquality().equals(other._geoLgas, _geoLgas) &&
            const DeepCollectionEquality().equals(other._geoWards, _geoWards) &&
            const DeepCollectionEquality().equals(other._geoPus, _geoPus) &&
            (identical(other.lastActive, lastActive) ||
                other.lastActive == lastActive) &&
            (identical(other.active, active) || other.active == active));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      uid,
      email,
      displayName,
      phone,
      avatarUrl,
      isStaff,
      role,
      const DeepCollectionEquality().hash(_geoLgas),
      const DeepCollectionEquality().hash(_geoWards),
      const DeepCollectionEquality().hash(_geoPus),
      lastActive,
      active);

  @override
  String toString() {
    return 'AppUser(uid: $uid, email: $email, displayName: $displayName, phone: $phone, avatarUrl: $avatarUrl, isStaff: $isStaff, role: $role, geoLgas: $geoLgas, geoWards: $geoWards, geoPus: $geoPus, lastActive: $lastActive, active: $active)';
  }
}

/// @nodoc
abstract mixin class _$AppUserCopyWith<$Res> implements $AppUserCopyWith<$Res> {
  factory _$AppUserCopyWith(_AppUser value, $Res Function(_AppUser) _then) =
      __$AppUserCopyWithImpl;
  @override
  @useResult
  $Res call(
      {String uid,
      String email,
      String displayName,
      String? phone,
      String? avatarUrl,
      bool isStaff,
      String role,
      List<String>? geoLgas,
      List<String>? geoWards,
      List<String>? geoPus,
      @JsonKey(fromJson: _timestampFromJson, toJson: _timestampToJson)
      DateTime? lastActive,
      bool active});
}

/// @nodoc
class __$AppUserCopyWithImpl<$Res> implements _$AppUserCopyWith<$Res> {
  __$AppUserCopyWithImpl(this._self, this._then);

  final _AppUser _self;
  final $Res Function(_AppUser) _then;

  /// Create a copy of AppUser
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $Res call({
    Object? uid = null,
    Object? email = null,
    Object? displayName = null,
    Object? phone = freezed,
    Object? avatarUrl = freezed,
    Object? isStaff = null,
    Object? role = null,
    Object? geoLgas = freezed,
    Object? geoWards = freezed,
    Object? geoPus = freezed,
    Object? lastActive = freezed,
    Object? active = null,
  }) {
    return _then(_AppUser(
      uid: null == uid
          ? _self.uid
          : uid // ignore: cast_nullable_to_non_nullable
              as String,
      email: null == email
          ? _self.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      displayName: null == displayName
          ? _self.displayName
          : displayName // ignore: cast_nullable_to_non_nullable
              as String,
      phone: freezed == phone
          ? _self.phone
          : phone // ignore: cast_nullable_to_non_nullable
              as String?,
      avatarUrl: freezed == avatarUrl
          ? _self.avatarUrl
          : avatarUrl // ignore: cast_nullable_to_non_nullable
              as String?,
      isStaff: null == isStaff
          ? _self.isStaff
          : isStaff // ignore: cast_nullable_to_non_nullable
              as bool,
      role: null == role
          ? _self.role
          : role // ignore: cast_nullable_to_non_nullable
              as String,
      geoLgas: freezed == geoLgas
          ? _self._geoLgas
          : geoLgas // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      geoWards: freezed == geoWards
          ? _self._geoWards
          : geoWards // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      geoPus: freezed == geoPus
          ? _self._geoPus
          : geoPus // ignore: cast_nullable_to_non_nullable
              as List<String>?,
      lastActive: freezed == lastActive
          ? _self.lastActive
          : lastActive // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      active: null == active
          ? _self.active
          : active // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

// dart format on

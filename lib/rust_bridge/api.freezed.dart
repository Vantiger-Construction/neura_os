// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$SwarmVerdict {
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is SwarmVerdict);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'SwarmVerdict()';
  }
}

/// @nodoc
class $SwarmVerdictCopyWith<$Res> {
  $SwarmVerdictCopyWith(SwarmVerdict _, $Res Function(SwarmVerdict) __);
}

/// Adds pattern-matching-related methods to [SwarmVerdict].
extension SwarmVerdictPatterns on SwarmVerdict {
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
    TResult Function(SwarmVerdict_Pass value)? pass,
    TResult Function(SwarmVerdict_Concern value)? concern,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case SwarmVerdict_Pass() when pass != null:
        return pass(_that);
      case SwarmVerdict_Concern() when concern != null:
        return concern(_that);
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
    required TResult Function(SwarmVerdict_Pass value) pass,
    required TResult Function(SwarmVerdict_Concern value) concern,
  }) {
    final _that = this;
    switch (_that) {
      case SwarmVerdict_Pass():
        return pass(_that);
      case SwarmVerdict_Concern():
        return concern(_that);
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
    TResult? Function(SwarmVerdict_Pass value)? pass,
    TResult? Function(SwarmVerdict_Concern value)? concern,
  }) {
    final _that = this;
    switch (_that) {
      case SwarmVerdict_Pass() when pass != null:
        return pass(_that);
      case SwarmVerdict_Concern() when concern != null:
        return concern(_that);
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
    TResult Function()? pass,
    TResult Function(String note)? concern,
    required TResult orElse(),
  }) {
    final _that = this;
    switch (_that) {
      case SwarmVerdict_Pass() when pass != null:
        return pass();
      case SwarmVerdict_Concern() when concern != null:
        return concern(_that.note);
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
    required TResult Function() pass,
    required TResult Function(String note) concern,
  }) {
    final _that = this;
    switch (_that) {
      case SwarmVerdict_Pass():
        return pass();
      case SwarmVerdict_Concern():
        return concern(_that.note);
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
    TResult? Function()? pass,
    TResult? Function(String note)? concern,
  }) {
    final _that = this;
    switch (_that) {
      case SwarmVerdict_Pass() when pass != null:
        return pass();
      case SwarmVerdict_Concern() when concern != null:
        return concern(_that.note);
      case _:
        return null;
    }
  }
}

/// @nodoc

class SwarmVerdict_Pass extends SwarmVerdict {
  const SwarmVerdict_Pass() : super._();

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is SwarmVerdict_Pass);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() {
    return 'SwarmVerdict.pass()';
  }
}

/// @nodoc

class SwarmVerdict_Concern extends SwarmVerdict {
  const SwarmVerdict_Concern({required this.note}) : super._();

  final String note;

  /// Create a copy of SwarmVerdict
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @pragma('vm:prefer-inline')
  $SwarmVerdict_ConcernCopyWith<SwarmVerdict_Concern> get copyWith =>
      _$SwarmVerdict_ConcernCopyWithImpl<SwarmVerdict_Concern>(
          this, _$identity);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is SwarmVerdict_Concern &&
            (identical(other.note, note) || other.note == note));
  }

  @override
  int get hashCode {
    return Object.hash(runtimeType, note);
  }

  @override
  String toString() {
    return 'SwarmVerdict.concern(note: $note)';
  }
}

/// @nodoc
abstract mixin class $SwarmVerdict_ConcernCopyWith<$Res>
    implements $SwarmVerdictCopyWith<$Res> {
  factory $SwarmVerdict_ConcernCopyWith(SwarmVerdict_Concern value,
          $Res Function(SwarmVerdict_Concern) _then) =
      _$SwarmVerdict_ConcernCopyWithImpl;
  @useResult
  $Res call({String note});
}

/// @nodoc
class _$SwarmVerdict_ConcernCopyWithImpl<$Res>
    implements $SwarmVerdict_ConcernCopyWith<$Res> {
  _$SwarmVerdict_ConcernCopyWithImpl(this._self, this._then);

  final SwarmVerdict_Concern _self;
  final $Res Function(SwarmVerdict_Concern) _then;

  /// Create a copy of SwarmVerdict
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  $Res call({
    Object? note = null,
  }) {
    return _then(SwarmVerdict_Concern(
      note: null == note
          ? _self.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

// dart format on

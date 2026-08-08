// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$SwarmVerdict {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() pass,
    required TResult Function(String note) concern,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? pass,
    TResult? Function(String note)? concern,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? pass,
    TResult Function(String note)? concern,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SwarmVerdict_Pass value) pass,
    required TResult Function(SwarmVerdict_Concern value) concern,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SwarmVerdict_Pass value)? pass,
    TResult? Function(SwarmVerdict_Concern value)? concern,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SwarmVerdict_Pass value)? pass,
    TResult Function(SwarmVerdict_Concern value)? concern,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SwarmVerdictCopyWith<$Res> {
  factory $SwarmVerdictCopyWith(
          SwarmVerdict value, $Res Function(SwarmVerdict) then) =
      _$SwarmVerdictCopyWithImpl<$Res, SwarmVerdict>;
}

/// @nodoc
class _$SwarmVerdictCopyWithImpl<$Res, $Val extends SwarmVerdict>
    implements $SwarmVerdictCopyWith<$Res> {
  _$SwarmVerdictCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$SwarmVerdict_PassImplCopyWith<$Res> {
  factory _$$SwarmVerdict_PassImplCopyWith(_$SwarmVerdict_PassImpl value,
          $Res Function(_$SwarmVerdict_PassImpl) then) =
      __$$SwarmVerdict_PassImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$SwarmVerdict_PassImplCopyWithImpl<$Res>
    extends _$SwarmVerdictCopyWithImpl<$Res, _$SwarmVerdict_PassImpl>
    implements _$$SwarmVerdict_PassImplCopyWith<$Res> {
  __$$SwarmVerdict_PassImplCopyWithImpl(_$SwarmVerdict_PassImpl _value,
      $Res Function(_$SwarmVerdict_PassImpl) _then)
      : super(_value, _then);
}

/// @nodoc

class _$SwarmVerdict_PassImpl extends SwarmVerdict_Pass {
  const _$SwarmVerdict_PassImpl() : super._();

  @override
  String toString() {
    return 'SwarmVerdict.pass()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType && other is _$SwarmVerdict_PassImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() pass,
    required TResult Function(String note) concern,
  }) {
    return pass();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? pass,
    TResult? Function(String note)? concern,
  }) {
    return pass?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? pass,
    TResult Function(String note)? concern,
    required TResult orElse(),
  }) {
    if (pass != null) {
      return pass();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SwarmVerdict_Pass value) pass,
    required TResult Function(SwarmVerdict_Concern value) concern,
  }) {
    return pass(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SwarmVerdict_Pass value)? pass,
    TResult? Function(SwarmVerdict_Concern value)? concern,
  }) {
    return pass?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SwarmVerdict_Pass value)? pass,
    TResult Function(SwarmVerdict_Concern value)? concern,
    required TResult orElse(),
  }) {
    if (pass != null) {
      return pass(this);
    }
    return orElse();
  }
}

abstract class SwarmVerdict_Pass extends SwarmVerdict {
  const factory SwarmVerdict_Pass() = _$SwarmVerdict_PassImpl;
  const SwarmVerdict_Pass._() : super._();
}

/// @nodoc
abstract class _$$SwarmVerdict_ConcernImplCopyWith<$Res> {
  factory _$$SwarmVerdict_ConcernImplCopyWith(_$SwarmVerdict_ConcernImpl value,
          $Res Function(_$SwarmVerdict_ConcernImpl) then) =
      __$$SwarmVerdict_ConcernImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String note});
}

/// @nodoc
class __$$SwarmVerdict_ConcernImplCopyWithImpl<$Res>
    extends _$SwarmVerdictCopyWithImpl<$Res, _$SwarmVerdict_ConcernImpl>
    implements _$$SwarmVerdict_ConcernImplCopyWith<$Res> {
  __$$SwarmVerdict_ConcernImplCopyWithImpl(_$SwarmVerdict_ConcernImpl _value,
      $Res Function(_$SwarmVerdict_ConcernImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? note = null,
  }) {
    return _then(_$SwarmVerdict_ConcernImpl(
      note: null == note
          ? _value.note
          : note // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc

class _$SwarmVerdict_ConcernImpl extends SwarmVerdict_Concern {
  const _$SwarmVerdict_ConcernImpl({required this.note}) : super._();

  @override
  final String note;

  @override
  String toString() {
    return 'SwarmVerdict.concern(note: $note)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SwarmVerdict_ConcernImpl &&
            (identical(other.note, note) || other.note == note));
  }

  @override
  int get hashCode => Object.hash(runtimeType, note);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SwarmVerdict_ConcernImplCopyWith<_$SwarmVerdict_ConcernImpl>
      get copyWith =>
          __$$SwarmVerdict_ConcernImplCopyWithImpl<_$SwarmVerdict_ConcernImpl>(
              this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function() pass,
    required TResult Function(String note) concern,
  }) {
    return concern(note);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function()? pass,
    TResult? Function(String note)? concern,
  }) {
    return concern?.call(note);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function()? pass,
    TResult Function(String note)? concern,
    required TResult orElse(),
  }) {
    if (concern != null) {
      return concern(note);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(SwarmVerdict_Pass value) pass,
    required TResult Function(SwarmVerdict_Concern value) concern,
  }) {
    return concern(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(SwarmVerdict_Pass value)? pass,
    TResult? Function(SwarmVerdict_Concern value)? concern,
  }) {
    return concern?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(SwarmVerdict_Pass value)? pass,
    TResult Function(SwarmVerdict_Concern value)? concern,
    required TResult orElse(),
  }) {
    if (concern != null) {
      return concern(this);
    }
    return orElse();
  }
}

abstract class SwarmVerdict_Concern extends SwarmVerdict {
  const factory SwarmVerdict_Concern({required final String note}) =
      _$SwarmVerdict_ConcernImpl;
  const SwarmVerdict_Concern._() : super._();

  String get note;
  @JsonKey(ignore: true)
  _$$SwarmVerdict_ConcernImplCopyWith<_$SwarmVerdict_ConcernImpl>
      get copyWith => throw _privateConstructorUsedError;
}

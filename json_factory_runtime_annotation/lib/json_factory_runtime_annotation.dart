/// Annotation consumed by `json_factory_runtime_generator`.
library;

import 'package:json_annotation/json_annotation.dart';

/// JSON field that carries the runtime key, unless configured otherwise.
const defaultJsonFactoryKeyField = '__type__';

/// Registers the enclosing `@JsonSerializable` class in a generated JSON
/// factory mixin.
///
/// Put it on a getter that returns the key as a string literal. Because this
/// is a [JsonKey], `json_serializable` writes the key into `toJson()` under
/// [name]; `fromJson` ignores it.
///
/// ```dart
/// @JsonSerializable()
/// class User {
///   @jsonFactoryKey()
///   String get factoryKey => 'user';
/// }
///
/// @JsonSerializable()
/// class Order {
///   @jsonFactoryKey(mixin: 'ApiMapper')
///   String get factoryKey => 'order';
/// }
///
/// @JsonSerializable()
/// class Member {
///   // Renamed from 'person'; JSON with "__type__": "person" still decodes.
///   @jsonFactoryKey(oldKeys: ['person'])
///   String get factoryKey => 'member';
/// }
/// ```
///
/// Keys, including [oldKeys], must be unique within one mixin; a duplicate
/// stops the build. [name]
/// must match the `key_field` option of `json_factory_aggregator` in
/// `build.yaml`, or the build stops.
// Lower-case so the annotation reads `@jsonFactoryKey(...)`.
// ignore: camel_case_types
class jsonFactoryKey extends JsonKey {
  /// Name of the generated mixin the class is registered in.
  ///
  /// Defaults to [defaultMixin] when omitted.
  final String? mixin;

  /// Previous keys of this class, still accepted when decoding.
  ///
  /// Lets a key be renamed without breaking JSON written with an old one.
  /// `toJson` writes only the current key. Old keys must be unique within the
  /// mixin, together with every class's current key.
  final List<String> oldKeys;

  const jsonFactoryKey({
    String name = defaultJsonFactoryKeyField,
    this.mixin,
    this.oldKeys = const [],
  }) : super(name: name, includeToJson: true, includeFromJson: false);

  /// Mixin name used when [mixin] is not given.
  static const String defaultMixin = 'JsonFactoryMapper';
}

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
/// ```
///
/// Keys must be unique within one mixin; a duplicate stops the build. [name]
/// must match the `key_field` option of `json_factory_aggregator` in
/// `build.yaml`, or the build stops.
// Lower-case so the annotation reads `@jsonFactoryKey(...)`.
// ignore: camel_case_types
class jsonFactoryKey extends JsonKey {
  /// Name of the generated mixin the class is registered in.
  ///
  /// Defaults to [defaultMixin] when omitted.
  final String? mixin;

  const jsonFactoryKey({
    String name = defaultJsonFactoryKeyField,
    this.mixin,
  }) : super(name: name, includeToJson: true, includeFromJson: false);

  /// Mixin name used when [mixin] is not given.
  static const String defaultMixin = 'JsonFactoryMapper';
}

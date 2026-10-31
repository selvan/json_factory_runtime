# Example

Run `dart run build_runner build` with [`json_factory_runtime_generator`](https://pub.dev/packages/json_factory_runtime_generator) and [`json_serializable`](https://pub.dev/packages/json_serializable) to generate `example.g.dart` and the factory mixins.

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:json_factory_runtime_annotation/json_factory_runtime_annotation.dart';

part 'example.g.dart';

@JsonSerializable()
class User {
  final String id;
  final String name;

  const User({required this.id, required this.name});

  /// Registers `User` under the key `'user'` in the default
  /// `JsonFactoryMapper` mixin. `toJson()` writes `"__type__": "user"`.
  @jsonFactoryKey()
  String get factoryKey => 'user';

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

/// Registered in a separate mixin, `ApiMapper`. Its key used to be
/// 'purchase'; JSON with "__type__": "purchase" still decodes to `Order`.
@JsonSerializable()
class Order {
  final String id;

  const Order({required this.id});

  @jsonFactoryKey(mixin: 'ApiMapper', oldKeys: ['purchase'])
  String get factoryKey => 'order';

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
  Map<String, dynamic> toJson() => _$OrderToJson(this);
}
```

A complete, runnable project is in the [generator's example](https://pub.dev/packages/json_factory_runtime_generator/example).

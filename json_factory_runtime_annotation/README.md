# json_factory_runtime_annotation

The `@jsonFactoryKey()` annotation for [`json_factory_runtime_generator`](https://pub.dev/packages/json_factory_runtime_generator).

Put it on a getter of a `@JsonSerializable` class. The generator then registers the class in a mixin that can rebuild it from JSON at runtime, using a key stored in the JSON itself.

```dart
@JsonSerializable()
class User {
  @jsonFactoryKey()                       // default mixin: JsonFactoryMapper
  String get factoryKey => 'user';
  ...
}

@JsonSerializable()
class Order {
  @jsonFactoryKey(mixin: 'ApiMapper')     // named mixin
  String get factoryKey => 'order';
  ...
}
```

`jsonFactoryKey` extends `JsonKey`, so `json_serializable` writes the key into `toJson()` (`"__type__": "user"`) and `fromJson` ignores it.

Add this package to `dependencies` and the generator to `dev_dependencies`. See the [generator's README](https://pub.dev/packages/json_factory_runtime_generator) for setup, configuration and the generated API.

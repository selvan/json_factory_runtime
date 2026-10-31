# Example

A small project that uses `json_factory_runtime_generator`.

- [`lib/models/`](lib/models/): `User` and `Address` in the default `JsonFactoryMapper` mixin (`Address` also accepts its old key `'location'`), `Order` and `ApiUser` in `ApiMapper`.
- [`build.yaml`](build.yaml): writes the mixins to `lib/src/factories/json_factory_runtime.g.dart`.
- [`lib/factories.dart`](lib/factories.dart): classes that mix them in.
- [`test/factory_test.dart`](test/factory_test.dart): round-trips JSON through the factories.

```dart
@JsonSerializable()
class User {
  final String id;
  final String name;

  const User({required this.id, required this.name});

  @jsonFactoryKey()
  String get factoryKey => 'user';

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
```

```dart
class ModelFactory with JsonFactoryMapper {
  const ModelFactory();
}

final json = const User(id: '1', name: 'Ada').toJson();
// {id: 1, name: Ada, __type__: user}

final user = const ModelFactory().fromKeyedJsonAs<User>(json);
```

Run it:

```bash
dart pub get
dart run build_runner build
dart test
```

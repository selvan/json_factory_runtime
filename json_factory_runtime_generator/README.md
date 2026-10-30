# json_factory_runtime_generator

Generates mixins that turn JSON back into the right `json_serializable` class at runtime, using a key stored in the JSON itself. You write no mapping by hand.

| Package | Add as | Contains |
|---|---|---|
| `json_factory_runtime_annotation` | `dependencies` | `@jsonFactoryKey(...)` |
| `json_factory_runtime_generator` | `dev_dependencies` | build_runner builders (auto-applied) |

The annotation has to be a normal dependency because your `lib/` code imports it. The generator is dev-only:

```bash
dart pub add json_factory_runtime_annotation json_annotation
dart pub add dev:json_factory_runtime_generator dev:json_serializable dev:build_runner
```

## Usage

Add a getter that returns the class's key, and annotate it with `@jsonFactoryKey()`. Parentheses are required, since it is a constructor call:

```dart
@JsonSerializable()
class User {
  ...
  @jsonFactoryKey()                       // default mixin: JsonFactoryMapper
  String get factoryKey => 'user';

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

@JsonSerializable()
class Order {
  ...
  @jsonFactoryKey(mixin: 'ApiMapper')     // named mixin
  String get factoryKey => 'order';
}
```

`jsonFactoryKey` extends `JsonKey`, so `json_serializable` writes the key into `toJson()` and `fromJson` ignores it:

```json
{"id": "1", "name": "Ada", "__type__": "user"}
```

The key is written for nested objects and lists as well.

### Renaming a key

To rename a key without breaking JSON that was already stored or sent with the old one, list the previous keys in `oldKeys`. It is optional; leave it out when a class has never been renamed.

```dart
@jsonFactoryKey(oldKeys: ['user', 'person'])
String get factoryKey => 'member';
```

`toJson()` now writes `"__type__": "member"`, and the generated mixin still decodes `"user"` and `"person"` to the same class.

```bash
dart run build_runner build
```

This writes `lib/generated/json_factory_runtime.g.dart` with one mixin per mixin name. For the models above, that is `JsonFactoryMapper` (holding `User`) and `ApiMapper` (holding `Order`).

## Using the generated mixins

A mixin can't be instantiated, so mix it into a class of your own. That can be an empty class:

```dart
import 'generated/json_factory_runtime.g.dart';

class ModelFactory with JsonFactoryMapper {
  const ModelFactory();
}

class ApiFactory with ApiMapper {
  const ApiFactory();
}
```

It can also be a class that already exists, such as a repository or an API client, which then gets the methods directly:

```dart
class UserRepository with JsonFactoryMapper {
  Future<Object> load(String id) async => fromKeyedJson(await _fetch(id));

  Future<Map<String, dynamic>> _fetch(String id) async => ...;
}
```

### Methods

| Member | Returns | Use when |
|---|---|---|
| `fromKeyedJson(json)` | `Object` | The key is in the JSON (`json['__type__']`). |
| `fromKeyedJsonAs<T>(json)` | `T` | Same, and you know the type you expect. |
| `fromJsonByKey(key, json)` | `Object` | The key comes from somewhere else, such as a URL or a header. |
| `fromJsonAs<T>(key, json)` | `T` | Same, typed. |
| `hasMapperKey(key)` | `bool` | Checking a key before decoding. Old keys count. |
| `mapperKeys` | `Iterable<String>` | Listing the current keys in the mixin. Old keys aren't listed. |
| `keyField` (static) | `String` | Reading the JSON field name, for example `JsonFactoryMapper.keyField`. |

`keyField` is static, so read it through the mixin (`JsonFactoryMapper.keyField`), not through your class (`ModelFactory.keyField` doesn't compile).

### Decoding a value whose type isn't known in advance

```dart
const factory = ModelFactory();

final json = jsonDecode(body) as Map<String, dynamic>;
// {"id": "1", "name": "Ada", "__type__": "user"}

switch (factory.fromKeyedJson(json)) {
  case User user:
    print('user ${user.name}');
  case Address address:
    print('address in ${address.city}');
  case final other:
    print('unhandled ${other.runtimeType}');
}
```

### Decoding a list of mixed types

Each item carries its own key, so one call per item rebuilds the right class:

```dart
final items = (jsonDecode(body) as List)
    .cast<Map<String, dynamic>>()
    .map(factory.fromKeyedJson)
    .toList();
// [User(...), Address(...), User(...)]
```

### Round trip

`toJson()` writes the key, so its output goes straight back through the factory:

```dart
final json = const User(id: '1', name: 'Ada').toJson();
final copy = factory.fromKeyedJsonAs<User>(json);
```

The same applies to stored data, such as a cache or a local database, as long as it was written with `toJson()`.

### Key passed separately

When the JSON has no key field, for example because it comes from an endpoint that always returns one type, pass the key yourself:

```dart
final user = factory.fromJsonAs<User>('user', json);
```

### Errors

Both of these throw an `ArgumentError`:

- `fromKeyedJson` when the JSON has no string key field.
- `fromJsonByKey` and `fromKeyedJson` when no class in that mixin is registered under the key.

Use `hasMapperKey` to check first when the input isn't trusted:

```dart
final key = json[JsonFactoryMapper.keyField];
if (key is String && factory.hasMapperKey(key)) {
  return factory.fromJsonByKey(key, json);
}
return null;
```

`fromKeyedJsonAs<T>` and `fromJsonAs<T>` also throw a `TypeError` if the decoded object isn't a `T`.

### Several mixins

Each mixin only knows its own classes. The same key can mean different classes in different mixins:

```dart
const ModelFactory().fromJsonByKey('user', json); // User
const ApiFactory().fromJsonByKey('user', json);   // ApiUser
const ApiFactory().hasMapperKey('address');       // false
```

## Configuration (`build.yaml` next to your `pubspec.yaml`)

```yaml
targets:
  $default:
    builders:
      json_factory_runtime_generator:json_factory_aggregator:
        options:
          output: lib/src/factories/json_factory_runtime.g.dart   # default: lib/generated/json_factory_runtime.g.dart
          key_field: kind                                  # default: __type__
```

- `output` must be a relative `.dart` path under `lib/`. All mixins go into this one file.
- `key_field` is the JSON field `fromKeyedJson` reads. The field `json_serializable` writes comes from the annotation, so every `@jsonFactoryKey` must use the same `name`, or the build stops. Defining the annotation once in your own code makes that easy:

  ```dart
  const typeKey = jsonFactoryKey(name: 'kind');
  const apiTypeKey = jsonFactoryKey(name: 'kind', mixin: 'ApiMapper');

  @typeKey
  String get factoryKey => 'user';
  ```

## Rules
- A key must be unique within a mixin. If two classes share one, the build stops and the error names both classes. The same key can be used in different mixins.
- Old keys count as keys: within a mixin, each old key must differ from every class's current key and every other old key, or the build stops and the error marks which side is the old key. An old key also can't be empty, repeat in the list, or equal its own class's current key.
- The annotated getter has to be an instance getter that returns a string literal: `=> 'user'` or `{ return 'user'; }`. Each class can have only one.
- The class must be annotated with `@JsonSerializable`; otherwise the build stops, because the key would never be written to its JSON.
- The class has to be public, non-generic and under `lib/`. It also needs a `fromJson(Map<String, dynamic>)` factory or static method.
- Every generated mixin has the same member names, so a class should mix in only one of them.

## Example

A complete project with models, a custom `build.yaml` and tests is in [`example/`](example/).

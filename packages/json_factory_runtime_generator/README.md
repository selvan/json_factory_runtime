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

Add a `final String` field holding the class's key, and annotate it with `@jsonFactoryKey()`. Parentheses are required, since it is a constructor call:

```dart
@JsonSerializable()
class User {
  ...
  @jsonFactoryKey()                       // default mixin: JsonFactoryMixin
  final String factoryKey = 'user';

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}

@JsonSerializable()
class Order {
  ...
  @jsonFactoryKey(mixin: 'ApiMixin')      // named mixin
  final String factoryKey = 'order';
}
```

`jsonFactoryKey` extends `JsonKey`, so `json_serializable` writes the key into `toJson()` and `fromJson` ignores it:

```json
{"id": "1", "name": "Ada", "__type__": "user"}
```

The key is written for nested objects and lists as well.

### Using an enum for the key

The field can also be an enum. The key is the constant's `@JsonValue`, which is what `json_serializable` writes into `toJson()`:

```dart
enum Kind {
  @JsonValue('user')
  user,
}

@JsonSerializable()
class User {
  ...
  @jsonFactoryKey()
  final Kind factoryKey = Kind.user;
}
```

The `@JsonValue` has to be a non-empty string. A constant without one stops the build.

### Renaming a key

To rename a key without breaking JSON that was already stored or sent with the old one, list the previous keys in `oldKeys`. It is optional; leave it out when a class has never been renamed.

```dart
@jsonFactoryKey(oldKeys: ['user', 'person'])
final String factoryKey = 'member';
```

`toJson()` now writes `"__type__": "member"`, and the generated mixin still decodes `"user"` and `"person"` to the same class.

### Annotating the class instead

To keep the key out of the class's fields and its `toJson()`, put `@JsonFactoryKey` on the class. The key can be any constant string, and `name`, `mixin` and `oldKeys` work the same way:

```dart
@JsonFactoryKey('user')
@JsonSerializable()
class User {
  ...
  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);
}
```

`toJson()` doesn't write the key, so use the generated `toJsonForFactory` for JSON that will be decoded through the factory:

```dart
user.toJson();                               // {"id": "1", "name": "Ada"}
JsonFactoryMapper.toJsonForFactory(user);    // {"id": "1", "name": "Ada", "__type__": "user"}
```

**JSON without the key can't be decoded through the factory, and the failure only shows up at runtime.** That applies to a direct `toJson()` call and to nested objects, because a parent's generated `toJson()` calls the child's. To include the key for a nested field, add:

```dart
@JsonKey(toJson: JsonFactoryMapper.toJsonForFactory)
final User customer;
```

The parameter of `toJsonForFactory` is non-nullable, so this form doesn't suit a nullable field. If `toJson()` itself needs to include the key, for example for nested lists, use `@jsonFactoryKey()` on a field instead. Both forms can be used in the same package.

```bash
dart run build_runner build
```

This writes `lib/generated/json_factory_runtime.g.dart` with, for each mixin name, the mixin and a static mapper class. For the models above, that is `JsonFactoryMixin` with `JsonFactoryMapper` (holding `User`), and `ApiMixin` with `ApiMapper` (holding `Order`).

The mapper's name is the mixin's with a trailing `Mixin` replaced by `Mapper` (`ApiMixin` → `ApiMapper`). Other names get `Mapper` appended (`Api` → `ApiMapper`). The build stops if a mapper name equals another mixin's name, or if two mixins end up with the same mapper.

## Using the generated code

Call the mapper class directly:

```dart
import 'generated/json_factory_runtime.g.dart';

final user = JsonFactoryMapper.fromKeyedJsonAs<User>(json);
final order = ApiMapper.fromKeyedJsonAs<Order>(json);
```

For code that takes the mixin as an object, `JsonFactoryMapper.instance` is a `const JsonFactoryMixin`.

To get the methods on a class of your own, such as a repository or an API client, mix the mixin in:

```dart
class UserRepository with JsonFactoryMixin {
  Future<Object> load(String id) async => fromKeyedJson(await _fetch(id));

  Future<Map<String, dynamic>> _fetch(String id) async => ...;
}
```

### Methods

All of these are static on the mapper class and instance members of the mixin, except `keyField`, which is static on both.

| Member | Returns | Use when |
|---|---|---|
| `toJsonForFactory(object)` | `Map<String, dynamic>` | Writing `object.toJson()` with its key added. Throws `ArgumentError` if the exact type of `object` isn't registered. |
| `fromKeyedJson(json)` | `Object` | The key is in the JSON (`json['__type__']`). |
| `fromKeyedJsonAs<T>(json)` | `T` | Same, and you know the type you expect. |
| `fromJsonByKey(key, json)` | `Object` | The key comes from somewhere else, such as a URL or a header. |
| `fromJsonAs<T>(key, json)` | `T` | Same, typed. |
| `hasMapperKey(key)` | `bool` | Checking a key before decoding. Old keys count. |
| `mapperKeys` | `Iterable<String>` | Listing the current keys in the mixin. Old keys aren't listed. |
| `keyField` | `String` | Reading the JSON field name, for example `JsonFactoryMapper.keyField`. |

Classes that mix in the mixin don't inherit `keyField`, so read it through the mapper or the mixin (`JsonFactoryMapper.keyField`, `JsonFactoryMixin.keyField`), not through your class (`UserRepository.keyField` doesn't compile).

### Decoding a value whose type isn't known in advance

```dart
final json = jsonDecode(body) as Map<String, dynamic>;
// {"id": "1", "name": "Ada", "__type__": "user"}

switch (JsonFactoryMapper.fromKeyedJson(json)) {
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
    .map(JsonFactoryMapper.fromKeyedJson)
    .toList();
// [User(...), Address(...), User(...)]
```

### Round trip

`toJson()` writes the key, so its output goes straight back through the factory:

```dart
final json = const User(id: '1', name: 'Ada').toJson();
final copy = JsonFactoryMapper.fromKeyedJsonAs<User>(json);
```

The same applies to stored data, such as a cache or a local database, as long as it was written with `toJson()`.

### Key passed separately

When the JSON has no key field, for example because it comes from an endpoint that always returns one type, pass the key yourself:

```dart
final user = JsonFactoryMapper.fromJsonAs<User>('user', json);
```

### Errors

Both of these throw an `ArgumentError`:

- `fromKeyedJson` when the JSON has no string key field.
- `fromJsonByKey` and `fromKeyedJson` when no class in that mixin is registered under the key.

Use `hasMapperKey` to check first when the input isn't trusted:

```dart
final key = json[JsonFactoryMapper.keyField];
if (key is String && JsonFactoryMapper.hasMapperKey(key)) {
  return JsonFactoryMapper.fromJsonByKey(key, json);
}
return null;
```

`fromKeyedJsonAs<T>` and `fromJsonAs<T>` also throw a `TypeError` if the decoded object isn't a `T`.

### Several mixins

Each mixin only knows its own classes. The same key can mean different classes in different mixins:

```dart
JsonFactoryMapper.fromJsonByKey('user', json); // User
ApiMapper.fromJsonByKey('user', json);         // ApiUser
ApiMapper.hasMapperKey('address');             // false
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
  const apiTypeKey = jsonFactoryKey(name: 'kind', mixin: 'ApiMixin');

  @typeKey
  final String factoryKey = 'user';
  ```

## Rules
- A key must be unique within a mixin. If two classes share one, the build stops and the error names both classes. The same key can be used in different mixins.
- Old keys count as keys: within a mixin, each old key must differ from every class's current key and every other old key, or the build stops and the error marks which side is the old key. An old key also can't be empty, repeat in the list, or equal its own class's current key.
- A class can use `@JsonFactoryKey` or a `@jsonFactoryKey` field, not both. `@JsonFactoryKey` needs a non-empty key and a `toJson()` on the class or a superclass, but not `@JsonSerializable`. A concrete `@JsonSerializable` subclass of a class with `@JsonFactoryKey` needs its own `@JsonFactoryKey`, or the build stops.
- `@JsonFactoryKey` goes on the class. On a method, getter or field it stops the build. To have `toJson()` write the key, use a `@jsonFactoryKey()` field instead.
- A class with `@JsonFactoryKey` can't extend a class with a `@jsonFactoryKey` field, or the build stops, because its `toJson()` would write the parent's key. Annotate its own key field instead. The opposite is allowed: a class with a `@jsonFactoryKey` field can extend a class with `@JsonFactoryKey`.
- A `@jsonFactoryKey` member has to be a final, non-`late` instance field, either a `String` initialized with a string literal (`final String factoryKey = 'user';`) or an enum initialized with a constant that has a string `@JsonValue` (`final Kind factoryKey = Kind.user;`). Getters, static fields and values set by a constructor stop the build. Each class can have only one.
- A concrete `@JsonSerializable` subclass of a registered class must annotate its own key field (with `@override` if it has the parent's name), or the build stops. Otherwise its JSON wouldn't decode back to the subclass. Give it its own `fromJson` too, unless the parent's `fromJson` picks the subclass itself. The override triggers the `overridden_fields` lint if you have it enabled; add `// ignore: overridden_fields` on the line directly above `final String`.
- A class with a `@jsonFactoryKey` field must be annotated with `@JsonSerializable`; otherwise the build stops, because the key would never be written to its JSON.
- The class has to be public, non-generic and under `lib/`. It also needs a `fromJson(Map<String, dynamic>)` factory or static method.
- Every generated mixin has the same member names, so a class should mix in only one of them.

## Example

A complete project with models, a custom `build.yaml` and tests is in [`example/`](example/).

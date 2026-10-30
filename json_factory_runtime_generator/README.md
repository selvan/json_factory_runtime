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

```bash
dart run build_runner build
```

This writes `lib/generated/json_factory.g.dart` with one mixin per mixin name:

```dart
import 'generated/json_factory.g.dart';

class ModelFactory with JsonFactoryMapper {}
class ApiFactory with ApiMapper {}

final obj  = ModelFactory().fromKeyedJson(json);          // reads the key from json
final user = ModelFactory().fromKeyedJsonAs<User>(json);  // typed
final byKey = ModelFactory().fromJsonByKey('user', json); // key passed separately
ModelFactory().hasMapperKey('user');                      // true
JsonFactoryMapper.keyField;                               // '__type__'
```

## Configuration (`build.yaml` next to your `pubspec.yaml`)

```yaml
targets:
  $default:
    builders:
      json_factory_runtime_generator:json_factory_aggregator:
        options:
          output: lib/src/factories/json_factory.g.dart   # default: lib/generated/json_factory.g.dart
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
- The annotated getter has to be an instance getter that returns a string literal: `=> 'user'` or `{ return 'user'; }`. Each class can have only one.
- The class must be annotated with `@JsonSerializable`; otherwise the build stops, because the key would never be written to its JSON.
- The class has to be public, non-generic and under `lib/`. It also needs a `fromJson(Map<String, dynamic>)` factory or static method.
- Every generated mixin has the same member names, so a class should mix in only one of them.

## Example

A complete project with models, a custom `build.yaml` and tests is in [`example/`](example/).

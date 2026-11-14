## 0.3.2

- No code changes. Republished so pub.dev can verify the repository link,
  which 0.3.1 pointed at before the matching pubspec was on GitHub.

## 0.3.1

- The build stops when `@JsonFactoryKey` is on a method, getter or field. It was
  ignored, which left the class unregistered.
- The build stops when a class with `@JsonFactoryKey` extends a class with a
  `@jsonFactoryKey` field. Its `toJson()` wrote the parent's key, so the JSON
  decoded back to the parent.

## 0.3.0

- `@JsonFactoryKey('key')` registers a class with no key field. Its `toJson()`
  doesn't write the key, so use `toJsonForFactory`.
- Each mixin and mapper gets `toJsonForFactory(object)`, which adds the key for
  the exact type of `object`. It works for classes using either annotation.
- The aggregator now runs before `json_serializable`, so
  `@JsonKey(toJson: JsonFactoryMapper.toJsonForFactory)` can resolve the mapper.
- The generated file also imports the registered classes' own libraries.
- Requires `json_factory_runtime_annotation` 0.3.0.

## 0.2.0

- **Breaking:** the default mixin is now `JsonFactoryMixin` (was
  `JsonFactoryMapper`). Replace `with JsonFactoryMapper` with
  `with JsonFactoryMixin`, or call the new static class instead.
- Each mixin gets a static mapper class, so no wrapper class is needed:
  `JsonFactoryMapper.fromKeyedJsonAs<User>(json)`. A trailing `Mixin` in the
  mixin name becomes `Mapper` (`ApiMixin` → `ApiMapper`); other names get
  `Mapper` appended. `instance` holds the mixin as a `const` object. The build
  stops if a mapper name clashes with a mixin name or another mapper.
- **Breaking:** `@jsonFactoryKey` goes on a `final String` field initialized
  with a string literal. Replace `String get factoryKey => 'user';` with
  `final String factoryKey = 'user';`. Getters now stop the build.
- `@jsonFactoryKey` is also accepted on a final enum field initialized with a
  constant that has a string `@JsonValue`.
- The build stops when a concrete `@JsonSerializable` subclass of a registered
  class has no `@jsonFactoryKey` field of its own.
- A class with a `@jsonFactoryKey` field but no `fromJson` of its own uses the
  nearest superclass's `fromJson`.
- Works with `build` 4.0.11+ and `source_gen` 4.2.4+ as well, for projects that
  also use builders not yet on `build` 5.
- Requires `json_factory_runtime_annotation` 0.2.0.

## 0.1.0

- Initial release.

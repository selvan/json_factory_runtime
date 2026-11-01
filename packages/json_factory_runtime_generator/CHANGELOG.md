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
- A class with a `@jsonFactoryKey` field but no `fromJson` of its own uses the
  nearest superclass's `fromJson`.
- Works with `build` 4.0.11+ and `source_gen` 4.2.4+ as well, for projects that
  also use builders not yet on `build` 5.
- Requires `json_factory_runtime_annotation` 0.2.0.

## 0.1.0

- Initial release.

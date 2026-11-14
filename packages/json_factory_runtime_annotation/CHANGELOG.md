## 0.3.1

- No code changes. Republished so pub.dev can verify the repository link,
  which 0.3.0 pointed at before the matching pubspec was on GitHub.

## 0.3.0

- Add `@JsonFactoryKey('key')`, which goes on the class instead of a field.

## 0.2.0

- **Breaking:** the default mixin is now `JsonFactoryMixin` (was
  `JsonFactoryMapper`). `JsonFactoryMapper` is now the name of the static
  class generated next to it.
- **Breaking:** goes on a `final String` field instead of a getter:
  `final String factoryKey = 'user';`.
- Can also go on a final enum field. The key is the constant's `@JsonValue`.

## 0.1.0

- Initial release.

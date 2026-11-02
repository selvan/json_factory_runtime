import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:json_factory_runtime_generator/src/aggregator.dart';
import 'package:json_factory_runtime_generator/src/collector.dart';
import 'package:test/test.dart';

const _imports = '''
import 'package:json_annotation/json_annotation.dart';
import 'package:json_factory_runtime_annotation/json_factory_runtime_annotation.dart';
''';

/// A model with a `fromJson` factory and the given key field.
String _model(String className, String field) => '''
$_imports
@JsonSerializable()
class $className {
  $className();
  factory $className.fromJson(Map<String, dynamic> json) => $className();
  $field
}
''';

/// Real sources of the packages the models import, for the in-memory build.
late final Map<String, String> _packageSources;

Future<Map<String, String>> _sourcesOf(List<String> packages) async {
  final sources = <String, String>{};
  for (final package in packages) {
    final root =
        await Isolate.resolvePackageUri(Uri.parse('package:$package/'));
    final dir = Directory.fromUri(root!);
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final path = file.uri.path.substring(dir.uri.path.length);
      sources['$package|lib/$path'] = file.readAsStringSync();
    }
  }
  return sources;
}

Future<TestBuilderResult> _build(
  Map<String, String> sources, {
  JsonFactoryAggregator? aggregator,
}) =>
    testBuilders(
      [JsonFactoryCollector(), aggregator ?? JsonFactoryAggregator()],
      {..._packageSources, ...sources},
      rootPackage: 'a',
    );

final _outputId = makeAssetId('a|$aggregatorOutput');

/// Reads the aggregator output at [path], wherever the test build placed it.
String _generated(TestBuilderResult result, [String path = aggregatorOutput]) {
  final outputId = makeAssetId('a|$path');
  expect(result.outputs, contains(outputId));
  final testing = result.readerWriter.testing;
  final id = testing.assets.firstWhere(
    (id) => id.path.endsWith('a/$path') || id == outputId,
  );
  return testing.readString(id);
}

String _errors(TestBuilderResult result) => result.errors.join('\n');

void main() {
  setUpAll(() async {
    _packageSources = await _sourcesOf(
      ['json_factory_runtime_annotation', 'json_annotation', 'meta'],
    );
  });

  test('generates default and named mixins', () async {
    final result = await _build({
      'a|lib/user.dart':
          _model('User', "@jsonFactoryKey() final String factoryKey = 'user';"),
      'a|lib/order.dart': _model(
        'Order',
        "@jsonFactoryKey(mixin: 'ApiMixin') final String kind = 'order';",
      ),
      'a|lib/plain.dart': 'class Plain {}',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));

    final code = _generated(result);
    expect(code, contains("import 'package:a/order.dart' as i0;"));
    expect(code, contains("import 'package:a/user.dart' as i1;"));
    expect(code, contains('mixin ApiMixin {'));
    expect(code, contains("'order': i0.Order.fromJson"));
    expect(code, contains('mixin JsonFactoryMixin {'));
    expect(code, contains("'user': i1.User.fromJson"));
    expect(code, contains("static const String keyField = '__type__';"));
    expect(code, contains('Object fromKeyedJson(Map<String, dynamic> json)'));
    expect(code, contains('abstract final class JsonFactoryMapper {'));
    expect(
      code,
      contains(
          'static const JsonFactoryMixin instance = _\$JsonFactoryMixin();'),
    );
    expect(code,
        contains('static T fromKeyedJsonAs<T>(Map<String, dynamic> json)'));
    expect(code,
        contains('final class _\$JsonFactoryMixin with JsonFactoryMixin'));
    expect(code, contains('abstract final class ApiMapper {'));
  });

  test('reads a static fromJson', () async {
    final result = await _build({
      'a|lib/item.dart': '''
$_imports
@JsonSerializable()
class Item {
  static Item fromJson(Map<String, dynamic> json) => Item();
  @jsonFactoryKey()
  final String factoryKey = 'item';
}
''',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
    expect(_generated(result), contains("'item': i0.Item.fromJson"));
  });

  test('reads the @JsonValue of an enum constant', () async {
    final result = await _build({
      'a|lib/kind.dart': '''
$_imports
enum Kind {
  @JsonValue('the_item')
  item,
}
''',
      'a|lib/item.dart': '''
$_imports
import 'kind.dart' as k;
@JsonSerializable()
class Item {
  factory Item.fromJson(Map<String, dynamic> json) => Item._();
  Item._();
  @jsonFactoryKey(oldKeys: ['thing'])
  final k.Kind factoryKey = k.Kind.item;
}
''',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
    final code = _generated(result);
    expect(code, contains("'the_item': i0.Item.fromJson"));
    expect(code, contains("'thing': i0.Item.fromJson"));
  });

  group('subclass of a registered class', () {
    const parent = '''
$_imports
@JsonSerializable()
class Parent {
  Parent();
  factory Parent.fromJson(Map<String, dynamic> json) => Parent();
  @jsonFactoryKey()
  final String factoryKey = 'parent';
}
''';

    Future<TestBuilderResult> buildChild(String child) => _build({
          'a|lib/parent.dart': parent,
          'a|lib/child.dart': '''
$_imports
import 'parent.dart';
$child
''',
        });

    test('registers under its own annotated key', () async {
      final result = await buildChild('''
@JsonSerializable()
class Child extends Parent {
  Child();
  factory Child.fromJson(Map<String, dynamic> json) => Child();
  @jsonFactoryKey()
  @override
  final String factoryKey = 'child';
}
''');
      expect(result.succeeded, isTrue, reason: _errors(result));
      final code = _generated(result);
      expect(code, contains("'child': i0.Child.fromJson"));
      expect(code, contains("'parent': i1.Parent.fromJson"));
    });

    test('stops the build when it does not override', () async {
      final result = await buildChild('''
@JsonSerializable()
class Child extends Parent {
  Child();
}
''');
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains('`Child` extends `Parent`'));
    });

    test('stops the build when it overrides without the annotation', () async {
      final result = await buildChild('''
@JsonSerializable()
class Child extends Parent {
  Child();
  @override
  final String factoryKey = 'child';
}
''');
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains('`Child` extends `Parent`'));
    });

    test('stops the build for an indirect subclass', () async {
      final result = await buildChild('''
class Middle extends Parent {
  Middle();
}
@JsonSerializable()
class Child extends Middle {
  Child();
}
''');
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains('`Child` extends `Parent`'));
    });

    test('is allowed when abstract or not @JsonSerializable', () async {
      final result = await buildChild('''
@JsonSerializable()
abstract class Base extends Parent {
  Base();
}
class Plain extends Parent {
  Plain();
}
''');
      expect(result.succeeded, isTrue, reason: _errors(result));
    });
  });

  test('reads a final field', () async {
    final result = await _build({
      'a|lib/item.dart': '''
$_imports
@JsonSerializable()
class Item {
  const Item();
  factory Item.fromJson(Map<String, dynamic> json) => const Item();
  @jsonFactoryKey(oldKeys: ['thing'])
  final String factoryKey = 'item';
}
''',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
    final code = _generated(result);
    expect(code, contains("'item': i0.Item.fromJson"));
    expect(code, contains("'thing': i0.Item.fromJson"));
  });

  test('uses the nearest superclass fromJson when the class has none',
      () async {
    final result = await _build({
      'a|lib/shape.dart': '''
$_imports
import 'circle.dart';
abstract class Shape {
  Shape();
  factory Shape.fromJson(Map<String, dynamic> json) => Circle();
}
''',
      'a|lib/circle.dart': '''
$_imports
import 'shape.dart';
@JsonSerializable()
class Circle extends Shape {
  @jsonFactoryKey(oldKeys: ['round'])
  final String factoryKey = 'circle';
}
''',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
    final code = _generated(result);
    expect(code, contains("import 'package:a/circle.dart' as i0;"));
    expect(code, contains("import 'package:a/shape.dart' as i1;"));
    expect(
      code,
      contains("'circle': i1.Shape.fromJson, // inherited by Circle"),
    );
    expect(
      code,
      contains("'round': i1.Shape.fromJson, "
          '// old key of Circle, inherited by Circle'),
    );
    expect(code, contains("i0.Circle: 'circle'"));
  });

  test('accepts a user-defined annotation constant', () async {
    final result = await _build({
      'a|lib/keys.dart': '''
$_imports
const apiKey = jsonFactoryKey(mixin: 'ApiMixin');
''',
      'a|lib/order.dart': '''
$_imports
import 'keys.dart';
@JsonSerializable()
class Order {
  factory Order.fromJson(Map<String, dynamic> json) => Order._();
  Order._();
  @apiKey
  final String factoryKey = 'order';
}
''',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
    expect(_generated(result), contains('mixin ApiMixin {'));
  });

  test('duplicate key in the same mixin stops the build', () async {
    final result = await _build({
      'a|lib/user.dart':
          _model('User', "@jsonFactoryKey() final String k = 'user';"),
      'a|lib/admin.dart':
          _model('Admin', "@jsonFactoryKey() final String k = 'user';"),
    });
    expect(result.succeeded, isFalse);
    expect(_errors(result), contains("key 'user' in mixin JsonFactoryMixin"));
    expect(_errors(result), contains('Admin (package:a/admin.dart)'));
    expect(_errors(result), contains('User (package:a/user.dart)'));
    expect(result.outputs, isNot(contains(_outputId)));
  });

  group('mixin names clashing with mapper classes stop the build:', () {
    Future<void> expectClash(String m1, String m2, String message) async {
      final result = await _build({
        'a|lib/user.dart': _model(
            'User', "@jsonFactoryKey(mixin: '$m1') final String k = 'u';"),
        'a|lib/admin.dart': _model(
            'Admin', "@jsonFactoryKey(mixin: '$m2') final String k = 'a';"),
      });
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains(message));
      expect(result.outputs, isNot(contains(_outputId)));
    }

    test(
      'a mixin named like another mixin\'s mapper',
      () => expectClash('Api', 'ApiMapper',
          'mixin ApiMapper has the name of the mapper class generated for mixin Api'),
    );
    test(
      'two mixins with the same mapper',
      () => expectClash('Api', 'ApiMixin',
          'mixins Api and ApiMixin both generate mapper class ApiMapper'),
    );
  });

  test('same key in different mixins is allowed', () async {
    final result = await _build({
      'a|lib/user.dart':
          _model('User', "@jsonFactoryKey() final String k = 'user';"),
      'a|lib/admin.dart': _model(
        'Admin',
        "@jsonFactoryKey(mixin: 'AdminMapper') final String k = 'user';",
      ),
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
  });

  group('oldKeys', () {
    test('map to the same class but are not listed in mapperKeys', () async {
      final result = await _build({
        'a|lib/member.dart': _model(
          'Member',
          "@jsonFactoryKey(oldKeys: ['user', 'person']) "
              "final String k = 'member';",
        ),
      });
      expect(result.succeeded, isTrue, reason: _errors(result));

      final code = _generated(result);
      expect(code, contains("'member': i0.Member.fromJson,\n"));
      expect(
        code,
        contains("'person': i0.Member.fromJson, // old key of Member"),
      );
      expect(
        code,
        contains("'user': i0.Member.fromJson, // old key of Member"),
      );
      expect(code, contains("_\$keys = ['member'];"));
    });

    test('conflicting with another class\'s key stops the build', () async {
      final result = await _build({
        'a|lib/user.dart':
            _model('User', "@jsonFactoryKey() final String k = 'user';"),
        'a|lib/member.dart': _model(
          'Member',
          "@jsonFactoryKey(oldKeys: ['user']) final String k = 'member';",
        ),
      });
      expect(result.succeeded, isFalse);
      expect(
        _errors(result),
        contains("key 'user' in mixin JsonFactoryMixin"),
      );
      expect(_errors(result), contains('User (package:a/user.dart)'));
      expect(
        _errors(result),
        contains('Member (package:a/member.dart, old key)'),
      );
      expect(result.outputs, isNot(contains(_outputId)));
    });

    test('conflicting with another class\'s old key stops the build', () async {
      final result = await _build({
        'a|lib/user.dart': _model(
          'User',
          "@jsonFactoryKey(oldKeys: ['person']) final String k = 'user';",
        ),
        'a|lib/member.dart': _model(
          'Member',
          "@jsonFactoryKey(oldKeys: ['person']) final String k = 'member';",
        ),
      });
      expect(result.succeeded, isFalse);
      expect(
        _errors(result),
        contains("key 'person' in mixin JsonFactoryMixin"),
      );
      expect(
        _errors(result),
        contains('User (package:a/user.dart, old key)'),
      );
      expect(
        _errors(result),
        contains('Member (package:a/member.dart, old key)'),
      );
    });

    test('the same old key in different mixins is allowed', () async {
      final result = await _build({
        'a|lib/user.dart': _model(
          'User',
          "@jsonFactoryKey(oldKeys: ['person']) final String k = 'user';",
        ),
        'a|lib/member.dart': _model(
          'Member',
          "@jsonFactoryKey(mixin: 'ApiMixin', oldKeys: ['person']) "
              "final String k = 'member';",
        ),
      });
      expect(result.succeeded, isTrue, reason: _errors(result));
    });
  });

  group('key_field', () {
    JsonFactoryAggregator configured(String field) =>
        JsonFactoryAggregator.fromOptions(
          BuilderOptions({'key_field': field}),
        );

    test('is written into the mixin', () async {
      final result = await _build(
        {
          'a|lib/user.dart': _model(
            'User',
            "@jsonFactoryKey(name: 'kind') final String k = 'user';",
          ),
        },
        aggregator: configured('kind'),
      );
      expect(result.succeeded, isTrue, reason: _errors(result));
      expect(
        _generated(result),
        contains("static const String keyField = 'kind';"),
      );
    });

    test('mismatch with the annotation name stops the build', () async {
      final result = await _build(
        {
          'a|lib/user.dart':
              _model('User', "@jsonFactoryKey() final String k = 'user';"),
        },
        aggregator: configured('kind'),
      );
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains("must match key_field 'kind'"));
      expect(
        _errors(result),
        contains("User (package:a/user.dart) writes '__type__'"),
      );
    });
  });

  group('@JsonFactoryKey on a class', () {
    /// A model with `fromJson` and `toJson`, under the given annotation.
    String classModel(String className, String annotation) => '''
$_imports
$annotation
@JsonSerializable()
class $className {
  $className();
  factory $className.fromJson(Map<String, dynamic> json) => $className();
  Map<String, dynamic> toJson() => {};
}
''';

    test('registers the class and adds it to toJsonForFactory', () async {
      final result = await _build({
        'a|lib/user.dart': classModel('User', "@JsonFactoryKey('user')"),
      });
      expect(result.succeeded, isTrue, reason: _errors(result));

      final code = _generated(result);
      expect(code, contains("import 'package:a/user.dart' as i0;"));
      expect(code, contains("'user': i0.User.fromJson"));
      expect(code, contains("i0.User: 'user'"));
      expect(code, contains('Map<String, dynamic> toJsonForFactory(Object'));
      expect(code, contains('static Map<String, dynamic> toJsonForFactory('));
    });

    test('reads mixin and oldKeys', () async {
      final result = await _build({
        'a|lib/user.dart': classModel(
          'User',
          "@JsonFactoryKey('member', mixin: 'ApiMixin', oldKeys: ['user'])",
        ),
      });
      expect(result.succeeded, isTrue, reason: _errors(result));

      final code = _generated(result);
      expect(code, contains('mixin ApiMixin {'));
      expect(code, contains("'user': i0.User.fromJson, // old key of User"));
      expect(code, contains("i0.User: 'member'"));
      expect(code, isNot(contains("i0.User: 'user'")));
    });

    test('accepts a named constant as the key', () async {
      final result = await _build({
        'a|lib/user.dart': '''
$_imports
const userKey = 'user';

@JsonFactoryKey(userKey)
class User {
  User();
  factory User.fromJson(Map<String, dynamic> json) => User();
  Map<String, dynamic> toJson() => {};
}
''',
      });
      expect(result.succeeded, isTrue, reason: _errors(result));
      expect(_generated(result), contains("i0.User: 'user'"));
    });

    test('accepts a toJson inherited from a superclass', () async {
      final result = await _build({
        'a|lib/user.dart': '''
$_imports
abstract class Base {
  Map<String, dynamic> toJson() => {};
}

@JsonFactoryKey('user')
class User extends Base {
  User();
  factory User.fromJson(Map<String, dynamic> json) => User();
}
''',
      });
      expect(result.succeeded, isTrue, reason: _errors(result));
    });

    test('field-annotated classes are in toJsonForFactory too', () async {
      final result = await _build({
        'a|lib/user.dart':
            _model('User', "@jsonFactoryKey() final String k = 'user';"),
      });
      expect(result.succeeded, isTrue, reason: _errors(result));
      expect(_generated(result), contains("i0.User: 'user'"));
    });

    test('uses the configured key_field', () async {
      final result = await _build(
        {
          'a|lib/user.dart':
              classModel('User', "@JsonFactoryKey('user', name: 'kind')"),
        },
        aggregator: JsonFactoryAggregator(keyField: 'kind'),
      );
      expect(result.succeeded, isTrue, reason: _errors(result));
      expect(
        _generated(result),
        contains("static const String keyField = 'kind';"),
      );
    });

    test('a name that differs from key_field stops the build', () async {
      final result = await _build({
        'a|lib/user.dart':
            classModel('User', "@JsonFactoryKey('user', name: 'kind')"),
      });
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains('must match key_field'));
    });

    test('a key clash with a field-annotated class stops the build', () async {
      final result = await _build({
        'a|lib/user.dart': classModel('User', "@JsonFactoryKey('same')"),
        'a|lib/other.dart':
            _model('Other', "@jsonFactoryKey() final String k = 'same';"),
      });
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains("key 'same'"));
    });

    Future<void> expectError(String body, String message) async {
      final result = await _build({'a|lib/bad.dart': '$_imports\n$body'});
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains(message));
    }

    test('both annotation forms stop the build', () => expectError('''
@JsonFactoryKey('bad')
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  Map<String, dynamic> toJson() => {};
  @jsonFactoryKey()
  final String k = 'bad';
}
''', 'both @JsonFactoryKey and a @jsonFactoryKey field'));

    test('an empty key stops the build', () => expectError('''
@JsonFactoryKey('')
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  Map<String, dynamic> toJson() => {};
}
''', 'must not be empty'));

    test('a missing toJson stops the build', () => expectError('''
@JsonFactoryKey('bad')
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
}
''', 'no `toJson()`'));

    test('a missing fromJson stops the build', () => expectError('''
@JsonFactoryKey('bad')
class Bad {
  Map<String, dynamic> toJson() => {};
}
''', 'no `fromJson'));

    test('a private class stops the build', () => expectError('''
@JsonFactoryKey('bad')
class _Bad {
  factory _Bad.fromJson(Map<String, dynamic> json) => _Bad._();
  _Bad._();
  Map<String, dynamic> toJson() => {};
}
''', 'private class'));

    test('a generic class stops the build', () => expectError('''
@JsonFactoryKey('bad')
class Bad<T> {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  Map<String, dynamic> toJson() => {};
}
''', 'generic class'));

    test('a serializable subclass needs its own key', () => expectError('''
@JsonFactoryKey('base')
class Base {
  Base();
  factory Base.fromJson(Map<String, dynamic> json) => Base();
  Map<String, dynamic> toJson() => {};
}

@JsonSerializable()
class Bad extends Base {}
''', 'which has @JsonFactoryKey'));

    group('on a member stops the build:', () {
      String model(String member) => '''
@JsonSerializable()
class Bad {
  Bad();
  factory Bad.fromJson(Map<String, dynamic> json) => Bad();
  $member
}
''';

      test(
        'method',
        () => expectError(
          model("@JsonFactoryKey('bad') Map<String, dynamic> toJson() => {};"),
          'not the member `toJson`',
        ),
      );
      test(
        'getter',
        () => expectError(
          model("@JsonFactoryKey('bad') String get k => 'bad';"),
          'not the member `k`',
        ),
      );
      test(
        'field',
        () => expectError(
          model("@JsonFactoryKey('bad') final String k = 'bad';"),
          'not the member `k`',
        ),
      );
    });

    test('a subclass of a class with a key field stops the build', () =>
        expectError('''
@JsonSerializable()
class Base {
  Base();
  factory Base.fromJson(Map<String, dynamic> json) => Base();
  Map<String, dynamic> toJson() => {};
  @jsonFactoryKey()
  final String k = 'base';
}

@JsonFactoryKey('bad')
@JsonSerializable()
class Bad extends Base {
  Bad();
  factory Bad.fromJson(Map<String, dynamic> json) => Bad();
}
''', "would write `Base`'s key"));

    test('a subclass with a key field of a @JsonFactoryKey class builds',
        () async {
      final result = await _build({
        'a|lib/child.dart': '''
$_imports
@JsonFactoryKey('base')
@JsonSerializable()
class Base {
  Base();
  factory Base.fromJson(Map<String, dynamic> json) => Base();
  Map<String, dynamic> toJson() => {};
}

@JsonSerializable()
class Child extends Base {
  Child();
  factory Child.fromJson(Map<String, dynamic> json) => Child();
  @jsonFactoryKey()
  final String k = 'child';
}
''',
      });
      expect(result.succeeded, isTrue, reason: _errors(result));
      expect(_generated(result), contains("'child': i0.Child.fromJson"));
    });
  });

  group('invalid usage is an error:', () {
    Future<void> expectError(String body, String message) async {
      final result = await _build({'a|lib/bad.dart': '$_imports\n$body'});
      expect(result.succeeded, isFalse);
      expect(_errors(result), contains(message));
    }

    test('class without @JsonSerializable', () => expectError('''
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  final String k = 'bad';
}
''', 'is not annotated with @JsonSerializable'));

    test('missing fromJson', () => expectError('''
@JsonSerializable()
class Bad {
  @jsonFactoryKey()
  final String k = 'bad';
}
''', 'no `fromJson'));

    test('fromJson only on a private superclass', () => expectError('''
abstract class _Base {
  _Base();
  factory _Base.fromJson(Map<String, dynamic> json) => Bad();
}
@JsonSerializable()
class Bad extends _Base {
  @jsonFactoryKey()
  final String k = 'bad';
}
''', 'private superclass `_Base`'));

    test('non-literal key', () => expectError('''
const name = 'bad';
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  final String k = name;
}
''', 'non-empty string literal'));

    Future<void> expectFieldError(String field, String message) => expectError(
          '''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  $field
}
''',
          message,
        );

    group('enum field', () {
      Future<void> expectEnumError(String enumBody, String field) =>
          expectError(
            '''
enum Kind { $enumBody }
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  $field
}
''',
            'annotated with a non-empty string @JsonValue',
          );

      test(
        'constant without @JsonValue',
        () => expectEnumError('a', 'final Kind k = Kind.a;'),
      );
      test(
        'constant with an int @JsonValue',
        () => expectEnumError('@JsonValue(1) a', 'final Kind k = Kind.a;'),
      );
      test(
        'constant with an empty @JsonValue',
        () => expectEnumError("@JsonValue('') a", 'final Kind k = Kind.a;'),
      );
      test(
        'initializer that is not a constant',
        () => expectEnumError(
          "@JsonValue('a') a",
          'final Kind k = Kind.values.first;',
        ),
      );
    });

    test('annotation on a getter', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  String get k => 'bad';
}
''', 'must be on a final String field, not the getter'));

    test(
      'field that is not a String',
      () => expectFieldError("final Object k = 'bad';", 'must be a `String`'),
    );
    test(
      'nullable String field',
      () => expectFieldError("final String? k = 'bad';", 'must be a `String`'),
    );
    test(
      'non-final field',
      () => expectFieldError("String k = 'bad';", 'must be final and not late'),
    );
    test(
      'late final field',
      () => expectFieldError(
        "late final String k = 'bad';",
        'must be final and not late',
      ),
    );
    test(
      'static field',
      () => expectFieldError(
        "static const String k = 'bad';",
        'must not be static',
      ),
    );
    test(
      'final field without an initializer',
      () => expectFieldError('final String k;', 'non-empty string literal'),
    );
    test(
      'final field with a non-literal initializer',
      () => expectFieldError(
        "final String k = 'b' + 'ad';",
        'non-empty string literal',
      ),
    );

    test('two key fields', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  final String a = 'a';
  @jsonFactoryKey()
  final String b = 'b';
}
''', 'more than one @jsonFactoryKey'));

    test('invalid mixin name', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey(mixin: 'not valid')
  final String k = 'bad';
}
''', 'not a valid public'));

    test('empty old key', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey(oldKeys: [''])
  final String k = 'bad';
}
''', 'must be non-empty strings'));

    test('old key equal to the key', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey(oldKeys: ['bad'])
  final String k = 'bad';
}
''', "'bad' is both the key and an old key of `Bad`"));

    test('old key listed twice', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey(oldKeys: ['old', 'old'])
  final String k = 'bad';
}
''', "lists 'old' twice"));
  });

  test('output option moves the generated file', () async {
    const output = 'lib/src/factories/mappers.g.dart';
    final result = await _build(
      {
        'a|lib/user.dart':
            _model('User', "@jsonFactoryKey() final String k = 'user';"),
      },
      aggregator: JsonFactoryAggregator.fromOptions(
        const BuilderOptions({'output': output}),
      ),
    );
    expect(result.succeeded, isTrue, reason: _errors(result));
    expect(result.outputs, isNot(contains(_outputId)));
    expect(_generated(result, output), contains('mixin JsonFactoryMixin {'));
  });

  test('options are validated', () {
    for (final options in [
      {'output': 'test/mappers.g.dart'},
      {'output': 'lib/mappers.json'},
      {'output': 'lib/../mappers.g.dart'},
      {'output': '/lib/mappers.g.dart'},
      {'output': 'lib//mappers.g.dart'},
      {'output': 42},
      {'key_field': ''},
      {'key_field': 42},
    ]) {
      expect(
        () => JsonFactoryAggregator.fromOptions(BuilderOptions(options)),
        throwsArgumentError,
        reason: '$options',
      );
    }
  });
}

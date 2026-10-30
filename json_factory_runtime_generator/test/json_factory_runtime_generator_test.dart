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

/// A model with a `fromJson` factory and the given key getter.
String _model(String className, String getter) => '''
$_imports
@JsonSerializable()
class $className {
  $className();
  factory $className.fromJson(Map<String, dynamic> json) => $className();
  $getter
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
          _model('User', "@jsonFactoryKey() String get factoryKey => 'user';"),
      'a|lib/order.dart': _model(
        'Order',
        "@jsonFactoryKey(mixin: 'ApiMapper') String get kind => 'order';",
      ),
      'a|lib/plain.dart': 'class Plain {}',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));

    final code = _generated(result);
    expect(code, contains("import 'package:a/order.dart' as i0;"));
    expect(code, contains("import 'package:a/user.dart' as i1;"));
    expect(code, contains('mixin ApiMapper {'));
    expect(code, contains("'order': i0.Order.fromJson"));
    expect(code, contains('mixin JsonFactoryMapper {'));
    expect(code, contains("'user': i1.User.fromJson"));
    expect(code, contains("static const String keyField = '__type__';"));
    expect(code, contains('Object fromKeyedJson(Map<String, dynamic> json)'));
  });

  test('reads a block-bodied getter and a static fromJson', () async {
    final result = await _build({
      'a|lib/item.dart': '''
$_imports
@JsonSerializable()
class Item {
  static Item fromJson(Map<String, dynamic> json) => Item();
  @jsonFactoryKey()
  String get factoryKey {
    return 'item';
  }
}
''',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
    expect(_generated(result), contains("'item': i0.Item.fromJson"));
  });

  test('accepts a user-defined annotation constant', () async {
    final result = await _build({
      'a|lib/keys.dart': '''
$_imports
const apiKey = jsonFactoryKey(mixin: 'ApiMapper');
''',
      'a|lib/order.dart': '''
$_imports
import 'keys.dart';
@JsonSerializable()
class Order {
  factory Order.fromJson(Map<String, dynamic> json) => Order._();
  Order._();
  @apiKey
  String get factoryKey => 'order';
}
''',
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
    expect(_generated(result), contains('mixin ApiMapper {'));
  });

  test('duplicate key in the same mixin stops the build', () async {
    final result = await _build({
      'a|lib/user.dart':
          _model('User', "@jsonFactoryKey() String get k => 'user';"),
      'a|lib/admin.dart':
          _model('Admin', "@jsonFactoryKey() String get k => 'user';"),
    });
    expect(result.succeeded, isFalse);
    expect(_errors(result), contains("key 'user' in mixin JsonFactoryMapper"));
    expect(_errors(result), contains('Admin (package:a/admin.dart)'));
    expect(_errors(result), contains('User (package:a/user.dart)'));
    expect(result.outputs, isNot(contains(_outputId)));
  });

  test('same key in different mixins is allowed', () async {
    final result = await _build({
      'a|lib/user.dart':
          _model('User', "@jsonFactoryKey() String get k => 'user';"),
      'a|lib/admin.dart': _model(
        'Admin',
        "@jsonFactoryKey(mixin: 'AdminMapper') String get k => 'user';",
      ),
    });
    expect(result.succeeded, isTrue, reason: _errors(result));
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
            "@jsonFactoryKey(name: 'kind') String get k => 'user';",
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
              _model('User', "@jsonFactoryKey() String get k => 'user';"),
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
  String get k => 'bad';
}
''', 'is not annotated with @JsonSerializable'));

    test('missing fromJson', () => expectError('''
@JsonSerializable()
class Bad {
  @jsonFactoryKey()
  String get k => 'bad';
}
''', 'no `fromJson'));

    test('non-literal key', () => expectError('''
const name = 'bad';
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  String get k => name;
}
''', 'must return a non-empty string literal'));

    test('annotation on a field', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  final String k = 'bad';
}
''', 'must be on a getter'));

    test('two key getters', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey()
  String get a => 'a';
  @jsonFactoryKey()
  String get b => 'b';
}
''', 'more than one @jsonFactoryKey'));

    test('invalid mixin name', () => expectError('''
@JsonSerializable()
class Bad {
  factory Bad.fromJson(Map<String, dynamic> json) => Bad._();
  Bad._();
  @jsonFactoryKey(mixin: 'not valid')
  String get k => 'bad';
}
''', 'not a valid public'));
  });

  test('output option moves the generated file', () async {
    const output = 'lib/src/factories/mappers.g.dart';
    final result = await _build(
      {
        'a|lib/user.dart':
            _model('User', "@jsonFactoryKey() String get k => 'user';"),
      },
      aggregator: JsonFactoryAggregator.fromOptions(
        const BuilderOptions({'output': output}),
      ),
    );
    expect(result.succeeded, isTrue, reason: _errors(result));
    expect(result.outputs, isNot(contains(_outputId)));
    expect(_generated(result, output), contains('mixin JsonFactoryMapper {'));
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

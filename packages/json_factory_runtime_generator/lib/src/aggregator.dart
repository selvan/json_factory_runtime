import 'dart:convert';

import 'package:build/build.dart';
import 'package:dart_style/dart_style.dart';
import 'package:glob/glob.dart';
import 'package:json_factory_runtime_annotation/json_factory_runtime_annotation.dart';

import 'collector.dart';
import 'entry.dart';

/// Default path of the generated file, relative to the package root.
///
/// Override it with the `output` builder option in `build.yaml`.
const aggregatorOutput = 'lib/generated/json_factory_runtime.g.dart';

/// Thrown when two classes register the same key (current or old) in the same
/// mixin, or a `@jsonFactoryKey` name does not match the configured
/// `key_field`.
class JsonFactoryConflictException implements Exception {
  final String message;
  JsonFactoryConflictException(this.message);

  @override
  String toString() => 'JsonFactoryConflictException: $message';
}

class JsonFactoryAggregator implements Builder {
  /// Path of the generated file, relative to the package root.
  final String output;

  /// JSON field holding the runtime key, read by `fromKeyedJson`.
  ///
  /// Every `@jsonFactoryKey` must use this as its `name`.
  final String keyField;

  JsonFactoryAggregator({
    this.output = aggregatorOutput,
    this.keyField = defaultJsonFactoryKeyField,
  }) {
    if (keyField.isEmpty) {
      throw ArgumentError.value(
        keyField,
        'key_field',
        'json_factory_aggregator `key_field` must not be empty',
      );
    }
    if (!output.startsWith('lib/') ||
        !output.endsWith('.dart') ||
        output.contains('\\') ||
        output.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      throw ArgumentError.value(
        output,
        'output',
        'json_factory_aggregator `output` must be a relative .dart path under '
            'lib/, for example lib/generated/json_factory_runtime.g.dart',
      );
    }
  }

  /// Reads the `output` and `key_field` options from `build.yaml`.
  factory JsonFactoryAggregator.fromOptions(BuilderOptions options) =>
      JsonFactoryAggregator(
        output: _stringOption(options, 'output') ?? aggregatorOutput,
        keyField:
            _stringOption(options, 'key_field') ?? defaultJsonFactoryKeyField,
      );

  static String? _stringOption(BuilderOptions options, String name) {
    final value = options.config[name];
    if (value == null || value is String) return value as String?;
    throw ArgumentError.value(
      value,
      name,
      'json_factory_aggregator `$name` must be a string',
    );
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        r'$lib$': [output.substring('lib/'.length)],
      };

  static final _inputs = Glob('lib/**$collectorExtension');

  @override
  Future<void> build(BuildStep buildStep) async {
    final entries = <JsonFactoryEntry>[];
    await for (final id in buildStep.findAssets(_inputs)) {
      final list = jsonDecode(await buildStep.readAsString(id)) as List;
      entries.addAll(
        list.map((e) => JsonFactoryEntry.fromJson(e as Map<String, dynamic>)),
      );
    }
    if (entries.isEmpty) return;

    final byMixin = _groupAndCheck(entries);
    final code = generate(byMixin, keyField: keyField);
    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, output),
      code,
    );
  }

  /// Groups entries by mixin and key, current and old keys alike, throwing on
  /// any duplicate key within a mixin so the build stops before anything is
  /// written.
  Map<String, Map<String, Registration>> _groupAndCheck(
    List<JsonFactoryEntry> entries,
  ) {
    final byMixin = <String, Map<String, Registration>>{};
    final conflicts = <String>[];
    final wrongField = [
      for (final e in entries)
        if (e.field != keyField) "  ${e.location} writes '${e.field}'",
    ];
    if (wrongField.isNotEmpty) {
      throw JsonFactoryConflictException(
        "@jsonFactoryKey name must match key_field '$keyField', "
        'generation stopped:\n'
        '${wrongField.join('\n')}\n'
        "Use `@jsonFactoryKey(name: '$keyField')`, or change `key_field` "
        'in build.yaml.',
      );
    }
    for (final entry in entries) {
      final keys = byMixin.putIfAbsent(entry.mixin, () => {});
      final registrations = [
        (key: entry.key, entry: entry, isOld: false),
        for (final oldKey in entry.oldKeys)
          (key: oldKey, entry: entry, isOld: true),
      ];
      for (final registration in registrations) {
        final existing = keys[registration.key];
        if (existing != null) {
          conflicts.add(
            "  key '${registration.key}' in mixin ${entry.mixin}: "
            '${_describe(existing)} and ${_describe(registration)}',
          );
          continue;
        }
        keys[registration.key] = registration;
      }
    }
    final clashes = <String>[];
    final mapperOf = <String, String>{};
    for (final mixin in byMixin.keys.toList()..sort()) {
      final mapper = mapperName(mixin);
      if (byMixin.containsKey(mapper)) {
        clashes.add('  mixin $mapper has the name of the mapper class '
            'generated for mixin $mixin');
      }
      if (mapperOf[mapper] case final other?) {
        clashes.add('  mixins $other and $mixin both generate mapper class '
            '$mapper');
      }
      mapperOf[mapper] = mixin;
    }
    if (clashes.isNotEmpty) {
      throw JsonFactoryConflictException(
        'Mixin names clash with generated mapper classes, generation '
        'stopped:\n'
        '${clashes.join('\n')}\n'
        'Rename one of the mixins with `@jsonFactoryKey(mixin: ...)`.',
      );
    }
    if (conflicts.isNotEmpty) {
      throw JsonFactoryConflictException(
        'Duplicate @jsonFactoryKey keys, generation stopped:\n'
        '${conflicts.join('\n')}\n'
        'Use a unique key or old key, or register one of the classes in a '
        'different mixin with `@jsonFactoryKey(mixin: ...)`.',
      );
    }
    return byMixin;
  }

  static String _describe(Registration r) => r.isOld
      ? '${r.entry.className} (${r.entry.importUri}, old key)'
      : r.entry.location;
}

/// One key in a mixin: the class it builds and whether it is an old key.
typedef Registration = ({String key, JsonFactoryEntry entry, bool isOld});

/// Renders the generated library. Public for tests.
String generate(
  Map<String, Map<String, Registration>> byMixin, {
  String keyField = defaultJsonFactoryKeyField,
}) {
  final uris = {
    for (final keys in byMixin.values)
      for (final r in keys.values) r.entry.fromJsonUri,
  }.toList()
    ..sort();
  final prefix = {for (var i = 0; i < uris.length; i++) uris[i]: 'i$i'};

  final out = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
    ..writeln('// Generated by json_factory_runtime_generator.')
    ..writeln()
    ..writeln('// ignore_for_file: type=lint')
    ..writeln();
  for (final uri in uris) {
    out.writeln("import '$uri' as ${prefix[uri]};");
  }

  for (final mixin in byMixin.keys.toList()..sort()) {
    final keys = byMixin[mixin]!;
    out
      ..writeln()
      ..writeln('/// JSON factory for classes registered with '
          '`@jsonFactoryKey(mixin: \'$mixin\')`.')
      ..writeln('mixin $mixin {')
      ..writeln('  /// JSON field that holds the runtime key.')
      ..writeln('  static const String keyField = ${_literal(keyField)};')
      ..writeln()
      ..writeln(
          '  static const Map<String, Object Function(Map<String, dynamic>)> '
          '_\$factories = {');
    for (final key in keys.keys.toList()..sort()) {
      final r = keys[key]!;
      final e = r.entry;
      final notes = [
        if (r.isOld) 'old key of ${e.className}',
        if (e.fromJsonClass != e.className) 'inherited by ${e.className}',
      ];
      out.writeln(
          '    ${_literal(key)}: ${prefix[e.fromJsonUri]}.${e.fromJsonClass}.fromJson,'
          '${notes.isEmpty ? '' : ' // ${notes.join(', ')}'}');
    }
    final currentKeys = [
      for (final r in keys.values)
        if (!r.isOld) r.key,
    ]..sort();
    out
      ..writeln('  };')
      ..writeln()
      ..writeln('  static const List<String> _\$keys = [')
      ..writeln([for (final k in currentKeys) '    ${_literal(k)},'].join('\n'))
      ..writeln('  ];')
      ..writeln()
      ..writeln('  /// Builds the class registered under [key] from [json].')
      ..writeln('  ///')
      ..writeln(
          '  /// Throws [ArgumentError] if no class is registered under [key].')
      ..writeln(
          '  Object fromJsonByKey(String key, Map<String, dynamic> json) {')
      ..writeln('    final factory = _\$factories[key];')
      ..writeln('    if (factory == null) {')
      ..writeln(
          "      throw ArgumentError.value(key, 'key', 'No @jsonFactoryKey class registered in $mixin');")
      ..writeln('    }')
      ..writeln('    return factory(json);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  /// Typed variant of [fromJsonByKey].')
      ..writeln('  T fromJsonAs<T>(String key, Map<String, dynamic> json) =>')
      ..writeln('      fromJsonByKey(key, json) as T;')
      ..writeln()
      ..writeln(
          '  /// Builds the class named by the [keyField] entry of [json].')
      ..writeln('  ///')
      ..writeln(
          '  /// Throws [ArgumentError] if [json] has no string [keyField] '
          'or no class is registered under it.')
      ..writeln('  Object fromKeyedJson(Map<String, dynamic> json) {')
      ..writeln('    final key = json[keyField];')
      ..writeln('    if (key is! String) {')
      ..writeln(
          "      throw ArgumentError.value(json, 'json', 'Missing string \$keyField');")
      ..writeln('    }')
      ..writeln('    return fromJsonByKey(key, json);')
      ..writeln('  }')
      ..writeln()
      ..writeln('  /// Typed variant of [fromKeyedJson].')
      ..writeln('  T fromKeyedJsonAs<T>(Map<String, dynamic> json) =>')
      ..writeln('      fromKeyedJson(json) as T;')
      ..writeln()
      ..writeln(
          '  /// Whether a class is registered under [key], current or old.')
      ..writeln(
          '  bool hasMapperKey(String key) => _\$factories.containsKey(key);')
      ..writeln()
      ..writeln('  /// All current keys.')
      ..writeln('  ///')
      ..writeln('  /// Old keys are accepted by [hasMapperKey] and the `from*` '
          'methods but not listed.')
      ..writeln('  Iterable<String> get mapperKeys => _\$keys;')
      ..writeln('}');

    final mapper = mapperName(mixin);
    final impl = '_\$$mixin';
    out
      ..writeln()
      ..writeln('/// Static access to [$mixin], for example '
          '`$mapper.fromKeyedJson(json)`.')
      ..writeln('abstract final class $mapper {')
      ..writeln('  /// [$mixin] as an object, for code that takes one.')
      ..writeln('  static const $mixin instance = $impl();')
      ..writeln()
      ..writeln('  /// See [$mixin.keyField].')
      ..writeln('  static const String keyField = $mixin.keyField;')
      ..writeln()
      ..writeln('  /// See [$mixin.fromJsonByKey].')
      ..writeln(
          '  static Object fromJsonByKey(String key, Map<String, dynamic> json) =>')
      ..writeln('      instance.fromJsonByKey(key, json);')
      ..writeln()
      ..writeln('  /// See [$mixin.fromJsonAs].')
      ..writeln(
          '  static T fromJsonAs<T>(String key, Map<String, dynamic> json) =>')
      ..writeln('      instance.fromJsonAs<T>(key, json);')
      ..writeln()
      ..writeln('  /// See [$mixin.fromKeyedJson].')
      ..writeln('  static Object fromKeyedJson(Map<String, dynamic> json) =>')
      ..writeln('      instance.fromKeyedJson(json);')
      ..writeln()
      ..writeln('  /// See [$mixin.fromKeyedJsonAs].')
      ..writeln('  static T fromKeyedJsonAs<T>(Map<String, dynamic> json) =>')
      ..writeln('      instance.fromKeyedJsonAs<T>(json);')
      ..writeln()
      ..writeln('  /// See [$mixin.hasMapperKey].')
      ..writeln(
          '  static bool hasMapperKey(String key) => instance.hasMapperKey(key);')
      ..writeln()
      ..writeln('  /// See [$mixin.mapperKeys].')
      ..writeln(
          '  static Iterable<String> get mapperKeys => instance.mapperKeys;')
      ..writeln('}')
      ..writeln()
      ..writeln('final class $impl with $mixin {')
      ..writeln('  const $impl();')
      ..writeln('}');
  }

  return DartFormatter(languageVersion: DartFormatter.latestLanguageVersion)
      .format(out.toString());
}

/// Name of the generated static class for [mixin]: a trailing `Mixin`
/// becomes `Mapper`, any other name gets `Mapper` appended.
String mapperName(String mixin) => mixin.endsWith('Mixin') && mixin != 'Mixin'
    ? '${mixin.substring(0, mixin.length - 'Mixin'.length)}Mapper'
    : '${mixin}Mapper';

/// Single-quoted Dart string literal for [value].
String _literal(String value) {
  final json = jsonEncode(value);
  final escaped = json
      .substring(1, json.length - 1)
      .replaceAll(r'\"', '"')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$');
  return "'$escaped'";
}

import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:json_factory_runtime_annotation/json_factory_runtime_annotation.dart';
import 'package:source_gen/source_gen.dart';

import 'entry.dart';

const _keyChecker = TypeChecker.typeNamed(
  jsonFactoryKey,
  inPackage: 'json_factory_runtime_annotation',
);

const _jsonSerializableChecker = TypeChecker.typeNamedLiterally(
  'JsonSerializable',
  inPackage: 'json_annotation',
);

final _identifier = RegExp(r'^[A-Za-z$][A-Za-z0-9_$]*$');

/// Extension of the intermediate files written by [JsonFactoryCollector].
const collectorExtension = '.json_factory.json';

class JsonFactoryCollector implements Builder {
  @override
  final buildExtensions = const {
    '.dart': [collectorExtension],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    // Cheap text check first so libraries without any annotation are never
    // resolved. The annotation may be a user-defined constant, so this can't
    // look for the class name.
    final source = await buildStep.readAsString(buildStep.inputId);
    if (!source.contains('@')) return;
    if (!await buildStep.resolver.isLibrary(buildStep.inputId)) return;

    final library = await buildStep.inputLibrary;
    final entries = <JsonFactoryEntry>[];
    for (final element in library.classes) {
      final entry = await _entryFor(element, library, buildStep);
      if (entry != null) entries.add(entry);
    }
    if (entries.isEmpty) return;

    await buildStep.writeAsString(
      buildStep.inputId.changeExtension(collectorExtension),
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }

  /// Returns the registration for [element], or `null` when it has no
  /// `@jsonFactoryKey` getter.
  Future<JsonFactoryEntry?> _entryFor(
    ClassElement element,
    LibraryElement library,
    BuildStep buildStep,
  ) async {
    for (final field in element.fields) {
      if (field.isOriginDeclaration && _keyChecker.hasAnnotationOf(field)) {
        throw InvalidGenerationSource(
          '@jsonFactoryKey must be on a getter, not the field `${field.name}`.',
          element: field,
          todo: "Use `String get ${field.name} => 'your_key';`",
        );
      }
    }
    for (final method in element.methods) {
      if (_keyChecker.hasAnnotationOf(method)) {
        throw InvalidGenerationSource(
          '@jsonFactoryKey must be on a getter, not the method '
          '`${method.name}`.',
          element: method,
        );
      }
    }

    final annotated = [
      for (final getter in element.getters)
        if (getter.isOriginDeclaration)
          if (_keyChecker.firstAnnotationOf(getter) case final annotation?)
            (getter, ConstantReader(annotation)),
    ];
    if (annotated.isEmpty) return null;

    final className = element.name;
    if (annotated.length > 1) {
      throw InvalidGenerationSource(
        '`$className` has more than one @jsonFactoryKey getter.',
        element: annotated[1].$1,
      );
    }
    final (getter, annotation) = annotated.single;

    // The key only reaches the JSON through json_serializable's toJson.
    if (!_jsonSerializableChecker.hasAnnotationOf(element)) {
      throw InvalidGenerationSource(
        '`$className` has a @jsonFactoryKey getter but is not annotated with '
        '@JsonSerializable, so the key would never be written to its JSON.',
        element: element,
        todo: 'Add @JsonSerializable() to `$className`.',
      );
    }

    if (className == null || element.isPrivate) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey cannot be used in private class `$className`: '
        'the generated factory has to import it.',
        element: element,
      );
    }
    if (element.typeParameters.isNotEmpty) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey cannot be used in generic class `$className`: '
        'its fromJson needs extra arguments for the type parameters.',
        element: element,
      );
    }
    if (getter.isStatic) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey getter `$className.${getter.name}` must not be '
        'static: json_serializable only writes instance members.',
        element: getter,
      );
    }
    _checkFromJson(element, className);

    final key = await _keyLiteral(getter, className, buildStep);
    final field = annotation.read('name').stringValue;
    if (field.isEmpty) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey name on `$className` must not be empty.',
        element: getter,
      );
    }

    final mixinReader = annotation.read('mixin');
    final mixin = mixinReader.isNull
        ? jsonFactoryKey.defaultMixin
        : mixinReader.stringValue;
    if (!_identifier.hasMatch(mixin)) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey mixin `$mixin` on `$className` is not a valid public '
        'Dart identifier.',
        element: getter,
      );
    }

    final oldKeys = _oldKeys(annotation, key, className, getter);

    final importUri = library.uri;
    if (importUri.scheme != 'package') {
      throw InvalidGenerationSource(
        '@jsonFactoryKey class `$className` must live under lib/ so it can be '
        'imported with a package: URI (found $importUri).',
        element: element,
      );
    }

    return JsonFactoryEntry(
      key: key,
      mixin: mixin,
      className: className,
      oldKeys: oldKeys,
      field: field,
      importUri: importUri.toString(),
    );
  }

  /// Reads `oldKeys`, which must be non-empty strings, distinct from each
  /// other and from the current [key].
  List<String> _oldKeys(
    ConstantReader annotation,
    String key,
    String className,
    GetterElement getter,
  ) {
    final oldKeys = <String>[];
    for (final object in annotation.read('oldKeys').listValue) {
      final oldKey = object.toStringValue();
      if (oldKey == null || oldKey.isEmpty) {
        throw InvalidGenerationSource(
          '@jsonFactoryKey oldKeys on `$className` must be non-empty strings.',
          element: getter,
        );
      }
      if (oldKey == key) {
        throw InvalidGenerationSource(
          "'$oldKey' is both the key and an old key of `$className`.",
          element: getter,
          todo: "Remove '$oldKey' from oldKeys.",
        );
      }
      if (oldKeys.contains(oldKey)) {
        throw InvalidGenerationSource(
          "@jsonFactoryKey oldKeys on `$className` lists '$oldKey' twice.",
          element: getter,
        );
      }
      oldKeys.add(oldKey);
    }
    return oldKeys;
  }

  /// Reads the key from the getter body, which must return a plain string
  /// literal: `=> 'user'` or `{ return 'user'; }`.
  Future<String> _keyLiteral(
    GetterElement getter,
    String className,
    BuildStep buildStep,
  ) async {
    final node = await buildStep.resolver.astNodeFor(getter.firstFragment);
    final body = node is MethodDeclaration ? node.body : null;
    final expression = switch (body) {
      ExpressionFunctionBody(:final expression) => expression,
      BlockFunctionBody(
        block: Block(statements: [ReturnStatement(:final expression)])
      ) =>
        expression,
      _ => null,
    };
    final value = expression is StringLiteral ? expression.stringValue : null;
    if (value == null || value.isEmpty) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey getter `$className.${getter.name}` must return a '
        'non-empty string literal, for example `=> \'user\'`.',
        element: getter,
      );
    }
    return value;
  }

  /// Requires `fromJson` as a factory/constructor or a static method whose
  /// only required parameter is the JSON map.
  void _checkFromJson(ClassElement element, String className) {
    final ExecutableElement? fromJson =
        element.getNamedConstructor('fromJson') ??
            switch (element.getMethod('fromJson')) {
              final m? when m.isStatic => m,
              _ => null,
            };

    if (fromJson == null) {
      throw InvalidGenerationSource(
        '`$className` has a @jsonFactoryKey getter but no '
        '`fromJson(Map<String, dynamic>)` factory constructor or static '
        'method.',
        element: element,
        todo: 'Add `factory $className.fromJson(Map<String, dynamic> json) '
            '=> _\$${className}FromJson(json);`',
      );
    }
    if (fromJson is ConstructorElement &&
        element.isAbstract &&
        !fromJson.isFactory) {
      throw InvalidGenerationSource(
        '`$className.fromJson` must be a factory: `$className` is abstract.',
        element: fromJson,
      );
    }

    final params = fromJson.formalParameters;
    final required = params.where((p) => p.isRequiredPositional).length;
    final requiredNamed = params.where((p) => p.isRequiredNamed).length;
    if (params.isEmpty ||
        required > 1 ||
        requiredNamed > 0 ||
        !params.first.isPositional) {
      throw InvalidGenerationSource(
        '`$className.fromJson` must take the JSON map as its only required '
        'argument.',
        element: fromJson,
      );
    }
  }
}

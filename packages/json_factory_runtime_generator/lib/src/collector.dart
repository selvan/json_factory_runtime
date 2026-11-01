import 'dart:convert';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
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

const _jsonValueChecker = TypeChecker.typeNamedLiterally(
  'JsonValue',
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
  /// `@jsonFactoryKey` field.
  Future<JsonFactoryEntry?> _entryFor(
    ClassElement element,
    LibraryElement library,
    BuildStep buildStep,
  ) async {
    for (final method in element.methods) {
      if (_keyChecker.hasAnnotationOf(method)) {
        throw InvalidGenerationSource(
          '@jsonFactoryKey must be on a final String field, not the method '
          '`${method.name}`.',
          element: method,
        );
      }
    }
    for (final getter in element.getters) {
      if (getter.isOriginDeclaration && _keyChecker.hasAnnotationOf(getter)) {
        throw InvalidGenerationSource(
          '@jsonFactoryKey must be on a final String field, not the getter '
          '`${getter.name}`.',
          element: getter,
          todo: "Use `final String ${getter.name} = 'your_key';`",
        );
      }
    }

    final annotated = [
      for (final field in element.fields)
        if (field.isOriginDeclaration)
          if (_keyChecker.firstAnnotationOf(field) case final annotation?)
            (field, ConstantReader(annotation)),
    ];
    if (annotated.isEmpty) return null;

    final className = element.name;
    if (annotated.length > 1) {
      throw InvalidGenerationSource(
        '`$className` has more than one @jsonFactoryKey field.',
        element: annotated[1].$1,
      );
    }
    final (field, annotation) = annotated.single;

    // The key only reaches the JSON through json_serializable's toJson.
    if (!_jsonSerializableChecker.hasAnnotationOf(element)) {
      throw InvalidGenerationSource(
        '`$className` has a @jsonFactoryKey field but is not annotated with '
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
    if (field.isStatic) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey field `$className.${field.name}` must not be '
        'static: json_serializable only writes instance members.',
        element: field,
      );
    }
    if (!field.isFinal || field.isLate) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey field `$className.${field.name}` must be final and '
        'not late: the key can\'t change at runtime.',
        element: field,
        todo: "Use `final String ${field.name} = 'your_key';`",
      );
    }
    if (!(field.type.isDartCoreString || field.type.element is EnumElement) ||
        field.type.nullabilitySuffix != NullabilitySuffix.none) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey field `$className.${field.name}` must be a '
        '`String` or an enum.',
        element: field,
        todo: "Use `final String ${field.name} = 'your_key';`",
      );
    }
    final fromJsonOwner = _checkFromJson(element, className);

    final key = await _keyValue(field, className, buildStep);
    final keyField = annotation.read('name').stringValue;
    if (keyField.isEmpty) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey name on `$className` must not be empty.',
        element: field,
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
        element: field,
      );
    }

    final oldKeys = _oldKeys(annotation, key, className, field);

    final importUri = library.uri;
    if (importUri.scheme != 'package') {
      throw InvalidGenerationSource(
        '@jsonFactoryKey class `$className` must live under lib/ so it can be '
        'imported with a package: URI (found $importUri).',
        element: element,
      );
    }

    final fromJsonUri = fromJsonOwner.library.uri;
    if (fromJsonUri.scheme != 'package') {
      throw InvalidGenerationSource(
        '`${fromJsonOwner.name}.fromJson`, used by `$className`, must live '
        'under lib/ so it can be imported with a package: URI '
        '(found $fromJsonUri).',
        element: element,
      );
    }

    return JsonFactoryEntry(
      key: key,
      mixin: mixin,
      className: className,
      oldKeys: oldKeys,
      field: keyField,
      importUri: importUri.toString(),
      fromJsonClass: fromJsonOwner.name!,
      fromJsonUri: fromJsonUri.toString(),
    );
  }

  /// Reads `oldKeys`, which must be non-empty strings, distinct from each
  /// other and from the current [key].
  List<String> _oldKeys(
    ConstantReader annotation,
    String key,
    String className,
    FieldElement field,
  ) {
    final oldKeys = <String>[];
    for (final object in annotation.read('oldKeys').listValue) {
      final oldKey = object.toStringValue();
      if (oldKey == null || oldKey.isEmpty) {
        throw InvalidGenerationSource(
          '@jsonFactoryKey oldKeys on `$className` must be non-empty strings.',
          element: field,
        );
      }
      if (oldKey == key) {
        throw InvalidGenerationSource(
          "'$oldKey' is both the key and an old key of `$className`.",
          element: field,
          todo: "Remove '$oldKey' from oldKeys.",
        );
      }
      if (oldKeys.contains(oldKey)) {
        throw InvalidGenerationSource(
          "@jsonFactoryKey oldKeys on `$className` lists '$oldKey' twice.",
          element: field,
        );
      }
      oldKeys.add(oldKey);
    }
    return oldKeys;
  }

  /// Reads the key from the initializer of [field]: a plain string literal,
  /// or an enum constant annotated with a string `@JsonValue`.
  Future<String> _keyValue(
    FieldElement field,
    String className,
    BuildStep buildStep,
  ) async {
    final isEnum = field.type.element is EnumElement;
    final node = await buildStep.resolver.astNodeFor(
      field.firstFragment,
      resolve: isEnum,
    );
    final expression = node is VariableDeclaration ? node.initializer : null;
    if (isEnum) {
      final value = _jsonValueOf(expression);
      if (value == null || value.isEmpty) {
        throw InvalidGenerationSource(
          '@jsonFactoryKey field `$className.${field.name}` must be initialized '
          'with an enum constant annotated with a non-empty string '
          "@JsonValue, for example `@JsonValue('user') user`.",
          element: field,
        );
      }
      return value;
    }
    final value = expression is StringLiteral ? expression.stringValue : null;
    if (value == null || value.isEmpty) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey field `$className.${field.name}` must be initialized '
        'with a non-empty string literal, for example '
        '`final String ${field.name} = \'user\';`.',
        element: field,
      );
    }
    return value;
  }

  /// The string `@JsonValue` of the enum constant [expression] refers to, or
  /// `null` when it isn't an enum constant with one.
  String? _jsonValueOf(Expression? expression) {
    final element = switch (expression) {
      PrefixedIdentifier(:final identifier) => identifier.element,
      PropertyAccess(:final propertyName) => propertyName.element,
      DotShorthandPropertyAccess(:final propertyName) => propertyName.element,
      _ => null,
    };
    final constant =
        element is PropertyAccessorElement ? element.variable : element;
    if (constant is! FieldElement || !constant.isEnumConstant) return null;
    final jsonValue = _jsonValueChecker.firstAnnotationOf(constant);
    if (jsonValue == null) return null;
    final value = ConstantReader(jsonValue).read('value');
    return value.isString ? value.stringValue : null;
  }

  /// Requires `fromJson` as a factory/constructor or a static method whose
  /// only required parameter is the JSON map, on [element] or else on the
  /// nearest superclass declaring one. Returns the class that declares it.
  InterfaceElement _checkFromJson(ClassElement element, String className) {
    InterfaceElement? owner = element;
    ExecutableElement? fromJson;
    while (owner != null) {
      fromJson = owner.getNamedConstructor('fromJson') ??
          switch (owner.getMethod('fromJson')) {
            final m? when m.isStatic => m,
            _ => null,
          };
      if (fromJson != null) break;
      owner = owner.supertype?.element;
    }

    if (owner == null || fromJson == null) {
      throw InvalidGenerationSource(
        '`$className` has a @jsonFactoryKey field but no '
        '`fromJson(Map<String, dynamic>)` factory constructor or static '
        'method, on itself or a superclass.',
        element: element,
        todo: 'Add `factory $className.fromJson(Map<String, dynamic> json) '
            '=> _\$${className}FromJson(json);`',
      );
    }
    final ownerName = owner.name;
    if (owner != element) {
      if (ownerName == null || owner.isPrivate) {
        throw InvalidGenerationSource(
          '`$className` uses `fromJson` of private superclass `$ownerName`: '
          'the generated factory has to import it.',
          element: element,
          todo: 'Add `factory $className.fromJson(Map<String, dynamic> json)` '
              'to `$className`.',
        );
      }
      if (owner.typeParameters.isNotEmpty) {
        throw InvalidGenerationSource(
          '`$className` uses `fromJson` of generic superclass `$ownerName`: '
          'it needs extra arguments for the type parameters.',
          element: element,
          todo: 'Add `factory $className.fromJson(Map<String, dynamic> json)` '
              'to `$className`.',
        );
      }
    }
    if (fromJson is ConstructorElement &&
        owner is ClassElement &&
        owner.isAbstract &&
        !fromJson.isFactory) {
      throw InvalidGenerationSource(
        '`$ownerName.fromJson` must be a factory: `$ownerName` is abstract.',
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
        '`$ownerName.fromJson` must take the JSON map as its only required '
        'argument.',
        element: fromJson,
      );
    }
    return owner;
  }
}

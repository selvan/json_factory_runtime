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

const _classKeyChecker = TypeChecker.typeNamed(
  JsonFactoryKey,
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

    // Nothing reads @JsonFactoryKey on a member, so the class would silently
    // go unregistered.
    for (final member in [
      ...element.methods,
      ...element.getters.where((g) => g.isOriginDeclaration),
      ...element.fields.where((f) => f.isOriginDeclaration),
    ]) {
      if (_classKeyChecker.hasAnnotationOf(member)) {
        throw InvalidGenerationSource(
          '@JsonFactoryKey must be on the class, not the member '
          '`${member.name}`.',
          element: member,
          todo: 'Move it to `${element.name}`, or use a @jsonFactoryKey() '
              'field if `toJson()` should write the key.',
        );
      }
    }

    final annotated = [
      for (final field in element.fields)
        if (field.isOriginDeclaration)
          if (_keyChecker.firstAnnotationOf(field) case final annotation?)
            (field, ConstantReader(annotation)),
    ];
    final classAnnotation = _classKeyChecker.firstAnnotationOf(element);
    if (classAnnotation != null) {
      if (annotated.isNotEmpty) {
        throw InvalidGenerationSource(
          '`${element.name}` has both @JsonFactoryKey and a @jsonFactoryKey '
          'field.',
          element: element,
          todo: 'Remove one of them.',
        );
      }
      return _classEntryFor(element, library, ConstantReader(classAnnotation));
    }
    if (annotated.isEmpty) {
      _checkNoInheritedKey(element);
      return null;
    }

    final className = _registrableName(element);
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
    return _entry(
      element,
      library,
      annotation,
      key: key,
      className: className,
      fromJsonOwner: fromJsonOwner,
      at: field,
    );
  }

  /// The registration for a class annotated with `@JsonFactoryKey`.
  JsonFactoryEntry _classEntryFor(
    ClassElement element,
    LibraryElement library,
    ConstantReader annotation,
  ) {
    final className = _registrableName(element);
    _checkNoInheritedKeyField(element);
    final key = annotation.read('key').stringValue;
    if (key.isEmpty) {
      throw InvalidGenerationSource(
        '@JsonFactoryKey on `$className` must not be empty.',
        element: element,
      );
    }
    if (!_hasToJson(element)) {
      throw InvalidGenerationSource(
        '`$className` has @JsonFactoryKey but no `toJson()` for '
        '`toJsonForFactory` to call, on itself or a superclass.',
        element: element,
        todo: 'Add `Map<String, dynamic> toJson()` to `$className`.',
      );
    }
    return _entry(
      element,
      library,
      annotation,
      key: key,
      className: className,
      fromJsonOwner: _checkFromJson(element, className),
      at: element,
    );
  }

  /// The name of [element], which must be public and not generic.
  String _registrableName(ClassElement element) {
    final className = element.name;
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
    return className;
  }

  /// Whether [element] or a supertype has an instance `toJson` callable with
  /// no arguments.
  bool _hasToJson(ClassElement element) {
    for (final type in [element.thisType, ...element.allSupertypes]) {
      final method = type.element.getMethod('toJson');
      if (method != null &&
          !method.isStatic &&
          !method.formalParameters.any((p) => p.isRequired)) {
        return true;
      }
    }
    return false;
  }

  /// Reads the options both annotations share and builds the registration.
  JsonFactoryEntry _entry(
    ClassElement element,
    LibraryElement library,
    ConstantReader annotation, {
    required String key,
    required String className,
    required InterfaceElement fromJsonOwner,
    required Element at,
  }) {
    final keyField = annotation.read('name').stringValue;
    if (keyField.isEmpty) {
      throw InvalidGenerationSource(
        '@jsonFactoryKey name on `$className` must not be empty.',
        element: at,
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
        element: at,
      );
    }

    final oldKeys = _oldKeys(annotation, key, className, at);

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
    Element at,
  ) {
    final oldKeys = <String>[];
    for (final object in annotation.read('oldKeys').listValue) {
      final oldKey = object.toStringValue();
      if (oldKey == null || oldKey.isEmpty) {
        throw InvalidGenerationSource(
          '@jsonFactoryKey oldKeys on `$className` must be non-empty strings.',
          element: at,
        );
      }
      if (oldKey == key) {
        throw InvalidGenerationSource(
          "'$oldKey' is both the key and an old key of `$className`.",
          element: at,
          todo: "Remove '$oldKey' from oldKeys.",
        );
      }
      if (oldKeys.contains(oldKey)) {
        throw InvalidGenerationSource(
          "@jsonFactoryKey oldKeys on `$className` lists '$oldKey' twice.",
          element: at,
        );
      }
      oldKeys.add(oldKey);
    }
    return oldKeys;
  }

  /// A concrete `@JsonSerializable` subclass of a registered class writes a key
  /// that doesn't decode back to it, unless it registers a key of its own.
  void _checkNoInheritedKey(ClassElement element) {
    if (element.isAbstract ||
        !_jsonSerializableChecker.hasAnnotationOf(element)) {
      return;
    }
    for (var parent = element.supertype?.element;
        parent != null;
        parent = parent.supertype?.element) {
      if (_classKeyChecker.hasAnnotationOf(parent)) {
        throw InvalidGenerationSource(
          '`${element.name}` extends `${parent.name}`, which has '
          "@JsonFactoryKey, but has none of its own, so its JSON won't decode "
          'back to `${element.name}`.',
          element: element,
          todo: "Add `@JsonFactoryKey('your_key')` and a `fromJson` to "
              '`${element.name}`.',
        );
      }
      for (final field in parent.fields) {
        if (field.isOriginDeclaration && _keyChecker.hasAnnotationOf(field)) {
          throw InvalidGenerationSource(
            '`${element.name}` extends `${parent.name}`, which has a '
            '@jsonFactoryKey field, but has none of its own, so its JSON '
            "won't decode back to `${element.name}`.",
            element: element,
            todo: 'Add `@jsonFactoryKey() @override final String ${field.name} '
                "= 'your_key';` and a `fromJson` to `${element.name}`.",
          );
        }
      }
    }
  }

  /// A `@JsonFactoryKey` class inheriting a `@jsonFactoryKey` field writes the
  /// parent's key from `toJson()`, which doesn't decode back to it.
  void _checkNoInheritedKeyField(ClassElement element) {
    for (var parent = element.supertype?.element;
        parent != null;
        parent = parent.supertype?.element) {
      for (final field in parent.fields) {
        if (field.isOriginDeclaration && _keyChecker.hasAnnotationOf(field)) {
          throw InvalidGenerationSource(
            '`${element.name}` has @JsonFactoryKey but extends '
            '`${parent.name}`, which has a @jsonFactoryKey field, so '
            "`toJson()` would write `${parent.name}`'s key.",
            element: element,
            todo: 'Replace @JsonFactoryKey with `@jsonFactoryKey() @override '
                "final String ${field.name} = 'your_key';`.",
          );
        }
      }
    }
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

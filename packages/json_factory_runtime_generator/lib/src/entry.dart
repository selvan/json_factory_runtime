/// One `@jsonFactoryKey` registration, as passed from the collector to the
/// aggregator.
class JsonFactoryEntry {
  final String key;
  final String mixin;
  final String className;

  /// Previous keys, still mapped to [className] when decoding.
  final List<String> oldKeys;

  /// JSON field the key is written to (the annotation's `name`).
  final String field;

  /// `package:` URI of the library that declares [className].
  final String importUri;

  /// Class whose `fromJson` builds [className]: [className] itself, or the
  /// nearest superclass declaring one.
  final String fromJsonClass;

  /// `package:` URI of the library that declares [fromJsonClass].
  final String fromJsonUri;

  const JsonFactoryEntry({
    required this.key,
    required this.mixin,
    required this.className,
    this.oldKeys = const [],
    required this.field,
    required this.importUri,
    String? fromJsonClass,
    String? fromJsonUri,
  })  : fromJsonClass = fromJsonClass ?? className,
        fromJsonUri = fromJsonUri ?? importUri;

  factory JsonFactoryEntry.fromJson(Map<String, dynamic> json) =>
      JsonFactoryEntry(
        key: json['key'] as String,
        mixin: json['mixin'] as String,
        className: json['className'] as String,
        oldKeys: (json['oldKeys'] as List?)?.cast<String>() ?? const [],
        field: json['field'] as String,
        importUri: json['importUri'] as String,
        fromJsonClass: json['fromJsonClass'] as String?,
        fromJsonUri: json['fromJsonUri'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'mixin': mixin,
        'className': className,
        'oldKeys': oldKeys,
        'field': field,
        'importUri': importUri,
        'fromJsonClass': fromJsonClass,
        'fromJsonUri': fromJsonUri,
      };

  /// Human-readable location used in error messages.
  String get location => '$className ($importUri)';
}

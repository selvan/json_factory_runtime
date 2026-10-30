/// One `@jsonFactoryKey` registration, as passed from the collector to the
/// aggregator.
class JsonFactoryEntry {
  final String key;
  final String mixin;
  final String className;

  /// JSON field the key is written to (the annotation's `name`).
  final String field;

  /// `package:` URI of the library that declares [className].
  final String importUri;

  const JsonFactoryEntry({
    required this.key,
    required this.mixin,
    required this.className,
    required this.field,
    required this.importUri,
  });

  factory JsonFactoryEntry.fromJson(Map<String, dynamic> json) =>
      JsonFactoryEntry(
        key: json['key'] as String,
        mixin: json['mixin'] as String,
        className: json['className'] as String,
        field: json['field'] as String,
        importUri: json['importUri'] as String,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'mixin': mixin,
        'className': className,
        'field': field,
        'importUri': importUri,
      };

  /// Human-readable location used in error messages.
  String get location => '$className ($importUri)';
}

import 'package:json_annotation/json_annotation.dart';
import 'package:json_factory_runtime_annotation/json_factory_runtime_annotation.dart';

import '../src/factories/json_factory_runtime.g.dart';

part 'command.g.dart';

/// The key is on the class, so there is no field for it and `toJson` is plain.
/// `CommandMapper.toJsonForFactory` adds the key.
@JsonFactoryKey('set_image', mixin: 'CommandMixin')
@JsonSerializable()
class SetImage {
  final String url;

  const SetImage({required this.url});

  factory SetImage.fromJson(Map<String, dynamic> json) =>
      _$SetImageFromJson(json);
  Map<String, dynamic> toJson() => _$SetImageToJson(this);
}

/// Inherits `toJson`, and still gets its own key from `toJsonForFactory`.
@JsonFactoryKey('set_logo', mixin: 'CommandMixin')
@JsonSerializable(createToJson: false)
class SetLogo extends SetImage {
  const SetLogo({required super.url});

  factory SetLogo.fromJson(Map<String, dynamic> json) =>
      _$SetLogoFromJson(json);
}

/// Not registered, so `toJsonForFactory` rejects it.
class SetDraft extends SetImage {
  const SetDraft({required super.url});
}

/// A nested object's `toJson` has no key, unless the field asks for it.
@JsonFactoryKey('wrap', mixin: 'CommandMixin')
@JsonSerializable(explicitToJson: true)
class Wrap {
  @JsonKey(toJson: CommandMapper.toJsonForFactory)
  final SetImage keyed;

  final SetImage plain;

  const Wrap({required this.keyed, required this.plain});

  factory Wrap.fromJson(Map<String, dynamic> json) => _$WrapFromJson(json);
  Map<String, dynamic> toJson() => _$WrapToJson(this);
}

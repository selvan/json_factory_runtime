// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'command.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SetImage _$SetImageFromJson(Map<String, dynamic> json) =>
    SetImage(url: json['url'] as String);

Map<String, dynamic> _$SetImageToJson(SetImage instance) => <String, dynamic>{
  'url': instance.url,
};

SetLogo _$SetLogoFromJson(Map<String, dynamic> json) =>
    SetLogo(url: json['url'] as String);

Wrap _$WrapFromJson(Map<String, dynamic> json) => Wrap(
  keyed: SetImage.fromJson(json['keyed'] as Map<String, dynamic>),
  plain: SetImage.fromJson(json['plain'] as Map<String, dynamic>),
);

Map<String, dynamic> _$WrapToJson(Wrap instance) => <String, dynamic>{
  'keyed': CommandMapper.toJsonForFactory(instance.keyed),
  'plain': instance.plain.toJson(),
};

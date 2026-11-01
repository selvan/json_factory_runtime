// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ApiEvent _$ApiEventFromJson(Map<String, dynamic> json) =>
    ApiEvent(name: json['name'] as String);

Map<String, dynamic> _$ApiEventToJson(ApiEvent instance) => <String, dynamic>{
  'name': instance.name,
  '__type__': _$ApiKindEnumMap[instance.factoryKey]!,
};

const _$ApiKindEnumMap = {ApiKind.event: 'api_event'};

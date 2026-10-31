// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'address.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Address _$AddressFromJson(Map<String, dynamic> json) =>
    Address(city: json['city'] as String, zip: json['zip'] as String);

Map<String, dynamic> _$AddressToJson(Address instance) => <String, dynamic>{
  'city': instance.city,
  'zip': instance.zip,
  '__type__': instance.factoryKey,
};

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Order _$OrderFromJson(Map<String, dynamic> json) => Order(
  id: json['id'] as String,
  total: (json['total'] as num).toDouble(),
  customer: json['customer'] == null
      ? null
      : User.fromJson(json['customer'] as Map<String, dynamic>),
);

Map<String, dynamic> _$OrderToJson(Order instance) => <String, dynamic>{
  'id': instance.id,
  'total': instance.total,
  'customer': instance.customer?.toJson(),
  '__type__': instance.factoryKey,
};

ApiUser _$ApiUserFromJson(Map<String, dynamic> json) =>
    ApiUser(login: json['login'] as String);

Map<String, dynamic> _$ApiUserToJson(ApiUser instance) => <String, dynamic>{
  'login': instance.login,
  '__type__': instance.factoryKey,
};

ApiAdmin _$ApiAdminFromJson(Map<String, dynamic> json) =>
    ApiAdmin(login: json['login'] as String);

Map<String, dynamic> _$ApiAdminToJson(ApiAdmin instance) => <String, dynamic>{
  'login': instance.login,
  '__type__': instance.factoryKey,
};

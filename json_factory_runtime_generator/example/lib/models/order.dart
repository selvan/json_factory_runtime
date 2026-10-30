import 'package:json_annotation/json_annotation.dart';
import 'package:json_factory_runtime_annotation/json_factory_runtime_annotation.dart';

import 'user.dart';

part 'order.g.dart';

@JsonSerializable(explicitToJson: true)
class Order {
  final String id;
  final double total;
  final User? customer;

  const Order({required this.id, required this.total, this.customer});

  @jsonFactoryKey(mixin: 'ApiMapper')
  String get factoryKey => 'order';

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
  Map<String, dynamic> toJson() => _$OrderToJson(this);
}

/// Same key as `User`, but in a different mixin, so it is allowed.
@JsonSerializable()
class ApiUser {
  final String login;

  const ApiUser({required this.login});

  @jsonFactoryKey(mixin: 'ApiMapper')
  String get factoryKey => 'user';

  factory ApiUser.fromJson(Map<String, dynamic> json) =>
      _$ApiUserFromJson(json);
  Map<String, dynamic> toJson() => _$ApiUserToJson(this);
}

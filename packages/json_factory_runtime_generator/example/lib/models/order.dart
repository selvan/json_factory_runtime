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

  @jsonFactoryKey(mixin: 'ApiMixin')
  final String factoryKey = 'order';

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
  Map<String, dynamic> toJson() => _$OrderToJson(this);
}

/// Same key as `User`, but in a different mixin, so it is allowed.
@JsonSerializable()
class ApiUser {
  final String login;

  const ApiUser({required this.login});

  @jsonFactoryKey(mixin: 'ApiMixin')
  final String factoryKey = 'user';

  factory ApiUser.fromJson(Map<String, dynamic> json) =>
      _$ApiUserFromJson(json);
  Map<String, dynamic> toJson() => _$ApiUserToJson(this);
}

/// A subclass registers under a key of its own, and needs its own `fromJson`.
@JsonSerializable()
class ApiAdmin extends ApiUser {
  const ApiAdmin({required super.login});

  @jsonFactoryKey(mixin: 'ApiMixin')
  @override
  // The key has to be a field, so the lint's advice to use a getter can't apply.
  // ignore: overridden_fields
  final String factoryKey = 'admin';

  factory ApiAdmin.fromJson(Map<String, dynamic> json) =>
      _$ApiAdminFromJson(json);
  @override
  Map<String, dynamic> toJson() => _$ApiAdminToJson(this);
}

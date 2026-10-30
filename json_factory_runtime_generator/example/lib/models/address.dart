import 'package:json_annotation/json_annotation.dart';
import 'package:json_factory_runtime_annotation/json_factory_runtime_annotation.dart';

part 'address.g.dart';

@JsonSerializable()
class Address {
  final String city;
  final String zip;

  const Address({required this.city, required this.zip});

  /// Was 'location'; JSON written with the old key still decodes.
  @jsonFactoryKey(oldKeys: ['location'])
  String get factoryKey => 'address';

  factory Address.fromJson(Map<String, dynamic> json) =>
      _$AddressFromJson(json);
  Map<String, dynamic> toJson() => _$AddressToJson(this);
}

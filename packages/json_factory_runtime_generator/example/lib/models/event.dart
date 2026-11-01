import 'package:json_annotation/json_annotation.dart';
import 'package:json_factory_runtime_annotation/json_factory_runtime_annotation.dart';

part 'event.g.dart';

enum ApiKind {
  @JsonValue('api_event')
  event,
}

/// The key comes from the `@JsonValue` of an enum constant.
@JsonSerializable()
class ApiEvent {
  final String name;

  const ApiEvent({required this.name});

  @jsonFactoryKey(mixin: 'ApiMixin')
  final ApiKind factoryKey = ApiKind.event;

  factory ApiEvent.fromJson(Map<String, dynamic> json) =>
      _$ApiEventFromJson(json);
  Map<String, dynamic> toJson() => _$ApiEventToJson(this);
}

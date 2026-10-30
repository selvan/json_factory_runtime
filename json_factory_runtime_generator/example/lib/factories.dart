import 'src/factories/json_factory_runtime.g.dart';

export 'src/factories/json_factory_runtime.g.dart';

/// Factory for models in the default mixin.
class ModelFactory with JsonFactoryMapper {
  const ModelFactory();
}

/// Factory for models registered with `mixin: 'ApiMapper'`.
class ApiFactory with ApiMapper {
  const ApiFactory();
}

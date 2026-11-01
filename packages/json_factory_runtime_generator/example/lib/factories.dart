import 'src/factories/json_factory_runtime.g.dart';

export 'src/factories/json_factory_runtime.g.dart';

/// Factory for models in the default mixin.
class ModelFactory with JsonFactoryMixin {
  const ModelFactory();
}

/// Factory for models registered with `mixin: 'ApiMixin'`.
class ApiFactory with ApiMixin {
  const ApiFactory();
}

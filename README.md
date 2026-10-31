# json_factory_runtime

Generates mixins that turn JSON back into the right `json_serializable` class at runtime, using a key stored in the JSON itself.

| Package | Add as | Contains |
|---|---|---|
| [`json_factory_runtime_annotation`](packages/json_factory_runtime_annotation/) | `dependencies` | `@jsonFactoryKey(...)` |
| [`json_factory_runtime_generator`](packages/json_factory_runtime_generator/) | `dev_dependencies` | build_runner builders (auto-applied) |

Usage, configuration and rules are in the [generator's README](packages/json_factory_runtime_generator/README.md). A full example project is in [`packages/json_factory_runtime_generator/example`](packages/json_factory_runtime_generator/example/).

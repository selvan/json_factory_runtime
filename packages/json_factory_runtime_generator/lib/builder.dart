/// build_runner entry points for json_factory_runtime_generator.
library;

import 'package:build/build.dart';

import 'src/aggregator.dart';
import 'src/collector.dart';

/// Per-library builder: records every class with a `@jsonFactoryKey` field in a
/// `.json_factory.json` file in the build cache.
Builder jsonFactoryCollector(BuilderOptions options) => JsonFactoryCollector();

/// Package-wide builder: merges the collected entries into one file, one mixin
/// per mixin name. Options in `build.yaml`:
/// - `output`: generated file, default `lib/generated/json_factory_runtime.g.dart`.
/// - `key_field`: JSON field holding the runtime key, default
///   `__type__`.
Builder jsonFactoryAggregator(BuilderOptions options) =>
    JsonFactoryAggregator.fromOptions(options);

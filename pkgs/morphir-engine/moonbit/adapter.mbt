///|
pub const PROVIDER : String = "finos/morphir-moonbit-frontend"

///|
fn input(source : @engine.Source, unit_id : String) -> @frontend.Input {
  {
    unit_id,
    package_name: source.package_name,
    module_name: source.module_name,
    source: source.content,
  }
}

///|
/// Descriptors and callbacks for in-process clients and engine registration.
/// The original single-function profile remains the default.
pub fn provider(
  limits~ : @frontend.Limits = @frontend.Limits::default(),
  library_limits~ : @frontend.LibraryLimits = @frontend.LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  unit_limits~ : @data.Limits = @data.Limits::default(),
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> @engine.SourceProvider raise {
  try {
    limits.validate()
    library_limits.validate()
  } catch {
    @frontend.Invalid(diagnostic) =>
      raise @engine.Rejected(
        diagnostic.code,
        diagnostic.detail,
        diagnostic.source,
      )
  }
  if max_string_code_units < 0 || max_string_code_units > 1048576 {
    raise @engine.Rejected(
      "moonbit_frontend.invalid_limits",
      "String code-unit limit must be between 0 and 1048576",
      None,
    )
  }
  let dependencies = Map::from_array([
    ("moonbitlang/parser", @frontend.PARSER_VERSION),
    ("moonbitlang/lexer", "0.4.3"),
  ])
  let seed : @engine.SourceProfile = {
    id: @ids.ProfileId::parse(@frontend.PROFILE),
    dependencies,
    evidence: @engine.LocalAcceptance,
    unit_limits,
    capabilities: {
      summary: "Single Boolean function",
      max_documents: Some(1),
      incremental: false,
      supported: [
        "One function with explicit Bool signature", "Boolean literals and parameters",
        "Negation, Boolean operators and conditionals",
      ],
      excluded: [
        "Function calls", "Local bindings", "Cross-file imports", "Other source types",
      ],
      limits: {
        "bytes": limits.max_bytes,
        "functions": 1,
        "parameters": limits.max_parameters,
        "expressions": limits.max_expressions,
        "expressionDepth": limits.max_depth,
      },
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile(
        input(source, unit_id),
        limits~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let library : @engine.SourceProfile = {
    id: @ids.ProfileId::parse(@frontend.LIBRARY_PROFILE),
    dependencies,
    evidence: @engine.LocalAcceptance,
    unit_limits,
    capabilities: {
      summary: "Boolean library",
      max_documents: Some(1),
      incremental: false,
      supported: [
        "Multiple functions with explicit Bool signatures", "Public and unexported functions",
        "Direct same-file calls, including forward and zero-input calls", "Immutable local bindings and lexical shadowing",
        "Boolean operators and conditionals",
      ],
      excluded: [
        "Recursion", "Cross-file imports", "Indirect or qualified calls", "Mutation",
        "Other source types",
      ],
      limits: {
        "bytes": library_limits.max_bytes,
        "functions": library_limits.max_functions,
        "parameters": library_limits.max_parameters,
        "lets": library_limits.max_lets,
        "expressions": library_limits.max_expressions,
        "calls": library_limits.max_calls,
        "expressionDepth": library_limits.max_depth,
        "callGraphDepth": library_limits.max_call_depth,
      },
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_library(
        input(source, unit_id),
        limits=library_limits,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      // Public entry enumeration belongs to the distribution and generator manifest.
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let foundation : @engine.SourceProfile = {
    ..library,
    id: @ids.ProfileId::parse(@frontend.TYPED_FOUNDATION_PROFILE),
    capabilities: {
      ..library.capabilities,
      summary: "Typed library foundation",
      supported: [
        "Explicit Bool and Int32 signatures, including the Int alias", "Typed immutable bindings, conditionals and direct same-file calls",
        "Boolean operators",
      ],
      excluded: [
        "Numeric literals and arithmetic", "String values", "Recursion", "Cross-file imports",
        "Qualified or indirect calls",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_typed_library(
        input(source, unit_id),
        limits=library_limits,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let numeric : @engine.SourceProfile = {
    ..foundation,
    id: @ids.ProfileId::parse(@frontend.INT32_LIBRARY_PROFILE),
    capabilities: {
      ..foundation.capabilities,
      summary: "Signed Int32 source library",
      supported: [
        "Explicit Bool and Int32 signatures, including the Int alias", "Signed Int32 literals, wraparound arithmetic and comparisons",
        "Typed immutable bindings, conditionals and direct same-file calls", "Boolean operators",
      ],
      excluded: [
        "String values", "Recursion", "Cross-file imports", "Qualified or indirect calls",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_int32_library(
        input(source, unit_id),
        limits=library_limits,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let integers : @engine.SourceProfile = {
    ..numeric,
    id: @ids.ProfileId::parse(@frontend.INTEGER_LIBRARY_PROFILE),
    capabilities: {
      ..numeric.capabilities,
      summary: "Integral MoonBit source library",
      supported: [
        "Bool, Int16, Int32, Int64, Byte, UInt16, UInt32, UInt64 and BigInt signatures",
        "Exact suffixed integer literals and width-normalized arithmetic", "Typed immutable bindings, conditionals and direct same-file calls",
      ],
      excluded: [
        "String values", "Numeric methods and casts", "Division and remainder", "Recursion, imports, indirect calls and mutation",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_integer_library(
        input(source, unit_id),
        limits=library_limits,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let floats : @engine.SourceProfile = {
    ..numeric,
    id: @ids.ProfileId::parse(@frontend.FLOAT_LIBRARY_PROFILE),
    capabilities: {
      ..numeric.capabilities,
      summary: "IEEE binary32 and binary64 source library",
      supported: [
        "Float and Double signatures and finite literals", "Arithmetic and comparisons with binary32 operation rounding",
        "Typed immutable bindings, conditionals and direct same-file calls",
      ],
      excluded: [
        "Source numeric casts", "Nonfinite source literals", "Recursion, imports, indirect calls and mutation",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_float_library(
        input(source, unit_id),
        limits=library_limits,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let string_limits = library.capabilities.limits.copy()
  string_limits["stringCodeUnits"] = max_string_code_units
  let strings : @engine.SourceProfile = {
    ..library,
    id: @ids.ProfileId::parse(@frontend.STRING_LIBRARY_PROFILE),
    capabilities: {
      ..library.capabilities,
      summary: "String and Boolean library",
      supported: [
        "Explicit String and Bool signatures", "String literals, concatenation and exact equality",
        "Immutable bindings, Boolean conditionals and direct same-file calls", "Well-formed UTF-16 with bounded public arguments and results",
      ],
      excluded: [
        "Ordering, length and slicing", "String methods and imports", "Numeric values",
        "Recursion", "Interpolation and multiline strings",
      ],
      limits: string_limits,
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_string_library(
        input(source, unit_id),
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let supported : @engine.SourceProfile = {
    ..strings,
    id: @ids.ProfileId::parse(@frontend.SUPPORTED_LIBRARY_PROFILE),
    capabilities: {
      ..strings.capabilities,
      summary: "Supported MoonBit library v1",
      supported: [
        "Qualified Bool, String and Int32 capabilities together in one library",
        "Explicit scalar signatures, including the Int alias", "String literals, bounded concatenation and exact equality",
        "Boolean operators, matching-type branches and typed immutable bindings",
        "Direct same-file calls, including forward and zero-input calls", "Well-formed UTF-16 with bounded public String arguments and results",
        "Int32 identity, selection and call paths",
      ],
      excluded: [
        "Numeric literals, arithmetic and numeric comparisons", "String ordering, length, slicing and methods",
        "Imports, recursion, indirect calls and mutation", "Interpolation, multiline strings and other scalar types",
        "Full MoonBit language or installed ecosystem conformance",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_supported_library(
        input(source, unit_id),
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let supported_v2 : @engine.SourceProfile = {
    ..supported,
    id: @ids.ProfileId::parse(@frontend.SUPPORTED_LIBRARY_PROFILE_V2),
    capabilities: {
      ..strings.capabilities,
      summary: "Supported MoonBit library v2",
      supported: [
        "Qualified Bool, String and Int32 capabilities together in one library",
        "Explicit scalar signatures, including the Int alias", "String literals, bounded concatenation and exact equality",
        "Boolean operators, matching-type branches and typed immutable bindings",
        "Direct same-file calls, including forward and zero-input calls", "Well-formed UTF-16 with bounded public String arguments and results",
        "Int32 identity, selection and call paths", "String <, <=, > and >= use UTF-16 shortlex ordering",
      ],
      excluded: [
        "Numeric literals, arithmetic and numeric comparisons", "String length, slicing and methods",
        "Imports, recursion, indirect calls and mutation", "Interpolation, multiline strings and other scalar types",
        "Full MoonBit language or installed ecosystem conformance",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_supported_library_v2(
        input(source, unit_id),
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let current : @engine.SourceProfile = {
    ..supported_v2,
    id: @ids.ProfileId::parse(@frontend.LIBRARY_PROFILE_2026_10_17),
    capabilities: {
      ..strings.capabilities,
      summary: "Supported MoonBit library 2026-10-17",
      supported: [
        "Qualified Bool, String and Int32 capabilities together in one library",
        "Explicit scalar signatures, including the Int alias", "String literals, bounded concatenation and exact equality",
        "Boolean operators, matching-type branches and typed immutable bindings",
        "Direct same-file calls, including forward and zero-input calls", "Well-formed UTF-16 with bounded public String arguments and results",
        "Int32 identity, selection and call paths", "String <, <=, > and >= use UTF-16 shortlex ordering",
      ],
      excluded: [
        "Numeric literals, arithmetic and numeric comparisons", "String length, slicing and methods",
        "Imports, recursion, indirect calls and mutation", "Interpolation, multiline strings and other scalar types",
        "Full MoonBit language or installed ecosystem conformance",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_supported_library_2026_10_17(
        input(source, unit_id),
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let indexed : @engine.SourceProfile = {
    ..current,
    id: @ids.ProfileId::parse(@frontend.LIBRARY_PROFILE_2026_10_19),
    capabilities: {
      ..current.capabilities,
      summary: "Supported MoonBit library 2026-10-19",
      supported: current.capabilities.supported +
      [
        "Signed Int32 literals, wraparound arithmetic and comparisons", "String.length() returns UTF-16 code-unit count as Int32",
        "String[start:end].to_owned() clamps indexes and adjusts split surrogate boundaries inward",
        "Mixed String and Int32 calls and results",
      ],
      excluded: [
        "Unowned String slices and single-index access", "Imports, recursion, indirect calls and mutation",
        "Interpolation, multiline strings and other scalar types", "Full MoonBit language conformance",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_supported_library_2026_10_19(
        input(source, unit_id),
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let pinned_dependencies = dependencies.copy()
  pinned_dependencies["finos/morphir-sdk/basics"] = "0.1.0+tree:9c83a100383570236b3d781362524008f76dd56d"
  let pinned_bindings = @frontend.PinnedSourceBindings::sdk_basics_not(
    "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
    "basics",
  ) catch {
    @frontend.Invalid(diagnostic) =>
      raise @engine.Rejected(
        diagnostic.code,
        diagnostic.detail,
        diagnostic.source,
      )
  }
  let pinned_sdk : @engine.SourceProfile = {
    ..foundation,
    id: @ids.ProfileId::parse(@frontend.PINNED_SDK_LIBRARY_PROFILE),
    dependencies: pinned_dependencies,
    capabilities: {
      ..foundation.capabilities,
      summary: "Typed Bool/Int32 library with one pinned SDK source call",
      supported: foundation.capabilities.supported +
      ["@basics.not_(Bool) -> Bool from pinned finos/morphir-sdk/basics 0.1.0"],
      excluded: [
        "Numeric literals and arithmetic", "String values", "Recursion", "Cross-file imports",
        "Indirect calls and other qualified SDK calls", "Numeric math and String SDK calls",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_pinned_sdk_library(
        input(source, unit_id),
        pinned_bindings,
        limits=library_limits,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let math_bindings = @frontend.PinnedSourceBindings::sdk_numeric_math(
    "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
    "basics",
  ) catch {
    @frontend.Invalid(diagnostic) =>
      raise @engine.Rejected(
        diagnostic.code,
        diagnostic.detail,
        diagnostic.source,
      )
  }
  let math : @engine.SourceProfile = {
    ..indexed,
    id: @ids.ProfileId::parse(@frontend.MATH_LIBRARY_PROFILE),
    dependencies: pinned_dependencies,
    capabilities: {
      ..indexed.capabilities,
      summary: "Supported MoonBit library 2026-10-19 revision 2 with pinned math calls",
      supported: indexed.capabilities.supported +
      integers.capabilities.supported +
      floats.capabilities.supported +
      [
        "Pinned @basics.not_, sqrt, sin, cos, power_float and abs_float", "Classic binary64 SDK math with declared per-function reference contracts",
      ],
      excluded: [
        "Source numeric casts and Integer-returning SDK rounding calls", "Other qualified SDK calls, Decimal and generic values",
        "Integer division, recursion, cross-file imports, mutation and indirect calls",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_math_library(
        input(source, unit_id),
        math_bindings,
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let conversion_bindings = @frontend.PinnedSourceBindings::sdk_numeric_conversions(
    "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
    "basics",
  ) catch {
    @frontend.Invalid(diagnostic) =>
      raise @engine.Rejected(
        diagnostic.code,
        diagnostic.detail,
        diagnostic.source,
      )
  }
  let conversion_dependencies = pinned_dependencies.copy()
  for
    package_name in [
      "finos/morphir-sdk", "finos/morphir-sdk/int", "finos/morphir-sdk/integer",
    ] {
    conversion_dependencies[package_name] = "0.1.0+tree:9c83a100383570236b3d781362524008f76dd56d"
  }
  let numeric_sdk : @engine.SourceProfile = {
    ..math,
    id: @ids.ProfileId::parse(@frontend.NUMERIC_SDK_LIBRARY_PROFILE),
    dependencies: conversion_dependencies,
    capabilities: {
      ..math.capabilities,
      summary: "Supported MoonBit library 2026-10-19 revision 3 with SDK Integer conversions",
      supported: math.capabilities.supported +
      [
        "Pinned @integer.Integer, @integer.Integer? and Double? boundaries", "Classic round, floor, ceiling, truncate, to_float and abs_int calls",
        "Explicit binary64 optional Int conversions through @int", "Declared raise @sdk.SdkError with checked direct-call propagation",
      ],
      excluded: [
        "General source effects, error handlers, Maybe patterns and constructors",
        "Source numeric casts and Float32 SDK carrier conversions", "Other SDK calls, Decimal, imports, recursion, mutation and indirect calls",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_numeric_sdk_library(
        input(source, unit_id),
        conversion_bindings,
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  let decimal_bindings = @frontend.PinnedSourceBindings::sdk_decimal(
    "finos/morphir-sdk/decimal",
    "0.1.0",
    @frontend.DECIMAL_SDK_TREE,
    "decimal",
  ) catch {
    @frontend.Invalid(d) => raise @engine.Rejected(d.code, d.detail, d.source)
  }
  let decimal_dependencies = conversion_dependencies.copy()
  decimal_dependencies["finos/morphir-sdk/decimal"] = "0.1.0+tree:" +
    @frontend.DECIMAL_SDK_TREE
  let decimal_sdk : @engine.SourceProfile = {
    ..numeric_sdk,
    id: @ids.ProfileId::parse(@frontend.DECIMAL_LIBRARY_PROFILE),
    dependencies: decimal_dependencies,
    capabilities: {
      ..numeric_sdk.capabilities,
      summary: "Supported MoonBit library revision 4 with checked Decimal calculations",
      supported: numeric_sdk.capabilities.supported +
      [
        "Pinned @decimal.Decimal and declared raise @decimal.DecimalError", "Exact construction, add/sub/mul, six comparisons, half-even rounding",
        "Versioned checked divide with distinct failures and opt-in fallback",
      ],
      excluded: [
        "General source effects, error handlers, Maybe patterns and constructors",
        "Source numeric casts and Float32 SDK carrier conversions", "Other SDK calls, imports, recursion, mutation and indirect calls",
      ],
    },
    compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
      let output = @frontend.compile_decimal_library(
        input(source, unit_id),
        decimal_bindings,
        limits=library_limits,
        max_string_code_units~,
        cancelled~,
        scope=observer.scope(),
      ) catch {
        @frontend.Invalid(diagnostic) =>
          raise @engine.Rejected(
            diagnostic.code,
            diagnostic.detail,
            diagnostic.source,
          )
        error => raise error
      }
      @data.IRUnit::{
        id: output.unit_id,
        distribution: output.ir,
        metadata: output.metadata.map(m => { node_id: m.node_id, data: m.data, }),
        annotations: output.annotations.copy(),
        provenance: output.provenance.copy(),
      }
    }),
  }
  {
    id: @ids.ProviderId::parse(PROVIDER),
    languages: [
      {
        id: @ids.LanguageId::parse("moonbit"),
        extensions: [@ids.FileExtension::parse(".mbt")],
        default_profile: @ids.ProfileId::parse(@frontend.PROFILE),
        profiles: [
          seed, library, foundation, numeric, integers, floats, strings, supported,
          supported_v2, current, indexed, pinned_sdk, math, numeric_sdk, decimal_sdk,
        ],
      },
    ],
  }
}

///|
/// Register the same descriptors exposed to in-process clients.
pub fn register(
  engine : @engine.Engine,
  limits~ : @frontend.Limits = @frontend.Limits::default(),
  library_limits~ : @frontend.LibraryLimits = @frontend.LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  unit_limits~ : @data.Limits = @data.Limits::default(),
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> Unit raise {
  engine.register_source_provider(
    provider(
      limits~,
      library_limits~,
      max_string_code_units~,
      unit_limits~,
      observer~,
    ),
  )
}

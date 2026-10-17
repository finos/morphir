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
  {
    id: @ids.ProviderId::parse(PROVIDER),
    languages: [
      {
        id: @ids.LanguageId::parse("moonbit"),
        extensions: [@ids.FileExtension::parse(".mbt")],
        default_profile: @ids.ProfileId::parse(@frontend.PROFILE),
        profiles: [
          seed, library, foundation, strings, supported, supported_v2, current,
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

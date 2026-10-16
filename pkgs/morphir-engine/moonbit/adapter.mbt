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
  {
    id: @ids.ProviderId::parse(PROVIDER),
    languages: [
      {
        id: @ids.LanguageId::parse("moonbit"),
        extensions: [@ids.FileExtension::parse(".mbt")],
        default_profile: @ids.ProfileId::parse(@frontend.PROFILE),
        profiles: [seed, library],
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
  unit_limits~ : @data.Limits = @data.Limits::default(),
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> Unit raise {
  engine.register_source_provider(
    provider(limits~, library_limits~, unit_limits~, observer~),
  )
}

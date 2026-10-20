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
/// Stable is the default; experimental contains capabilities awaiting promotion.
pub fn provider(
  library_limits~ : @frontend.LibraryLimits = @frontend.LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  unit_limits~ : @data.Limits = @data.Limits::default(),
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> @engine.SourceProvider raise {
  library_limits.validate() catch {
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
  fn channel_profile(
    channel : @frontend.SourceChannel,
  ) -> @engine.SourceProfile raise {
    let library_dependencies = dependencies.copy()
    for package_name in ["finos/morphir-sdk", "finos/morphir-sdk/basics"] {
      library_dependencies[package_name] = "0.1.0+tree:9c83a100383570236b3d781362524008f76dd56d"
    }
    library_dependencies[@frontend.MOONBIT_CORE_PACKAGE] = @frontend.MOONBIT_CORE_VERSION +
      "+tree:" +
      @frontend.MOONBIT_CORE_TREE
    if channel == @frontend.Experimental {
      for package_name in ["finos/morphir-sdk/int", "finos/morphir-sdk/integer"] {
        library_dependencies[package_name] = "0.1.0+tree:9c83a100383570236b3d781362524008f76dd56d"
      }
      library_dependencies["finos/morphir-sdk/decimal"] = "0.1.0+tree:" +
        @frontend.DECIMAL_SDK_TREE
    }
    let bindings = (if channel == @frontend.Stable {
      @frontend.PinnedSourceBindings::sdk_basics_not(
        "finos/morphir-sdk/basics", "0.1.0", "9c83a100383570236b3d781362524008f76dd56d",
        "basics",
      )
    } else {
      @frontend.PinnedSourceBindings::sdk_decimal(
        "finos/morphir-sdk/decimal",
        "0.1.0",
        @frontend.DECIMAL_SDK_TREE,
        "decimal",
      )
    }).with_string_predicates(
      @frontend.MOONBIT_CORE_PACKAGE,
      @frontend.MOONBIT_CORE_VERSION,
      @frontend.MOONBIT_CORE_TREE,
    ) catch {
      @frontend.Invalid(d) => raise @engine.Rejected(d.code, d.detail, d.source)
    }
    let common = [
      "Public and unexported functions with explicit concrete signatures", "Immutable bindings, lexical shadowing, conditionals and direct same-file calls",
      "Bool, Int32/Int values, qualified Int32 arithmetic and comparisons", "Bounded well-formed UTF-16 Strings, concatenation, equality and shortlex ordering",
      "String.length() and owned slices with qualified UTF-16 index semantics", "Pinned @basics.not_ Boolean call",
      "Pinned String is_empty, contains, has_prefix and has_suffix predicates",
    ]
    {
      id: @ids.ProfileId::parse(channel.profile()),
      dependencies: library_dependencies,
      evidence: @engine.LocalAcceptance,
      unit_limits,
      capabilities: {
        summary: if channel == @frontend.Stable {
          "Stable typed MoonBit library"
        } else {
          "Experimental typed MoonBit library"
        },
        max_documents: Some(1),
        incremental: false,
        supported: common +
        (if channel == @frontend.Experimental {
          [
            "Fixed-width signed/unsigned integers, BigInt, Float and Double with IEEE operation rounding",
            "SDK Integer boundaries, classic rounding, explicit optional conversions and binary64 math",
            "Checked Decimal construction, arithmetic, comparisons, half-even rounding and division",
            "Declared SDK error propagation without general source effects",
          ]
        } else {
          []
        }),
        excluded: [
          "Recursion, cross-file imports, mutation and indirect calls", "Integer division, source numeric casts and Float32 SDK carrier conversions",
          "General source effects, error handlers, Maybe patterns and constructors",
          "Unowned String slices, single-index access, interpolation and multiline strings",
          "Unlisted SDK calls and full MoonBit language conformance",
        ] +
        (if channel == @frontend.Stable {
          [
            "Unpromoted numeric widths, floats, SDK math/conversions and Decimal; select experimental",
          ]
        } else {
          []
        }),
        limits: {
          "bytes": library_limits.max_bytes,
          "functions": library_limits.max_functions,
          "parameters": library_limits.max_parameters,
          "lets": library_limits.max_lets,
          "expressions": library_limits.max_expressions,
          "calls": library_limits.max_calls,
          "expressionDepth": library_limits.max_depth,
          "callGraphDepth": library_limits.max_call_depth,
          "stringCodeUnits": max_string_code_units,
        },
      },
      compile: @engine.PerFile(fn(source, unit_id, cancelled) raise {
        let output = @frontend.compile_library(
          input(source, unit_id),
          channel~,
          bindings=Some(bindings),
          limits=library_limits,
          max_string_code_units~,
          cancelled~,
          scope=observer.scope(),
        ) catch {
          @frontend.Invalid(d) =>
            raise @engine.Rejected(d.code, d.detail, d.source)
          error => raise error
        }
        @data.IRUnit::{
          id: output.unit_id,
          distribution: output.ir,
          metadata: output.metadata.map(m => {
            node_id: m.node_id,
            data: m.data,
          }),
          annotations: output.annotations.copy(),
          provenance: output.provenance.copy(),
        }
      }),
    }
  }
  {
    id: @ids.ProviderId::parse(PROVIDER),
    languages: [
      {
        id: @ids.LanguageId::parse("moonbit"),
        extensions: [@ids.FileExtension::parse(".mbt")],
        default_profile: @ids.ProfileId::parse(@frontend.STABLE_PROFILE),
        profiles: [
          channel_profile(@frontend.Stable),
          channel_profile(@frontend.Experimental),
        ],
      },
    ],
  }
}

///|
/// Register the same descriptors exposed to in-process clients.
pub fn register(
  engine : @engine.Engine,
  library_limits~ : @frontend.LibraryLimits = @frontend.LibraryLimits::default(),
  max_string_code_units~ : Int32 = 1048576,
  unit_limits~ : @data.Limits = @data.Limits::default(),
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> Unit raise {
  engine.register_source_provider(
    provider(library_limits~, max_string_code_units~, unit_limits~, observer~),
  )
}

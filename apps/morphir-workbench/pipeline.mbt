///|
/// Local adapter envelopes are private to the worker, not Morphir RPC methods.
/// Decode/migrate imports explicitly; the inspector uses the current semantic model.
pub fn execute(request : Json) -> Json {
  try {
    let operation = @wire.string(@wire.field(request, "operation"))
    if operation == "catalog" {
      return source_catalog()
    }
    let source = @wire.string(@wire.field(request, "source"))
    let language = match @wire.optional(request, "languageId") {
      None => "scheme"
      Some(String(language)) => language
      _ => raise @scheme.Invalid("This local input language is unavailable")
    }
    let target = if operation == "compile" || operation == "run" {
      if !["scheme", "moonbit"].contains(language) {
        raise @scheme.Invalid("This local input language is unavailable")
      }
      let target = match @wire.optional(request, "target") {
        None => "scheme"
        Some(String(target)) => target
        _ => raise @scheme.Invalid("This generation target is unavailable")
      }
      if !["", "scheme", "elm", "moonbit"].contains(target) {
        raise @scheme.Invalid(
          "This generation target is unavailable: " + target,
        )
      }
      target
    } else {
      ""
    }
    if (
        operation == "compile" || operation == "run" || operation == "worksheet"
      ) &&
      language != "moonbit" &&
      (
        source_constraint(request, "frontendProvider") != None ||
        source_constraint(request, "frontendProfile") != None
      ) {
      raise @scheme.Invalid("frontend.provider_language_mismatch: " + language)
    }
    if operation == "worksheet" {
      if language != "scheme" {
        raise @scheme.Invalid("The local worksheet supports Scheme only")
      }
      let runtime = @scheme.Runtime::new()
      let results = @scheme.parse_program(source).map(form => {
        @wire.obj([
          ("expression", @wire.text(form.to_source())),
          (
            "value",
            @wire.text(@scheme.value_to_string(runtime.eval(form.to_source()))),
          ),
        ])
      })
      return @wire.obj([
        ("success", Json::boolean(true)),
        ("results", Json::array(results)),
      ])
    }
    if operation == "run" && language != "scheme" {
      raise @scheme.Invalid(
        "Compile MoonBit, then evaluate a public function in Model Explorer",
      )
    }
    let compiled = if (operation == "compile" || operation == "run") &&
      language == "moonbit" {
      Some(compile_source(request, source))
    } else {
      None
    }
    let file = if operation == "inspect" || operation == "evaluate" {
      @migration.to_current(@versioned.read(source))
    } else if operation == "compile" || operation == "run" {
      match compiled {
        Some(output) => output.unit.distribution
        None => @frontend.compile_file(source)
      }
    } else {
      raise @scheme.Invalid("Unknown operation: " + operation)
    }
    if operation == "evaluate" {
      if @wire.optional(request, "executionMode") == Some(@wire.text("typed")) {
        return evaluate_typed(file, request)
      }
      return evaluate_model(file, request)
    }
    let (package_name, distribution_kind) = match file.distribution {
      Library(name, _, _) => (name, "Library")
      Specs(name, _, _) => (name, "Specification")
      Application(name, _, _, _) => (name, "Application")
    }
    let result = [
      ("success", Json::boolean(true)),
      ("ir", @codec.to_json(file)),
      ("irSource", @wire.text(@codec.to_json(file).stringify())),
      ("nodes", Json::array(describe(file))),
      ("evaluations", evaluation_profiles(file)),
      ("typedEvaluations", typed_profiles(file)),
      ("package", @wire.text(package_name.to_canonical())),
      ("distributionKind", @wire.text(distribution_kind)),
      ("formatVersion", @wire.text(file.format_version.to_release_string())),
    ]
    if compiled is Some(output) {
      source_ui(result, output.unit.metadata)
      result.push(("sourceWarnings", source_warnings(output.unit.provenance)))
    }
    let generator_input = match compiled {
      Some(output) => {
        let unit = output.unit
        let registry = @data.Registry::new()
        match registry.encode("ion-text", unit) {
          Text(source) => result.push(("sourceUnitIon", @wire.text(source)))
          Binary(_) => ()
        }
        result.push(("sourceProfile", @wire.text(output.profile)))
        result.push(("sourceProvider", @wire.text(output.provider)))
        let entries = match
          @wire.field(
            @wire.field(@wire.obj(result), "typedEvaluations"),
            "entries",
          ) {
          Object(entries) => entries.keys().collect()
          _ => []
        }
        entries.sort()
        result.push(("sourceEntries", Json::array(entries.map(@wire.text))))
        if output.profile == @moonbit_frontend.PROFILE {
          let entry = unit.metadata[0].node_id
            .strip_prefix("value:")
            .unwrap()
            .to_owned()
          result.push(("sourceEntry", @wire.text(entry)))
          result.push(("sourcePublic", Json::boolean(entries.contains(entry))))
        }
        @moonbit.Input::{
          unit_id: unit.id,
          ir: file,
          metadata: unit.metadata.map(m => { node_id: m.node_id, data: m.data, }),
          annotations: unit.annotations,
          provenance: unit.provenance,
        }
      }
      None => @moonbit.Input::new("workbench", file)
    }
    if target == "scheme" {
      result.push(("generated", @wire.text(@backend.emit_file(file))))
    } else if target == "moonbit" {
      match moonbit_output(generator_input) {
        Object(fields) =>
          for key, value in fields {
            result.push((key, value))
          }
        _ => ()
      }
    } else if target == "elm" {
      let generated = elm_output(file)
      match generated {
        Object(fields) =>
          for key, value in fields {
            result.push((key, value))
          }
        _ => ()
      }
    }
    if operation == "run" {
      result.push(
        (
          "value",
          @wire.text(
            @scheme.value_to_string(
              @backend.run_file(file, @ir.FQName::parse("user:main#main"), []),
            ),
          ),
        ),
      )
    }
    @wire.obj(result)
  } catch {
    @ion.Syntax(message)
    | @ion.DataModel(message)
    | @ion.Unsupported(message) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text("Ion: " + message)),
      ])
    @moonbit_frontend.Invalid(diagnostic) =>
      frontend_failure(diagnostic.code, diagnostic.detail, diagnostic.source)
    @engine.Rejected(code, detail, source) =>
      frontend_failure(code, detail, source)
    @protocol.Invalid(code) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(code)),
      ])
    @moonbit.Invalid(code, _, detail) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(code + ": " + detail)),
      ])
    @wire.Invalid(_, message) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(message)),
      ])
    error =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(@scheme.error_message(error))),
      ])
  }
}

///|
fn elm_problem(problem : @elm.Problem) -> Json {
  @wire.obj([
    ("code", @wire.text(problem.code)),
    ("nodePath", @wire.text(problem.node_path)),
    ("detail", @wire.text(problem.detail)),
  ])
}

///|
/// A generation refusal must not discard the successfully compiled model.
fn elm_output(file : @ir.IRFile) -> Json {
  try {
    let output = @elm.generate("workbench", file, @elm.Options::default())
    @wire.obj([
      (
        "artifacts",
        Json::array(
          output.files.map(file => {
            @wire.obj([
              ("path", @wire.text(file.path)),
              ("content", @wire.text(file.content)),
              ("binary", Json::boolean(false)),
            ])
          }),
        ),
      ),
      (
        "generated",
        @wire.text(
          output.files
          .filter(f => f.role == @elm.Source)
          .get(0)
          .map(f => f.content)
          .unwrap_or(""),
        ),
      ),
      ("generationWarnings", Json::array(output.warnings.map(@wire.text))),
    ])
  } catch {
    @elm.Refused(problem) => elm_refusal([problem])
    @elm.Failed(problems) => elm_refusal(problems)
  }
}

///|
fn elm_refusal(problems : Array[@elm.Problem]) -> Json {
  @wire.obj([
    ("artifacts", Json::array([])),
    ("generationDiagnostics", Json::array(problems.map(elm_problem))),
    (
      "generationMessage",
      @wire.text(
        "Elm generation failed: " +
        problems
        .map(p => p.code + " at " + p.node_path + ": " + p.detail)
        .join("; "),
      ),
    ),
  ])
}

///|
fn frontend_failure(
  code : String,
  detail : String,
  source : @ir.SourceLocation?,
) -> Json {
  @wire.obj([
    ("success", Json::boolean(false)),
    ("message", @wire.text(code + ": " + detail)),
    (
      "frontendDiagnostic",
      @wire.obj([
        ("code", @wire.text(code)),
        ("coordinateProfile", @wire.text("moonbit-parser-position-v1")),
        ("detail", @wire.text(detail)),
        (
          "source",
          source
          .map(loc => {
            @wire.obj([
              ("startLine", Json::number(loc.start_line.to_double())),
              ("startColumn", Json::number(loc.start_column.to_double())),
              ("endLine", Json::number(loc.end_line.to_double())),
              ("endColumn", Json::number(loc.end_column.to_double())),
            ])
          })
          .unwrap_or(Json::null()),
        ),
      ]),
    ),
  ])
}

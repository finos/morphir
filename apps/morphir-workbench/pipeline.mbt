///|
/// Local adapter envelopes are private to the worker, not Morphir RPC methods.
/// Decode/migrate imports explicitly; the inspector uses the current semantic model.
pub fn execute_with(engine : @engine.Engine, request : Json) -> Json {
  try {
    let operation = @wire.string(@wire.field(request, "operation"))
    if operation == "catalog" {
      return catalog(engine)
    }
    if operation == "compile" || operation == "run" {
      let project = project_request(request, engine.languages())
      if operation == "run" && project.language.to_string() != "scheme" {
        raise @scheme.Invalid(
          "Compile, then evaluate a public function in Model Explorer",
        )
      }
      let target = optional_text(request, "target").unwrap_or("scheme")
      let engine_run = run_engine(engine, project, target)
      let result = compile_reply(engine_run, project, target) catch {
        CompileFailed(reply) => return reply
        error => raise error
      }
      if operation == "run" && engine_run.unit is Some(unit) {
        result.push(
          (
            "value",
            @wire.text(
              @scheme.value_to_string(
                @backend.run_file(
                  unit.distribution,
                  @ir.FQName::parse("user:main#main"),
                  [],
                ),
              ),
            ),
          ),
        )
      }
      return @wire.obj(result)
    }
    let source = @wire.string(@wire.field(request, "source"))
    let language = match @wire.optional(request, "languageId") {
      None => "scheme"
      Some(String(language)) => language
      _ => raise @scheme.Invalid("This local input language is unavailable")
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
    let imported = if operation == "inspect" &&
      @wire.optional(request, "sourceCodec") != None {
      let codec = @wire.string(@wire.field(request, "sourceCodec"))
      guard ["morphir-json", "ion-text", "ion-binary"].contains(codec) else {
        raise @scheme.Invalid("Unsupported model codec")
      }
      let encoded = @wire.string(@wire.field(request, "sourceBase64"))
      guard encoded.length() <= 22369624 else {
        raise @scheme.Invalid("Model import exceeds the 16-MiB limit")
      }
      let bytes = @base64.decode(encoded[:])
      guard bytes.length() <= 16 * 1024 * 1024 else {
        raise @scheme.Invalid("Model import exceeds the 16-MiB limit")
      }
      let registry = @data.Registry::new(limits={
        max_bytes: 16 * 1024 * 1024,
        max_depth: 128,
        max_values: 100000,
      })
      Some(
        registry.open_checkpoint(
          codec,
          if codec == "ion-binary" {
            @data.Binary(bytes)
          } else {
            @data.Text(@utf8.decode(bytes))
          },
        ),
      )
    } else {
      None
    }
    let file = if imported is Some(unit) {
      unit.distribution
    } else if operation == "inspect" || operation == "evaluate" {
      @migration.to_current(@versioned.read(source))
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
    if imported is Some(unit) {
      source_ui(result, unit.metadata)
      let registry = @data.Registry::new(limits={
        max_bytes: 16 * 1024 * 1024,
        max_depth: 128,
        max_values: 100000,
      })
      match registry.encode("ion-text", unit) {
        Text(source) => result.push(("sourceUnitIon", @wire.text(source)))
        Binary(_) => ()
      }
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
    CompileFailed(reply) => reply
    @config.Invalid(message) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(message)),
      ])
    @protocol.Invalid(code) =>
      @wire.obj([
        ("success", Json::boolean(false)),
        ("message", @wire.text(code)),
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
/// The local worker's entry: one engine with the built-in providers for each request.
pub fn execute(request : Json) -> Json {
  let engine = workbench_engine() catch {
    error =>
      return @wire.obj([
        ("success", Json::boolean(false)),
        (
          "message",
          @wire.text("Engine setup failed: " + @scheme.error_message(error)),
        ),
      ])
  }
  execute_with(engine, request)
}

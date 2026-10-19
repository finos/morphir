///|
fn generation_backend_options(cli : Cli, backend : String) -> Json raise {
  let fields : Map[String, Json] = Map([])
  for source in values(cli, "backend-option") {
    guard source.find("=") is Some(at) && at > 0 && source.length() <= 65536 else {
      raise @config.Invalid("generate.invalid_option: Expected key=<JSON>")
    }
    let key = source[:at].to_owned()
    if fields.contains(key) {
      raise @config.Invalid("generate.duplicate_option: " + key)
    }
    if backend == "moonbit" && key != "naming" {
      raise @config.Invalid("generate.unsupported_option: " + key)
    }
    fields[key] = @model_wire.parse_bounded(source[at + 1:].to_owned())
  }
  Json::object(fields)
}

///|
fn generation_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  if !@platform.bytes_supported() || !@platform.interruption_supported() {
    raise @config.Invalid(
      "generate.host_unavailable: Local files and cancellation are required",
    )
  }
  @platform.interruption_start()
  defer @platform.interruption_stop()
  let backend = value(cli, "target", fallback="moonbit")
  if !["moonbit", "elm"].contains(backend) {
    raise @config.Invalid("generation.unsupported_target: " + backend)
  }
  let options = generation_backend_options(cli, backend)
  let policy = match value(cli, "validation", fallback="source-only") {
    "source-only" => @engine.SourceOnly
    "required" => @engine.Required(value(cli, "build-target", fallback="js"))
    _ => raise @config.Invalid("generate.invalid_validation")
  }
  let provider = match value(cli, "build-provider") {
    "" => None
    "process" =>
      Some(
        @host.LibraryBuildProvider::process(
          value(cli, "build-node", fallback="node"),
          value(cli, "build-helper"),
          value(cli, "home"),
          Map::from_array([("finos/morphir-sdk", value(cli, "sdk"))]),
          timeout=build_timeout(value(cli, "timeout", fallback="120000")),
        ),
      )
    other => raise @config.Invalid("build.unsupported_provider: " + other)
  }
  let path = value(cli, "path")
  if path == "" {
    raise @config.Invalid("generate requires a model path")
  }
  let unit = load_local_model(cli, @data.Limits::default())
  let output = @metadata_grants.host_path(
    value(cli, "output", fallback="dist"),
    @platform.cwd(),
    @platform.system_type(),
  )
  let leaf = output.split("/").last().unwrap_or("").to_owned()
  if leaf == "" {
    raise @config.Invalid("generate.invalid_output")
  }
  let parent = output[:output.length() - leaf.length()].to_owned()
  if @platform.kind(parent) != 2 {
    raise @config.Invalid("generate.output_parent_required: " + parent)
  }
  let engine = @engine.Engine::new()
  let plan = engine.plan_retained_generation(
    unit,
    backend,
    leaf,
    options~,
    policy~,
    project=value(cli, "project", fallback="generated"),
  )
  if flag(cli, "dry-run") {
    emit_plan(plan.sources(), plan.destinations(), plan.boundaries(), mode)
    return 0
  }
  let logs = @host.TelemetrySession::local(
    @platform.cwd(),
    values(cli, "log-file").get(0),
    enabled=true,
    format=value(cli, "log-format", fallback="ion-binary"),
  )
  defer logs.flush()
  let mount = @host.Mount::memory(
    Map::from_array(plan.sources().map(path => (path, ""))),
  )
  let cancel_file = value(cli, "cancel-file")
  let host = @host.Host::new(
    mount,
    library_build=provider,
    event=fn(event) { logs.event(event) },
    cancelled=fn() {
      @platform.interruption_requested() ||
      (cancel_file != "" && (@platform.kind(cancel_file) catch { _ => 1 }) != 0)
    },
  )
  let result = host.run_content(
    engine,
    plan,
    @host.ContentPublisher::filesystem(parent, plan.output_root),
  )
  for diagnostic in result.report.diagnostics {
    @platform.stderr(
      path + " [" + diagnostic.stage + "]: " + diagnostic.message + "\n",
    )
  }
  for warning in result.report.warnings {
    @platform.stderr("warning: " + warning.message + "\n")
  }
  if result.publication_error is Some(error) {
    @platform.stderr(error + "\n")
  }
  let report : Json = {
    "operation": "generate",
    "target": backend,
    "unitId": unit.id,
    "input": path,
    "output": output,
    "successful": result.successful(),
    "processed": result.report.processed,
    "artifactDetails": result.report.artifacts.map(a => {
      artifact_json({ ..a, source: path, })
    }),
    "projects": result.report.projects.map(p => {
      project_json({ ..p, source: path, })
    }),
    "validated": result.validated.map(validated_json),
    "committed": result.committed,
    "diagnostics": result.report.diagnostics.map(d => {
      diagnostic_json({ ..d, path, })
    }),
    "warnings": result.report.warnings.map(d => diagnostic_json({ ..d, path, })),
    "publicationError": result.publication_error
    .map(Json::string)
    .unwrap_or(Json::null()),
    "cancelled": result.cancelled,
  }
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("result", report)
    Human =>
      for artifact in result.report.artifacts {
        println(artifact.path)
      }
  }
  if result.cancelled {
    130
  } else if result.successful() {
    0
  } else {
    1
  }
}

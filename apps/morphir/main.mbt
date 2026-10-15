///|
fn usage(mode : OutputMode, help_text : String) -> Unit {
  if !(mode is Human) {
    let help = Json::object(
      Map::from_array([
        (
          "commands",
          Json::array(
            [
              "run", "execute", "verify", "conform", "workspace", "project list",
              "toolchain info", "toolchain setup", "toolchain build", "toolchain run",
              "toolchain exec",
            ].map(Json::string),
          ),
        ),
        ("usage", Json::string(help_text)),
        (
          "options",
          Json::array(
            [
              "--project", "--all", "--frontend", "--frontend-provider", "--frontend-profile",
              "--backend", "--target", "--output", "--config", "--file", "--directory",
              "--json", "--json-lines", "--dry-run", "--checkpoint-format", "--validation",
              "--build-provider", "--build-helper", "--sdk", "--build-node", "--component",
              "--help", "--home", "--yes", "--package", "--timeout", "--suite", "--suite-format",
              "--model-format", "--unit-id", "--execution-helper", "--dependency",
              "--node", "--log-file", "--log-format", "--toolchain-pin", "--telemetry-adapter",
              "--otel-binary", "--otel-pin", "--otel-helper", "--otel-endpoint",
              "--otel-protocol", "--otel-flush-timeout", "--log", "--build-mode",
              "--comparison", "--absolute-tolerance", "--relative-tolerance", "--cancel-file",
              "--cases", "--cases-format", "--evaluators", "--require-evaluator",
              "--rust-evaluator", "--rust-evaluator-pin", "--rust-helper", "--receipt",
              "--receipt-format", "--metadata-grants", "--metadata-timeout",
            ].map(Json::string),
          ),
        ),
      ]),
    )
    if mode is JSONLines {
      emit_record("help", help)
    } else {
      println(help.stringify())
    }
    return
  }
  println("Morphir CLI\n" + help_text)
}

///|
fn main {
  let args = @platform.arguments()
  let mut mode = error_output_mode(args)
  let mut status = 0
  try {
    let cli = parse_cli(args)
    mode = if flag(cli, "json-lines") {
      JSONLines
    } else if flag(cli, "json") {
      JSON
    } else {
      Human
    }
    status = command(cli, mode)
  } catch {
    error => {
      let message = match error {
        @toolchain.ToolchainError(message) => message
        _ => @host.error_message(error)
      }
      @platform.stderr(message + "\n")
      print_error(message, mode)
      status = if message == "Cancelled" { 130 } else { 2 }
    }
  }
  @platform.exit(status)
}

///|
fn command(cli : Cli, mode : OutputMode) -> Int raise {
  if cli.help {
    usage(mode, cli.help_text)
    return 0
  }
  if cli.command.has_prefix("toolchain ") {
    return toolchain_command(cli, mode)
  }
  if cli.command == "execute" ||
    cli.command == "verify" ||
    cli.command == "conform" {
    return execution_command(cli, mode)
  }
  let project_list = cli.command == "project list"
  let path = value(cli, "path", fallback=".")
  let selector = value(cli, "project")
  let all = flag(cli, "all")
  let frontends = values(cli, "frontend")
  let targets = values(cli, "target")
  let dry_run = flag(cli, "dry-run")
  let directory = flag(cli, "directory")
  let file = flag(cli, "file")
  let script_path = value(cli, "config")
  let overlay_fields : Map[String, Json] = Map([])
  if !project_list {
    for
      (option, table, key) in [
        ("frontend", "frontend", "language"),
        ("frontend-provider", "frontend", "provider"),
        ("frontend-profile", "frontend", "profile"),
        ("backend", "pipeline", "backend"),
        ("checkpoint-format", "pipeline", "checkpoint_format"),
        ("validation", "pipeline", "validation"),
        ("target", "pipeline", "target"),
        ("build-provider", "pipeline", "build_provider"),
        ("build-helper", "pipeline", "build_helper"),
        ("build-node", "pipeline", "build_node"),
        ("sdk", "pipeline", "sdk"),
        ("home", "pipeline", "compiler_home"),
        ("timeout", "pipeline", "build_timeout"),
        ("component", "pipeline", "components"),
        ("output", "workspace", "out_dir"),
      ] {
      let entries = values(cli, option)
      if !entries.is_empty() {
        let fields = match overlay_fields.get(table) {
          Some(Object(fields)) => fields
          _ => Map([])
        }
        fields[key] = if option == "component" {
          Json::array(entries.map(Json::string))
        } else {
          Json::string(value(cli, option))
        }
        overlay_fields[table] = Json::object(fields)
      }
    }
  }
  let location = @host.locate(path)
  if file && location.file is None {
    raise @config.Invalid("--file requires a file path")
  }
  if directory && location.file is Some(_) {
    raise @config.Invalid("--directory requires a directory path")
  }
  let mount = @host.Mount::filesystem(location.root)
  let environment = @platform.environment()
  let (system, global) = @host.configuration(environment)
  let cancel_path = value(cli, "cancel-file")
  let cancel_file = if cancel_path == "" {
    ""
  } else {
    @metadata_grants.host_path(
      cancel_path,
      @platform.cwd(),
      @platform.system_type(),
    )
  }
  let host = @host.Host::new(mount, environment~, system~, global~, cancelled=fn() {
    cancel_file != "" && (@platform.kind(cancel_file) catch { _ => 1 }) != 0
  })
  let snapshot = host.snapshot()
  let overlay = @config.from_json(Json::object(overlay_fields), origin="CLI")
  let workspace = @workspace.discover(
    snapshot.tree,
    system~,
    global~,
    environment~,
    overlay~,
  )
  for warning in workspace.warnings {
    @platform.stderr("warning: " + warning + "\n")
  }
  if cli.command == "workspace" {
    if !(mode is Human) {
      emit_workspace(workspace.to_json(), mode)
    } else {
      for project in workspace.projects {
        println(
          project.name +
          "\t" +
          (if project.root == "" { "." } else { project.root }),
        )
      }
    }
    return if workspace.projects.any(p => p.error is Some(_)) { 2 } else { 0 }
  }
  let logs = @host.TelemetrySession::local(
    location.root,
    if dry_run || project_list {
      None
    } else {
      values(cli, "log-file").get(0)
    },
    enabled=flag(cli, "log") && !dry_run && !project_list,
    kind="frontend",
    format=value(cli, "log-format", fallback="ion-binary"),
  )
  defer logs.flush()
  let engine = @engine.Engine::new()
    ..register_source_provider(
      @moonbit_frontend.provider(observer=logs.observer()),
    )
    ..register_source_provider(@elm_frontend.provider())
  let grant_file = value(cli, "metadata-grants")
  let grants = if grant_file == "" {
    None
  } else {
    let path = @metadata_grants.host_path(
      grant_file,
      @platform.cwd(),
      @platform.system_type(),
    )
    let format = if path.has_suffix(".json") {
      @metadata_grants.Json
    } else if path.has_suffix(".ionb") {
      @metadata_grants.IonBinary
    } else {
      @metadata_grants.IonText
    }
    Some(
      @metadata_grants.Grants::decode(
        @platform.read_bytes(path),
        format,
        path,
        @platform.system_type(),
      ),
    )
  }
  host.register_process_metadata_provider(
    engine,
    grants,
    location.root,
    @platform.cwd(),
    timeout=metadata_timeout(value(cli, "metadata-timeout", fallback="120000")),
    cancel_file~,
    observer=logs.observer(),
    audit_sink=logs.metadata_audit_sink(),
  )
  let script = if script_path == "" { "" } else { @platform.read(script_path) }
  if project_list {
    return print_projects(
      engine.list_projects(snapshot.engine_host(), workspace, script~),
      frontends,
      targets,
      mode,
    )
  }
  let request = @engine.Request::{
    selector,
    all,
    invocation: location.invocation,
    file: location.file,
    directory: if directory ||
      (
        location.file is None &&
        location.invocation != "" &&
        !workspace.projects.any(p => p.root == location.invocation)
      ) {
      Some(location.invocation)
    } else {
      None
    },
    script,
    overlay,
  }
  let plan = engine.plan(snapshot.engine_host(), workspace, request)
  if dry_run {
    emit_plan(
      plan.sources(),
      plan.destinations(),
      plan.boundaries(),
      mode,
      components=plan.component_boundaries(),
      frontends=plan.source_frontends(),
    )
    return 0
  }
  let publisher = @host.ContentPublisher::filesystem(
    location.root,
    plan.output_root,
  )
  let build_config = @config.merge(workspace.document, overlay)
  let provider = match build_config.text("pipeline.build_provider", "") {
    "" => None
    "process" =>
      Some(
        @host.LibraryBuildProvider::process(
          build_config.text("pipeline.build_node", "node"),
          build_config.text("pipeline.build_helper", ""),
          build_config.text("pipeline.compiler_home", ""),
          Map::from_array([
            ("finos/morphir-sdk", build_config.text("pipeline.sdk", "")),
          ]),
          timeout=build_timeout(
            build_config.text("pipeline.build_timeout", "120000"),
          ),
        ),
      )
    other => raise @config.Invalid("build.unsupported_provider: " + other)
  }
  // Retain the owner used by the effect-free metadata binder during planning.
  let host = { ..host, library_build: provider, }
  let boundaries = plan.boundaries()
  let result = host.run_content(
    engine,
    plan,
    publisher,
    read_bytes=if plan.requires_byte_read() {
      Some(@host.Mount::filesystem_bytes(location.root))
    } else {
      None
    },
  ) catch {
    error => {
      let message = @host.error_message(error)
      @platform.stderr(message + "\n")
      print_error(message, mode)
      return if message == "Cancelled" { 130 } else { 1 }
    }
  }
  for diagnostic in result.report.diagnostics {
    @platform.stderr(
      diagnostic.path +
      " [" +
      diagnostic.stage +
      "]: " +
      diagnostic.message +
      "\n",
    )
  }
  for warning in result.report.warnings {
    @platform.stderr(
      "warning: " +
      warning.path +
      " [" +
      warning.stage +
      "]: " +
      warning.message +
      "\n",
    )
  }
  if result.publication_error is Some(error) {
    @platform.stderr(error + "\n")
  }
  if !(mode is Human) {
    emit_result(
      Json::object(
        Map::from_array([
          ("frontends", Json::array(plan.source_frontends().map(frontend_json))),
          ("boundaries", Json::array(boundaries.map(boundary_json))),
          (
            "components",
            Json::array(plan.component_boundaries().map(component_json)),
          ),
          (
            "artifactDetails",
            Json::array(result.report.artifacts.map(artifact_json)),
          ),
          ("projects", Json::array(result.report.projects.map(project_json))),
          ("validated", Json::array(result.validated.map(validated_json))),
          ("successful", Json::boolean(result.successful())),
          ("processed", Json::number(result.report.processed.to_double())),
          ("committed", Json::array(result.committed.map(Json::string))),
          (
            "publicationDetails",
            Json::array(
              result.committed.map(path => {
                Json::object(
                  Map::from_array([
                    ("path", Json::string(path)),
                    ("status", Json::string("published")),
                  ]),
                )
              }),
            ),
          ),
          (
            "diagnostics",
            Json::array(
              result.report.diagnostics.map(d => {
                Json::object(
                  Map::from_array([
                    ("path", Json::string(d.path)),
                    ("stage", Json::string(d.stage)),
                    ("message", Json::string(d.message)),
                  ]),
                )
              }),
            ),
          ),
          ("warnings", Json::array(result.report.warnings.map(warning_json))),
          (
            "publicationError",
            match result.publication_error {
              Some(s) => Json::string(s)
              None => Json::null()
            },
          ),
          (
            "artifacts",
            Json::array(result.report.artifacts.map(a => Json::string(a.path))),
          ),
        ]),
      ),
      mode,
    )
  } else {
    for boundary in boundaries {
      println(
        boundary.source +
        ": " +
        boundary.input_format +
        " -> " +
        boundary.output_format,
      )
    }
    for artifact in result.report.artifacts {
      println("Accepted " + artifact.path + " (" + artifact.format + ")")
    }
    for validation in result.validated {
      println("Validated " + validation.root + " for " + validation.target)
    }
    for destination in result.committed {
      println("Published " + destination)
    }
    if result.successful() {
      println(
        "Published " + result.report.processed.to_string() + " artifact(s)",
      )
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

///|
fn build_timeout(text : String) -> Int raise {
  match @json.parse(text) {
    Number(n, ..) if n >= 1.0 && n <= 600000.0 && n == n.to_int().to_double() =>
      n.to_int()
    _ => raise @config.Invalid("build.invalid_timeout")
  }
}

///|
fn metadata_timeout(text : String) -> Int raise {
  let value = @json.parse(text) catch {
    _ => raise @config.Invalid("metadata.restore_invalid_deadline")
  }
  match value {
    Number(n, ..) if n >= 6001.0 && n <= 600000.0 && n == n.to_int().to_double() =>
      n.to_int()
    _ => raise @config.Invalid("metadata.restore_invalid_deadline")
  }
}

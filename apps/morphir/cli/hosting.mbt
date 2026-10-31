///|
/// Parsed ownership and immutable run-wide settings shared by the two entries.
pub struct Invocation {
  priv cli : Cli
  priv mode : OutputMode
  priv environment : Map[String, String]
  priv directory : String
  priv root : String
  priv configuration : @config.Document
  priv settings : @diagnostics.Settings
  priv cancel_file : String
  priv command_started : Ref[Bool]
  priv workers : WorkerHosting
}

///|
/// `workers` holds the worker launchers of the entry for this target.
pub fn Invocation::prepare(
  args : Array[String],
  workers~ : WorkerHosting = WorkerHosting::none(),
) -> Invocation raise {
  let cli = parse_cli(args)
  let mode = if flag(cli, "json-lines") {
    JSONLines
  } else if flag(cli, "json") {
    JSON
  } else {
    Human
  }
  let environment = @platform.environment()
  let directory = host_working_directory()
  if cli.help {
    return {
      cli,
      mode,
      environment,
      directory,
      root: directory,
      configuration: @config.empty(),
      settings: { level: Warn, files: Disabled, },
      cancel_file: "",
      command_started: Ref(false),
      workers,
    }
  }
  let input = match cli.command {
    "run" | "workspace" | "project list" => value(cli, "path", fallback=".")
    "compile" => value(cli, "input", fallback=value(cli, "path", fallback="."))
    _ => "."
  }
  let boundary = values(cli, "discovery-boundary").last()
  let location = @host.locate(input, boundary?)
  let options = configuration_controls(cli, location, environment)
  let overlay = match diagnostic_level(cli) {
    Some(level) =>
      Some(
        @config.from_json(
          { "logging": { "level": level.name() } },
          origin="CLI",
        ),
      )
    None => None
  }
  let configuration = @host.run_configuration(
    location,
    environment,
    options,
    overlay?,
  )
  let settings = @diagnostics.Settings::from_config(configuration.framework())
  let selected_cancel = value(cli, "cancel-file")
  let cancel_file = if selected_cancel == "" {
    ""
  } else {
    @metadata_grants.host_path(
      selected_cancel,
      directory,
      @platform.system_type(),
    )
  }
  {
    cli,
    mode,
    environment,
    directory,
    root: location.root,
    configuration,
    settings,
    cancel_file,
    command_started: Ref(false),
    workers,
  }
}

///|
pub fn Invocation::diagnostics(self : Invocation) -> @diagnostics.Settings {
  if self.cli.help {
    { level: Off, files: Disabled, }
  } else {
    self.settings
  }
}

///|
/// The prepared host path, for embedding adapters that poll while MoonBit waits.
pub fn Invocation::cancel_file(self : Invocation) -> String? {
  if self.cancel_file == "" {
    None
  } else {
    Some(self.cancel_file)
  }
}

///|
pub fn Invocation::log_directory(
  self : Invocation,
) -> @sinks.LogDirectory raise {
  @sinks.LogDirectory::from_absolute(
    @lander_core.AbsolutePath::parse(self.root + "/.morphir/logs"),
  )
}

///|
/// Replay only already-owned local arguments. Child argv remains in Cli.forwarded.
fn Invocation::host_arguments(self : Invocation) -> Array[String] {
  if self.cli.help {
    return []
  }
  let args = self.cli.command.split(" ").map(StringView::to_owned).collect()
  for name, enabled in self.cli.flags {
    if enabled && name != "help" && name != "no-banner" {
      args.push("--" + name)
    }
  }
  for name, entries in self.cli.entries {
    if name != "path" {
      for entry in entries {
        args.push("--" + name + "=" + entry)
      }
    }
  }
  if self.cli.entries.get("path") is Some(paths) {
    args.append(paths)
  }
  args
}

///|
priv struct ActiveRun {
  lifetime : @hosting.Lifetime
  logger : &@logging.Logger
  telemetry : Array[() -> Unit]
}

///|
let active_run : Ref[ActiveRun?] = Ref(None)

///|
/// Register the real flush once with the run; standalone command tests retain
/// immediate flushing. Stop hooks drain diagnostics before these callbacks.
fn telemetry_flush(flush : () -> Unit) -> () -> Unit {
  match active_run.val {
    None => flush
    Some(run) => {
      run.telemetry.push(flush)
      () => ()
    }
  }
}

///|
fn drain_telemetry(run : ActiveRun) -> Unit {
  let callbacks = run.telemetry.copy()
  run.telemetry.clear()
  for index = callbacks.length() - 1; index >= 0; index = index - 1 {
    callbacks[index]()
  }
}

///|
fn Invocation::stop_requested(
  self : Invocation,
  ctx : @hosting.Context[Unit],
) -> Bool {
  if self.cancel_file != "" &&
    (@platform.kind(self.cancel_file) catch { _ => 1 }) != 0 {
    ctx.lifetime.stop_application(
      exit_code=@hosting.ExitCode::from_int(130) catch {
        _ => abort("valid exit code")
      },
    )
  }
  ctx.stop_requested()
}

///|
fn cancellation_exit_code() -> Int32 {
  match active_run.val {
    Some(run) =>
      match run.lifetime.stop_reason() {
        Some(Signal(signal)) => signal.exit_code().to_int()
        _ => 130
      }
    None => 130
  }
}

///|
pub fn Invocation::host(
  self : Invocation,
  logger : &@logging.Logger,
  close_diagnostics : async () -> Unit,
) -> @hosting.Host[Unit] raise {
  let scope : Ref[@platform.InterruptionScope?] = Ref(None)
  let processes : Ref[@platform.ProcessScope?] = Ref(None)
  let previous : Ref[ActiveRun?] = Ref(None)
  let run : Ref[ActiveRun?] = Ref(None)
  let entered = Ref(false)
  @lander.cli(
    @lander_core.AppName::parse("morphir"),
    self.host_arguments(),
    env_vars=self.environment,
    working_dir=@lander_core.AbsolutePath::parse(self.directory),
  )
  |> @hosting.command(name => command_spec("", name))
  |> @hosting.skip_env_source
  |> @hosting.configure(builder => {
    builder
    |> @lander_config.add(
      @lander_config.in_memory(
        self.configuration.value(),
        name="Morphir run configuration",
        priority=0,
      ),
    )
  })
  |> @hosting.service(
    "run-resources",
    start=ctx => {
      previous.val = active_run.val
      let resources : ActiveRun = {
        lifetime: ctx.lifetime,
        logger,
        telemetry: [],
      }
      active_run.val = Some(resources)
      run.val = Some(resources)
      let process_logger = @logging.with_category(
        logger, "morphir.host.process",
      )
      processes.val = Some(
        @platform.ProcessScope::install(program => {
          process_logger.debug("Starting child process {program}", [
            Json(program),
          ])
        }),
      )
      scope.val = Some(
        @platform.InterruptionScope::install(() => self.stop_requested(ctx)),
      )
    },
    stop=_ => {
      if scope.val is Some(bound) {
        bound.close()
        scope.val = None
      }
      if processes.val is Some(bound) {
        bound.close()
        processes.val = None
      }
      active_run.val = previous.val
    },
  )
  |> @hosting.service("telemetry", stop=_ => {
    if run.val is Some(resources) {
      drain_telemetry(resources)
    }
  })
  |> @hosting.service(
    "diagnostics",
    start=_ => {
      let configuration_logger = @logging.with_category(
        logger, "morphir.configuration",
      )
      for report in self.configuration.framework().reports() {
        if report.status is Loaded && report.path is Some(path) {
          configuration_logger.debug("Loaded configuration {path}", [Json(path)])
        }
      }
    },
    stop=_ => close_diagnostics(),
  )
  |> @hosting.service("command-state", start=ctx => {
    ctx.lifetime.on_started(() => entered.val = true)
  })
  |> @hosting.error_report((error, code) => {
    if entered.val {
      @platform.stderr(@host.error_message(error) + "\n")
    } else {
      ignore(
        report_command_failure(
          failure_presentation(self.cli.command),
          self.mode,
          error,
          status=code.to_int(),
        ),
      )
    }
  })
  |> @hosting.build(_ => ())
}

///|
pub async fn Invocation::execute(
  self : Invocation,
  ctx : @hosting.Context[Unit],
) -> Unit {
  self.command_started.val = true
  let logger = match active_run.val {
    Some(run) => run.logger
    None => @logging.null_logger()
  }
  let context = {
    ..command_context(self.mode, configuration=self.configuration.framework()),
    logger,
    check_cancelled: fn() raise { ctx.check_cancelled() },
    stop_requested: fn() { ctx.stop_requested() },
    workers: self.workers,
  }
  let status = if self.cli.help {
    help_command(self.cli, self.mode)
  } else {
    dispatch_cli(self.cli, context)
  }
  ctx.lifetime.set_exit_code(@hosting.ExitCode::from_int(status))
}

///|
pub fn startup_failure(
  args : Array[String],
  error : Error,
  status~ : Int32 = 2,
) -> Int32 {
  let parsed = Some(parse_cli(args)) catch { _ => None }
  let presentation = match parsed {
    Some(cli) => failure_presentation(cli.command)
    None =>
      match notebook_error_operation(args) {
        Some(operation) => FailurePresentation::Notebook(operation)
        None => Legacy
      }
  }
  report_command_failure(presentation, error_output_mode(args), error, status~)
}

///|
#cfg(target="wasm")
fn host_working_directory() -> String {
  "/"
}

///|
#cfg(any(target="native", target="js", target="wasm-gc"))
fn host_working_directory() -> String {
  @platform.cwd()
}

///|
/// A clean stop may skip every service and the command. The owning runner
/// supplies its selected code; Morphir still owns its JSON failure schema.
pub fn Invocation::report_unstarted_stop(
  self : Invocation,
  status : Int32,
) -> Unit {
  if !self.command_started.val && (status == 130 || status == 143) {
    self.command_started.val = true
    ignore(
      report_command_failure(
        failure_presentation(self.cli.command),
        self.mode,
        @platform.Interrupted,
        status~,
      ),
    )
  }
}

///|
priv enum FailurePresentation {
  Legacy
  Compilation
  Model
  Notebook(NotebookOperation)
}

///|
priv suberror CommandCancelled

///|
/// The host supplies these run services; command handlers own their result schemas.
priv struct CommandContext {
  mode : OutputMode
  configuration : @lander_config.Config
  logger : &@logging.Logger
  clock : () -> Double
  check_cancelled : () -> Unit raise
  failed : (FailurePresentation, Error) -> Int32
  workers : WorkerHosting
}

///|
fn failure_presentation(command : String) -> FailurePresentation {
  if command == "compile" {
    Compilation
  } else if command == "model inspect" || command == "model export-original" {
    Model
  } else {
    match notebook_operation(command) {
      Some(operation) => Notebook(operation)
      None => Legacy
    }
  }
}

///|
fn command_context(
  mode : OutputMode,
  configuration~ : @lander_config.Config = @config.empty().framework(),
) -> CommandContext {
  {
    mode,
    configuration,
    logger: @logging.null_logger(),
    clock: @platform.monotonic_seconds,
    // Standalone tests and the embedded legacy entry provide no run lifetime.
    check_cancelled: fn() { () },
    failed: fn(presentation, error) {
      report_command_failure(presentation, mode, error)
    },
    workers: WorkerHosting::none(),
  }
}

///|
fn[Req] command_sender(
  command : String,
  handler : (CommandContext, Req) -> Int32 raise,
) -> @mediator_async.Sender[CommandContext, Req, Int32] {
  async_command_sender(command, (context, request) => {
    complete_command(handler(context, request))
  })
}

///|
/// A sender for a handler that awaits its own work, with the same timing,
/// logging, cancellation and failure middleware.
fn[Req] async_command_sender(
  command : String,
  handler : async (CommandContext, Req) -> Int32,
) -> @mediator_async.Sender[CommandContext, Req, Int32] {
  @mediator_async.sender(handler).use_(
    @mediator_async.middleware(async fn(next, context, request) {
      let started = (context.clock)()
      let logger = @logging.with_category(
        context.logger,
        "morphir.cli." + command.replace(old=" ", new="."),
      )
      let scoped = { ..context, logger, }
      let profiles = match context.configuration.profiles() {
        Resolved(resolution) =>
          resolution.active().names().map(name => Json(name.to_string()))
        _ => []
      }
      logger.debug("Starting {Command} with profiles {Profiles}", [
        Json::string(command),
        Json::array(profiles),
      ])
      defer logger.debug("Finished {Command} after {ElapsedMilliseconds} ms", [
        Json::string(command),
        Json::number(((context.clock)() - started) * 1000.0),
      ])
      try {
        (context.check_cancelled)()
        let code = next(scoped, request)
        logger.debug("Command {Command} returned {ExitCode}", [
          Json::string(command),
          Json::number(code.to_double()),
        ])
        code
      } catch {
        error => {
          logger.error(
            "Command {Command} failed",
            [Json::string(command)],
            error~,
          )
          (context.failed)(failure_presentation(command), error)
        }
      }
    }),
  )
}

///|
fn report_command_failure(
  presentation : FailurePresentation,
  mode : OutputMode,
  error : Error,
  status? : Int32,
) -> Int32 {
  let message = match error {
    CommandCancelled | @platform.Interrupted | @hosting.StopRequested =>
      "Cancelled"
    @diagnostics.InvalidLevel(_) as failure => failure.message()
    @diagnostics.InvalidFileFormat(_) as failure => failure.message()
    @lander_core.InvalidAbsolutePath(..) as failure => failure.message()
    @toolchain.ToolchainError(message) => message
    _ => @host.error_message(error)
  }
  let status = status.unwrap_or_else(fn() {
    if error is CommandCancelled ||
      error is @platform.Interrupted ||
      error is @hosting.StopRequested ||
      @platform.interruption_requested() {
      cancellation_exit_code()
    } else if presentation is Compilation {
      1
    } else {
      2
    }
  })
  match presentation {
    Notebook(operation) =>
      notebook_failure(
        operation,
        mode,
        if error is @platform.Interrupted ||
          error is @hosting.StopRequested ||
          error is CommandCancelled {
          "notebook.cancelled"
        } else {
          "notebook.invalid_arguments"
        },
        message,
        status,
      )
    Compilation => {
      @platform.stderr(message + "\n")
      compilation_error(message, mode, status)
      status
    }
    Model => {
      @platform.stderr(message + "\n")
      let report : Json = {
        "successful": false,
        "error": message,
        "code": if error is @platform.Interrupted ||
          error is @hosting.StopRequested {
          "execution.cancelled"
        } else {
          @host.error_code(error)
        },
      }
      match mode {
        JSON => println(report.stringify())
        JSONLines => emit_record("error", report)
        Human => ()
      }
      status
    }
    Legacy => {
      @platform.stderr(message + "\n")
      print_error(message, mode)
      status
    }
  }
}

///|
enum FailurePresentation {
  Legacy
  Compilation
  Notebook(NotebookOperation)
}

///|
suberror CommandCancelled

///|
/// The host supplies these run services; command handlers own their result schemas.
struct CommandContext {
  mode : OutputMode
  logger : &@logging.Logger
  clock : () -> Double
  check_cancelled : () -> Unit raise
  failed : (FailurePresentation, Error) -> Int32
}

///|
fn failure_presentation(command : String) -> FailurePresentation {
  if command == "compile" {
    Compilation
  } else {
    match notebook_operation(command) {
      Some(operation) => Notebook(operation)
      None => Legacy
    }
  }
}

///|
fn command_context(mode : OutputMode) -> CommandContext {
  {
    mode,
    logger: @logging.null_logger(),
    clock: @platform.monotonic_seconds,
    // Existing command adapters retain interruption ownership until the host
    // supplies its lifetime through this seam.
    check_cancelled: fn() { () },
    failed: fn(presentation, error) {
      report_command_failure(presentation, mode, error)
    },
  }
}

///|
fn[Req] command_sender(
  command : String,
  handler : (CommandContext, Req) -> Int32 raise,
) -> @mediator.Sender[CommandContext, Req, Int32] {
  @mediator.sender(handler).use_(
    @mediator.middleware(fn(next, context, request) {
      let started = (context.clock)()
      let logger = @logging.with_category(
        context.logger,
        "morphir.cli." + command.replace(old=" ", new="."),
      )
      let scoped = { ..context, logger, }
      logger.debug("Starting {Command}", [Json::string(command)])
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
) -> Int32 {
  let message = match error {
    CommandCancelled => "Cancelled"
    @toolchain.ToolchainError(message) => message
    _ => @host.error_message(error)
  }
  let status = if error is CommandCancelled || message == "Cancelled" {
    130
  } else if presentation is Compilation {
    1
  } else {
    2
  }
  match presentation {
    Notebook(operation) =>
      notebook_failure(
        operation, mode, "notebook.invalid_arguments", message, status,
      )
    Compilation => {
      @platform.stderr(message + "\n")
      compilation_error(message, mode, status)
      status
    }
    Legacy => {
      @platform.stderr(message + "\n")
      print_error(message, mode)
      status
    }
  }
}

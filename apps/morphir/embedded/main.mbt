///|
#cfg(target="wasm-gc")
fn main {
  let args = @platform.arguments()
  let status = gc_run(args) catch { error => @cli.startup_failure(args, error) }
  @platform.exit(status)
}

///|
#cfg(target="wasm")
fn main {
  let args = @platform.arguments()
  let status = embedded_run(args) catch {
    error => @cli.startup_failure(args, error)
  }
  @platform.exit(status)
}

///|
#cfg(target="wasm")
fn embedded_run(args : Array[String]) -> Int32 raise {
  let invocation = @cli.Invocation::prepare(args)
  let settings = invocation.diagnostics()
  if !(settings.level is Off) && settings.files is Enabled(_) {
    raise @config.Invalid(
      "diagnostics.file_logging_unavailable: rolling files require the native or JS process host",
    )
  }
  let logger = if settings.level is Off {
    @logging.null_logger()
  } else {
    let initial = @platform.utc_milliseconds()
    let validated = @formatting.LogTimestamp::from_epoch_millis(initial)
    let started = @platform.monotonic_seconds()
    @diagnostics.text_logger(settings.level, @platform.stderr, () => {
      let elapsed = ((@platform.monotonic_seconds() - started).max(0.0) * 1000.0).to_int64()
      @formatting.LogTimestamp::from_epoch_millis(initial + elapsed) catch {
        _ => validated
      }
    })
  }
  let host = invocation.host(logger, () => ())
  let status = @hosting.run_embedded(host, ctx => invocation.execute(ctx))
    .exit_code()
    .to_int()
  invocation.report_unstarted_stop(status)
  status
}

///|
#cfg(target="wasm-gc")
fn gc_run(args : Array[String]) -> Int32 raise {
  let invocation = @cli.Invocation::prepare(args)
  // UTC logging waits for the maintainer's decision on the unchanged host ABI.
  let host = invocation.host(@logging.null_logger(), () => ())
  let outcome = @hosting.run_embedded(
    host,
    ctx => invocation.execute(ctx),
    stop_probe=@platform.external_interruption_requested,
  )
  let status = match outcome.stop_reason() {
    Embedder => 130
    _ => outcome.exit_code().to_int()
  }
  invocation.report_unstarted_stop(status)
  status
}

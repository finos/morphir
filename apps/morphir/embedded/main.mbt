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
  let logger = embedded_logger(invocation.diagnostics())
  let host = invocation.host(logger, () => ())
  let status = @hosting.run_embedded(host, ctx => invocation.execute(ctx))
    .exit_code()
    .to_int()
  invocation.report_unstarted_stop(status)
  status
}

///|
fn embedded_logger(settings : @diagnostics.Settings) -> &@logging.Logger raise {
  if !(settings.level is Off) && settings.files is Enabled(_) {
    raise @config.Invalid(
      "diagnostics.file_logging_unavailable: rolling files require the native or JS process host",
    )
  }
  if settings.level is Off {
    @logging.null_logger()
  } else {
    let initial = @platform.utc_milliseconds()
    let validated = @formatting.LogTimestamp::from_epoch_millis(initial) catch {
      _ => raise @config.Invalid("diagnostics.invalid_utc_clock")
    }
    let started = @platform.monotonic_seconds()
    @diagnostics.text_logger(settings.level, @platform.stderr, () => {
      let elapsed = ((@platform.monotonic_seconds() - started).max(0.0) * 1000.0).to_int64()
      @formatting.LogTimestamp::from_epoch_millis(initial + elapsed) catch {
        _ => validated
      }
    })
  }
}

///|
#cfg(target="wasm-gc")
fn gc_run(args : Array[String]) -> Int32 raise {
  let invocation = @cli.Invocation::prepare(args)
  let finalized = Ref(true)
  let status = gc_registered_run(invocation, finalized)
  if finalized.val || status != 0 {
    status
  } else {
    1
  }
}

///|
#cfg(target="wasm-gc")
fn gc_registered_run(
  invocation : @cli.Invocation,
  finalized : Ref[Bool],
) -> Int32 raise {
  let cancel_file = invocation.cancel_file()
  if cancel_file is Some(path) {
    @platform.register_cancel_file(path)
  }
  defer (if cancel_file is Some(_) {
    @platform.register_cancel_file("") catch {
      _ => {
        finalized.val = false
        @platform.stderr("cancellation.cancel_file_cleanup_failed\n")
      }
    }
  })
  let logger = embedded_logger(invocation.diagnostics())
  let host = invocation.host(logger, () => ())
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

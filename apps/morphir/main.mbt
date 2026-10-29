///|
async fn main {
  let args = @platform.arguments()
  let invocation = @cli.Invocation::prepare(args) catch {
    error => {
      @platform.exit(@cli.startup_failure(args, error))
      return
    }
  }
  let settings = invocation.diagnostics().session(invocation.log_directory()) catch {
      error => {
        @platform.exit(@cli.startup_failure(args, error))
        return
      }
    }
  let signals = parent_signal_probe()
  @bridge.run_with_session(
    settings,
    session => invocation.host(session.logger(), () => ignore(session.close())),
    ctx => invocation.execute(ctx),
    signals?,
  ) catch {
    error => @platform.exit(@cli.startup_failure(args, error, status=1))
  }
}

///|
#cfg(target="js")
extern "js" fn parent_signal_available() -> Bool =
  #| () => globalThis.__morphirInterrupt instanceof Int32Array

///|
#cfg(target="js")
extern "js" fn parent_signal_code() -> Int32 =
  #| () => Atomics.load(globalThis.__morphirInterrupt, 0)

///|
#cfg(target="js")
fn parent_signal_probe() -> @hosting.SignalProbe? {
  if !parent_signal_available() {
    return None
  }
  Some(
    @hosting.SignalProbe::new(() => {
      match parent_signal_code() {
        1 => Some(Interrupt)
        2 => Some(Terminate)
        3 => Some(Quit)
        _ => None
      }
    }),
  )
}

///|
#cfg(target="native")
fn parent_signal_probe() -> @hosting.SignalProbe? {
  None
}

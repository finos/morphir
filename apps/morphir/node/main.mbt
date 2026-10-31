///|
/// The Node entry of the npm package. It starts process workers with the
/// Node process launcher.
async fn main {
  let args = @platform.arguments()
  let invocation = @cli.Invocation::prepare(args, workers=worker_hosting()) catch {
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
    completed=(_, selected) => {
      invocation.report_unstarted_stop(selected.to_int())
    },
  ) catch {
    error => @platform.exit(@cli.startup_failure(args, error, status=1))
  }
}

///|
/// A Node host on a platform without a Morphir release starts no workers.
fn worker_hosting() -> @cli.WorkerHosting {
  match @node_worker.host_machine() {
    Some(machine) =>
      @cli.WorkerHosting::new(
        Node(machine),
        process=@node_worker.NodeProcessLauncher::new(),
        wasm=@thread_worker.ThreadLauncher::bundled(),
      )
    None => @cli.WorkerHosting::none()
  }
}

///|
extern "js" fn parent_signal_available() -> Bool =
  #| () => globalThis.__morphirInterrupt instanceof Int32Array

///|
extern "js" fn parent_signal_code() -> Int32 =
  #| () => Atomics.load(globalThis.__morphirInterrupt, 0)

///|
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

///|
/// The native entry. It starts process workers with the native process
/// launcher.
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
  @bridge.run_with_session(
    settings,
    session => invocation.host(session.logger(), () => ignore(session.close())),
    ctx => invocation.execute(ctx),
    completed=(_, selected) => {
      invocation.report_unstarted_stop(selected.to_int())
    },
  ) catch {
    error => @platform.exit(@cli.startup_failure(args, error, status=1))
  }
}

///|
/// A host on a platform without a Morphir release starts no workers.
fn worker_hosting() -> @cli.WorkerHosting {
  match @native_worker.host_machine() {
    Some(machine) =>
      @cli.WorkerHosting::new(
        Native(machine),
        process=@native_worker.ProcessLauncher::new(),
      )
    None => @cli.WorkerHosting::none()
  }
}

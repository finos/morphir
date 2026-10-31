///|
/// The native entry. It starts process workers with the native process
/// launcher and WASM workers in its own worker mode.
async fn main {
  let args = @platform.arguments()
  // The worker mode serves one WASM guest on stdio, outside the CLI host:
  // its stdout carries only MEP frames.
  if @wasm_worker.is_worker_invocation(args) {
    @platform.exit(@wasm_worker.serve_worker(args, stamp=build_stamp()))
    return
  }
  let wasm = @wasm_worker.WasmProcessLauncher::new(stamp=build_stamp())
  // The staged copy of this executable lives until the CLI is done.
  defer wasm.release()
  let invocation = @cli.Invocation::prepare(args, workers=worker_hosting(wasm)) catch {
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
/// The version and the git commit of this build, from the generated
/// `build_stamp.mbt`.
fn build_stamp() -> @wasm_worker.BuildStamp {
  @wasm_worker.BuildStamp::new(version=build_version, commit=build_commit)
}

///|
/// A host on a platform without a Morphir release starts no workers.
fn worker_hosting(
  wasm : @wasm_worker.WasmProcessLauncher,
) -> @cli.WorkerHosting {
  match @native_worker.host_machine() {
    Some(machine) =>
      @cli.WorkerHosting::new(
        Native(machine),
        process=@native_worker.ProcessLauncher::new(),
        wasm~,
      )
    None => @cli.WorkerHosting::none()
  }
}

///|
extern "C" fn host_machine_ffi() -> Int32 = "morphir_worker_host_machine"

///|
/// The machine that this host runs on, or `None` where the host has no
/// process worker support. The operating system and the architecture are
/// those of this executable; on Linux the C libraries are those whose
/// dynamic loaders the machine has, so a static musl host on a glibc machine
/// runs gnu artifacts.
pub fn host_machine() -> @worker.Machine? {
  let (os, arch) : (@worker.Os, @worker.Arch) = match host_machine_ffi() {
    1 => (MacOs, Aarch64)
    2 => (MacOs, X86_64)
    3 => (Linux, Aarch64)
    4 => (Linux, X86_64)
    5 => (Windows, Aarch64)
    6 => (Windows, X86_64)
    _ => return None
  }
  Some(machine_under("", os, arch))
}

///|
/// The machine of `os` and `arch` whose loader paths are under `root`, the
/// file-system root for a real host.
fn machine_under(
  root : String,
  os : @worker.Os,
  arch : @worker.Arch,
) -> @worker.Machine {
  @worker.Machine::detect(os, arch, present=path => file_present(root + path))
}

///|
/// Starts process workers on Linux, macOS and Windows. Each worker runs a
/// verified private copy of its artifact, in its own process group or job
/// object, with an empty environment and an empty private working directory.
pub struct ProcessLauncher {
  priv staging_root : String?
  priv grace_ms : Int32
  priv confirm_ms : Int32
}

///|
/// `staging_root` is where `launch` makes each worker's private directory;
/// without it, the system's temporary directory. `grace_ms` is how long
/// `close` waits for a worker to exit after `exit`; `confirm_ms` bounds the
/// confirmation that a stopped tree is gone.
pub fn ProcessLauncher::new(
  staging_root? : String,
  grace_ms~ : Int32 = @shared.EXIT_GRACE_MS,
  confirm_ms~ : Int32 = @shared.STOP_CONFIRM_MS,
) -> ProcessLauncher {
  { staging_root, grace_ms, confirm_ms, }
}

///|
/// Starts a staged artifact with `args`, forwarded unchanged. The channel
/// refuses a request frame above `limits.request_bytes` and a response body
/// above `limits.response_bytes`.
pub async fn ProcessLauncher::start(
  self : ProcessLauncher,
  staged : @shared.StagedArtifact,
  args : Array[String],
  limits~ : @worker.Limits = @worker.Limits::host(),
) -> ProcessChannel {
  // Until the channel is returned, any way out removes the private directory;
  // `spawn` has stopped the worker by then.
  let mut handed_over = false
  defer (if !handed_over { @async.protect_from_cancel(() => unstage(staged)) })
  let worker = spawn(staged, args)
  handed_over = true
  let channel = ProcessChannel::new(
    worker,
    staged,
    limits,
    grace_ms=self.grace_ms,
    confirm_ms=self.confirm_ms,
  )
  // A cancellation during protected work takes effect here. The caller has
  // then returned without the channel, so the `defer` stops the worker and
  // removes its directory.
  let mut returned = false
  defer (if !returned {
    @async.protect_from_cancel(() => ignore(channel.abort(Cancelled)))
  })
  @async.pause()
  returned = true
  channel
}

///|
pub extend ProcessLauncher with @worker.Launcher::{launch}

///|
/// Checks that the specification names a process for this platform, stages
/// the artifact and starts it with the session's frame limits. A cancelled
/// launch leaves no process and no private directory.
pub impl @worker.Launcher for ProcessLauncher with fn launch(self, spec, limits) {
  guard spec.runtime is Process(platform~, args~) else {
    raise @worker.LaunchError::RuntimeUnavailable(supported=[
      @worker.RuntimeKind::Process,
    ])
  }
  guard host_machine() is Some(machine) && machine.runs(platform) else {
    raise @worker.LaunchError::PlatformMismatch(platform)
  }
  self.start(stage(spec.artifact, root?=self.staging_root), args, limits~)
}

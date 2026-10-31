///|
extern "C" fn host_platform_ffi() -> Int32 = "morphir_worker_host_platform"

///|
/// The platform that this host runs on, or `None` where the host has no
/// process worker support.
pub fn host_platform() -> @worker.Platform? {
  match host_platform_ffi() {
    1 => Some(Aarch64AppleDarwin)
    2 => Some(X86_64AppleDarwin)
    3 => Some(Aarch64UnknownLinuxGnu)
    4 => Some(X86_64UnknownLinuxGnu)
    5 => Some(Aarch64UnknownLinuxMusl)
    6 => Some(X86_64UnknownLinuxMusl)
    7 => Some(Aarch64PcWindowsMsvc)
    8 => Some(X86_64PcWindowsMsvc)
    _ => None
  }
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
  guard host_platform() is Some(host) && host == platform else {
    raise @worker.LaunchError::PlatformMismatch(platform)
  }
  self.start(stage(spec.artifact, root?=self.staging_root), args, limits~)
}

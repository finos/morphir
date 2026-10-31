///|
fn ArtifactRead::problem(self : ArtifactRead) -> @worker.ArtifactProblem? {
  match self.problem_code() {
    0 => None
    1 => Some(SymbolicLink)
    2 => Some(NotRegularFile)
    3 => Some(TooLarge)
    _ =>
      Some(
        Unreadable(
          detail=match self.detail() {
            "" => None
            detail => Some(detail)
          },
        ),
      )
  }
}

///|
/// Reads the artifact without following a link, checks the digest of the
/// bytes it read and writes them to a new private directory. The worker
/// runs that copy, so a later change to the original path does not change
/// what runs. The reads and writes do not block the event loop, and they
/// finish even when the task is cancelled; the caller then removes the copy.
pub async fn stage(
  artifact : @worker.ArtifactRef,
) -> @process.StagedArtifact raise @worker.LaunchError {
  guard artifact.source is File(path) else {
    raise RuntimeUnavailable(supported=[Process])
  }
  let read = read_artifact(path.to_string(), @process.ARTIFACT_LIMIT_BYTES).wait() catch {
    error => raise ArtifactUnreadable(Unreadable(detail=Some("\{error}")))
  }
  if read.problem() is Some(problem) {
    raise ArtifactUnreadable(problem)
  }
  let verified = @process.VerifiedArtifact::check(read.bytes(), artifact)
  let style = host_path_style()
  let directory = write_private_copy(
    verified.copy_name(style),
    verified.bytes(),
    @process.STAGED_BIN_DIRECTORY,
    @process.STAGED_WORK_DIRECTORY,
  ).wait() catch {
    _ => ""
  }
  guard directory != "" else {
    raise LaunchFailed("cannot write the private copy of the artifact")
  }
  verified.stage_in(directory~, style~)
}

///|
/// The machine that the Node host runs on, or `None` when Node runs on a
/// platform that has no Morphir release. On Linux the C libraries are those
/// whose dynamic loaders the machine has, whatever Node itself links. A
/// command-line host uses it to make its `HostPlatform::Node`.
pub fn host_machine() -> @worker.Machine? {
  let (os, arch) : (@worker.Os, @worker.Arch) = match host_machine_code() {
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
fn host_path_style() -> @worker.PathStyle {
  if host_is_windows() {
    Windows
  } else {
    Posix
  }
}

///|
/// Starts process workers through Node's `child_process`, for the npm CLI.
pub struct NodeProcessLauncher {}

///|
pub fn NodeProcessLauncher::new() -> NodeProcessLauncher {
  NodeProcessLauncher::{ }
}

///|
pub extend NodeProcessLauncher with @worker.Launcher::{launch}

///|
/// Refuses a WASM runtime, an artifact in memory and a platform that the
/// machine cannot run, then stages the artifact and starts the verified copy. The channel
/// checks frames against the session's limits.
pub impl @worker.Launcher for NodeProcessLauncher with fn launch(
  _self,
  spec,
  limits,
) {
  guard spec.runtime is Process(platform~, args~) else {
    raise @worker.LaunchError::RuntimeUnavailable(supported=[Process])
  }
  guard host_machine() is Some(machine) && machine.runs(platform) else {
    raise @worker.LaunchError::PlatformMismatch(platform)
  }
  NodeProcessChannel::start(stage(spec.artifact), args, limits~)
}

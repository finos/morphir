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
  let directory = write_private_copy(
    verified.file_name(),
    verified.bytes(),
    @process.STAGED_BIN_DIRECTORY,
    @process.STAGED_WORK_DIRECTORY,
  ).wait() catch {
    _ => ""
  }
  guard directory != "" else {
    raise LaunchFailed("cannot write the private copy of the artifact")
  }
  verified.stage_in(directory~, style=host_path_style())
}

///|
/// The host's release platform, if it has one.
fn host_platform() -> @worker.Platform? {
  Some(@worker.Platform::parse(host_triple())) catch {
    _ => None
  }
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
/// Refuses a WASM runtime, an artifact in memory and a platform other than the
/// host's, then stages the artifact and starts the verified copy. The channel
/// checks frames against the session's limits.
pub impl @worker.Launcher for NodeProcessLauncher with fn launch(
  _self,
  spec,
  limits,
) {
  guard spec.runtime is Process(platform~, args~) else {
    raise @worker.LaunchError::RuntimeUnavailable(supported=[Process])
  }
  guard host_platform() == Some(platform) else {
    raise @worker.LaunchError::PlatformMismatch(platform)
  }
  NodeProcessChannel::start(stage(spec.artifact), args, limits~)
}

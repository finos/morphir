///|
#cfg(not(platform="windows"))
const SEPARATOR : String = "/"

///|
#cfg(platform="windows")
const SEPARATOR : String = "\\"

///|
#cfg(not(platform="windows"))
let path_style : @worker.PathStyle = Posix

///|
#cfg(platform="windows")
let path_style : @worker.PathStyle = Windows

///|
/// Reads a file artifact through a descriptor that does not follow a link,
/// checks the SHA-256 of the bytes it read and writes those bytes to a new
/// private directory: `bin/<name>`, executable only by the host's user, and an
/// empty `work` directory. A later change to the original path does not change
/// what runs. A refusal or a cancellation leaves nothing behind.
///
/// The private directory is a new directory in the system's temporary
/// directory, or in `root` when it is given.
pub async fn stage(
  artifact : @worker.ArtifactRef,
  root? : String,
) -> @shared.StagedArtifact {
  guard artifact.source is File(path) else {
    raise @worker.LaunchError::RuntimeUnavailable(supported=[
      @worker.RuntimeKind::Process,
    ])
  }
  let verified = @shared.VerifiedArtifact::check(
    read_artifact(path.to_string()),
    artifact,
  )
  // A cancelled `mkdir` may still make the directory, so it is not
  // cancelled either.
  let directory = @async.protect_from_cancel(() => {
    match root {
      None => @fs.tmpdir(prefix="morphir-worker-")
      Some(root) => private_directory(root)
    }
  })
  let staged = verified.stage_in(directory~, style=path_style)
  // Until the staged artifact is returned, any way out (an error or a
  // cancellation) removes the directory.
  let mut staged_out = false
  defer (if !staged_out {
    @async.protect_from_cancel(() => remove_directory(directory))
  })
  // A cancelled file job may still finish in a worker thread, after a
  // removal. So the writes are not cancelled.
  @async.protect_from_cancel(() => {
    @fs.mkdir(
      directory + SEPARATOR + @shared.STAGED_BIN_DIRECTORY,
      permission=0o700,
    )
    @fs.mkdir(staged.working_directory(), permission=0o700)
    @fs.write_file(
      staged.executable(),
      verified.bytes(),
      create_mode=CreateNew,
      permission=0o700,
    )
  })
  // A cancellation during the writes takes effect here, and the `defer`
  // removes the directory: a caller such as `with_timeout_opt` has already
  // returned without it.
  @async.pause()
  staged_out = true
  staged
}

///|
let private_directories : Ref[Int32] = Ref(0)

///|
/// Makes a new directory in `root` that only the host's user can use.
async fn private_directory(root : String) -> String {
  while true {
    private_directories.val += 1
    let path = root +
      SEPARATOR +
      "morphir-worker-\{@async.now()}-\{private_directories.val}"
    if !@fs.exists(path) {
      @fs.mkdir(path, permission=0o700)
      return path
    }
  }
  panic()
}

///|
async fn remove_directory(directory : String) -> Unit noraise {
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}

///|
/// Removes the private directory of a staged artifact. A launcher calls it
/// only after it confirmed that the worker's tree stopped.
pub async fn unstage(staged : @shared.StagedArtifact) -> Unit noraise {
  remove_directory(staged.directory())
}

///|
/// Removes the private directory of a staged artifact, and tries again for
/// `REMOVE_RETRY_MS` while a file in it is still in use. Returns whether the
/// directory is gone.
async fn remove_staged(staged : @shared.StagedArtifact) -> Bool noraise {
  let directory = staged.directory()
  let deadline = @async.now() + @shared.REMOVE_RETRY_MS.to_int64()
  while true {
    remove_directory(directory)
    let exists = @fs.exists(directory) catch { _ => true }
    if !exists {
      return true
    }
    if @async.now() >= deadline {
      return false
    }
    @async.sleep(20)
  }
  false
}

///|
extern "C" fn executable_path_ffi() -> Bytes = "morphir_wasm_worker_executable_path"

///|
/// The path of the running executable: `/proc/self/exe` on Linux, the real
/// path of the executable on macOS and Windows.
fn executable_path() -> String raise @worker.LaunchError {
  let bytes = executable_path_ffi()
  guard bytes.length() > 0 else {
    raise LaunchFailed("the path of the CLI executable is not known")
  }
  @utf8.decode(bytes) catch {
    _ => raise LaunchFailed("the path of the CLI executable is not UTF-8")
  }
}

///|
/// Where the WASM launcher finds the executable that has the worker mode.
pub(all) enum WorkerExecutable {
  /// The running CLI itself.
  Own
  /// Another executable with the same worker mode, for tests.
  At(String)
}

///|
/// The CLI's executable, hashed and staged once for the life of the process:
/// a private directory with the copy at `bin/<name>`.
priv struct OwnExecutable {
  verified : @shared.VerifiedArtifact
  directory : String
  path : String
}

///|
/// Starts WASM workers on native (WASM-2). Each worker is the CLI's own
/// executable in its worker mode, started as a process worker. When the
/// process first needs a worker, the launcher reads the executable, hashes
/// the bytes it read and writes them to a private copy; every worker runs
/// that copy, and the launcher keeps it and its digest until `release`. Each
/// worker gets its own private directory with the module and an empty
/// `work` directory. Before it starts a worker, the launcher classifies the
/// module, checks its features and caps its memory, so a refusal costs no
/// process.
pub struct WasmProcessLauncher {
  priv process : @process.ProcessLauncher
  priv staging_root : String?
  priv executable : WorkerExecutable
  priv identity : BuildIdentity
  priv call : @guest.CallBounds?
  priv lock : @async.Mutex
  priv mut own : OwnExecutable?
}

///|
/// `stamp` is the CLI build's stamp. `executable`, `identity` and `call` are
/// for tests: another executable with the worker mode, the identity that the
/// host passes instead of the stamp's, and call bounds other than those of
/// the profile.
pub fn WasmProcessLauncher::new(
  stamp~ : BuildStamp,
  staging_root? : String,
  executable~ : WorkerExecutable = Own,
  identity? : BuildIdentity,
  call? : @guest.CallBounds,
  grace_ms~ : Int32 = @shared.EXIT_GRACE_MS,
  confirm_ms~ : Int32 = @shared.STOP_CONFIRM_MS,
) -> WasmProcessLauncher {
  {
    process: @process.ProcessLauncher::new(
      staging_root?,
      grace_ms~,
      confirm_ms~,
    ),
    staging_root,
    executable,
    identity: identity.unwrap_or(BuildIdentity::current(stamp)),
    call,
    lock: @async.Mutex(),
    own: None,
  }
}

///|
/// The bytes of the module that a specification names, checked against its
/// SHA-256.
async fn module_bytes(artifact : @worker.ArtifactRef) -> Bytes {
  let bytes = match artifact.source {
    Memory(bytes) => bytes
    File(path) =>
      @fs.read_file(path.to_string()).binary() catch {
        error =>
          raise @worker.LaunchError::ArtifactUnreadable(
            Unreadable(detail=Some(@debug.to_string(error))),
          )
      }
  }
  @shared.VerifiedArtifact::check(bytes, artifact).bytes()
}

///|
/// Reads the executable with the worker mode. On macOS and Windows the path
/// must name a regular file.
async fn WasmProcessLauncher::read_executable(
  self : WasmProcessLauncher,
) -> (String, Bytes) {
  let path = match self.executable {
    Own => executable_path()
    At(path) => path
  }
  if !path.has_prefix("/proc/") {
    let kind = @fs.kind(path, follow_symlink=false) catch {
      _ => raise @worker.LaunchError::ArtifactUnreadable(NotRegularFile)
    }
    guard kind is Regular else {
      raise @worker.LaunchError::ArtifactUnreadable(NotRegularFile)
    }
  }
  let bytes = @fs.read_file(path).binary() catch {
    error =>
      raise @worker.LaunchError::ArtifactUnreadable(
        Unreadable(detail=Some(@debug.to_string(error))),
      )
  }
  (path, bytes)
}

///|
#cfg(platform="windows")
let path_style : @worker.PathStyle = Windows

///|
#cfg(not(platform="windows"))
let path_style : @worker.PathStyle = Posix

///|
#cfg(platform="windows")
let separator : String = "\\"

///|
#cfg(not(platform="windows"))
let separator : String = "/"

///|
let private_directories : Ref[Int32] = Ref(0)

///|
/// A new directory that only the host's user can use, in the system's
/// temporary directory or in the staging root.
async fn WasmProcessLauncher::private_directory(
  self : WasmProcessLauncher,
) -> String {
  @async.protect_from_cancel(() => {
    match self.staging_root {
      None => @fs.tmpdir(prefix="morphir-wasm-worker-")
      Some(root) => {
        private_directories.val += 1
        let directory = root +
          separator +
          "morphir-wasm-worker-\{@async.now()}-\{private_directories.val}"
        @fs.mkdir(directory, permission=0o700)
        directory
      }
    }
  })
}

///|
async fn remove_directory(directory : String) -> Unit noraise {
  @fs.rmdir(directory, recursive=true) catch {
    _ => ()
  }
}

///|
/// The staged copy of the CLI's executable: hashed and written on the first
/// call, then the same copy for the life of the process.
async fn WasmProcessLauncher::own_executable(
  self : WasmProcessLauncher,
) -> OwnExecutable {
  self.lock.acquire()
  defer self.lock.release()
  if self.own is Some(own) {
    return own
  }
  let (path, executable) = self.read_executable()
  let reference = @worker.ArtifactRef::new(
    File(
      @worker.ArtifactPath::parse(path, path_style) catch {
        _ => raise @worker.LaunchError::LaunchFailed("invalid executable path")
      },
    ),
    @worker.Sha256::of(executable),
  )
  let verified = @shared.VerifiedArtifact::check(executable, reference)
  let directory = self.private_directory()
  let bin = directory + separator + @shared.STAGED_BIN_DIRECTORY
  let copy = bin + separator + verified.file_name()
  let mut done = false
  defer (if !done {
    @async.protect_from_cancel(() => remove_directory(directory))
  })
  @async.protect_from_cancel(() => {
    @fs.mkdir(bin, permission=0o700)
    @fs.write_file(copy, executable, create_mode=CreateNew, permission=0o700)
  })
  @async.pause()
  done = true
  let own = { verified, directory, path: copy, }
  self.own = Some(own)
  own
}

///|
/// Removes the staged copy of the executable. The CLI calls it when it has
/// stopped its workers; a later launch stages a new copy. A process that
/// ends without it leaves the copy in its temporary directory.
pub async fn WasmProcessLauncher::release(
  self : WasmProcessLauncher,
) -> Unit noraise {
  self.lock.acquire()
  defer self.lock.release()
  if self.own is Some(own) {
    self.own = None
    @async.protect_from_cancel(() => remove_directory(own.directory)) catch {
      _ => ()
    }
  }
}

///|
/// Writes a worker's private directory: `bin/module.wasm` and an empty
/// `work` directory, usable only by the host's user. The worker runs the
/// staged copy of the executable from there.
async fn WasmProcessLauncher::stage(
  self : WasmProcessLauncher,
  module_ : Bytes,
) -> (@shared.StagedArtifact, String) {
  let own = self.own_executable()
  let directory = self.private_directory()
  let staged = own.verified.staged(
    directory~,
    executable=own.path,
    working_directory=directory + separator + @shared.STAGED_WORK_DIRECTORY,
  )
  let module_path = directory +
    separator +
    @shared.STAGED_BIN_DIRECTORY +
    separator +
    "module.wasm"
  let mut done = false
  defer (if !done {
    @async.protect_from_cancel(() => @process.unstage(staged))
  })
  @async.protect_from_cancel(() => {
    @fs.mkdir(
      directory + separator + @shared.STAGED_BIN_DIRECTORY,
      permission=0o700,
    )
    @fs.mkdir(staged.working_directory(), permission=0o700)
    @fs.write_file(
      module_path,
      module_,
      create_mode=CreateNew,
      permission=0o600,
    )
  })
  @async.pause()
  done = true
  (staged, module_path)
}

///|
pub extend WasmProcessLauncher with @worker.Launcher::{launch}

///|
/// Checks and stages a WASM specification and starts the worker mode with
/// the session's frame limits. A refusal of the module comes before any
/// process starts.
pub impl @worker.Launcher for WasmProcessLauncher with fn launch(
  self,
  spec,
  limits,
) {
  guard spec.runtime is Wasm(abi~) else {
    raise @worker.LaunchError::RuntimeUnavailable(supported=[Wasm])
  }
  let bytes = module_bytes(spec.artifact)
  let prepared = @wasm.PreparedModule::prepare(bytes, declared?=abi)
  if @guest.missing_feature(bytes) is Some(feature) {
    raise @worker.LaunchError::WasmFeatureUnsupported(feature=Some(feature))
  }
  let (staged, module_path) = self.stage(bytes)
  let options : WorkerOptions = {
    abi: prepared.abi,
    module_path,
    build_identity: self.identity,
    request_bytes: limits.request_bytes,
    response_bytes: limits.response_bytes,
    call: self.call,
    memory_pages: None,
    json: true,
  }
  let channel = self.process.start(
    staged,
    ["extension", "worker", ..options.to_args()],
    limits~,
  )
  WasmProcessChannel::{ inner: channel, }
}

///|
/// The host end of a native WASM worker: a process channel that reads the
/// worker's report when its stdout ends, and raises the guest fault or the
/// refusal that the report names.
pub struct WasmProcessChannel {
  priv inner : @process.ProcessChannel
}

///|
/// The error for a worker whose stream ended: the fault or refusal of its
/// report, or `error` when it reported neither.
async fn WasmProcessChannel::ended(
  self : WasmProcessChannel,
  error : @worker.ChannelError,
) -> @worker.ChannelError {
  let stop = @async.protect_from_cancel(() => self.inner.close())
  @guest.WorkerEvent::ending_in(stop.stderr.bytes()).unwrap_or(error)
}

///|
pub extend WasmProcessChannel with @worker.Channel::{
  send,
  receive,
  close,
  abort,
  bounds,
}

///|
pub impl @worker.Channel for WasmProcessChannel with fn send(self, message) {
  self.inner.send(message) catch {
    @worker.WorkerClosed => raise self.ended(WorkerClosed)
    @worker.TransportFailed(text) => raise self.ended(TransportFailed(text))
    error => raise error
  }
}

///|
pub impl @worker.Channel for WasmProcessChannel with fn receive(self) {
  self.inner.receive() catch {
    @worker.WorkerClosed => raise self.ended(WorkerClosed)
    error => raise error
  }
}

///|
pub impl @worker.Channel for WasmProcessChannel with fn close(self) {
  self.inner.close()
}

///|
pub impl @worker.Channel for WasmProcessChannel with fn abort(self, reason) {
  self.inner.abort(reason)
}

///|
/// The native engine enforces the memory ceiling, the instruction budget and
/// the per-call deadline.
pub impl @worker.Channel for WasmProcessChannel with fn bounds(_) {
  Some(@guest.engine_bounds())
}

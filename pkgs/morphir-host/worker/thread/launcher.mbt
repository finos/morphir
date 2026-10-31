///|
/// Starts WASM workers in Node worker threads (WASM-3). Before it starts a
/// thread, the launcher checks the module's SHA-256, classifies it, checks
/// its features and caps its memory, so a refusal starts no thread.
pub struct ThreadLauncher {
  priv entry : String
  priv grace_ms : Int32
  priv call_ms : Int32?
}

///|
/// `entry` is the path of the worker entry module. `call_ms` replaces the
/// per-call deadline of the profile, for tests.
pub fn ThreadLauncher::new(
  entry~ : String,
  grace_ms~ : Int32 = @shared.EXIT_GRACE_MS,
  call_ms? : Int32,
) -> ThreadLauncher {
  { entry, grace_ms, call_ms, }
}

///|
/// The file name of the worker entry module in the npm package, beside the
/// CLI bundle.
pub const ENTRY_FILE : String = "wasm-worker.js"

///|
/// The launcher of the npm CLI: its entry module is `wasm-worker.js` beside
/// the CLI bundle. When the file is missing, or its path is not known or not
/// absolute, each launch fails and names it.
pub fn ThreadLauncher::bundled() -> ThreadLauncher {
  ThreadLauncher::new(entry=beside_script(ENTRY_FILE))
}

///|
pub extend ThreadLauncher with @worker.Launcher::{launch}

///|
pub impl @worker.Launcher for ThreadLauncher with fn launch(self, spec, limits) {
  guard spec.runtime is Wasm(abi~) else {
    raise @worker.LaunchError::RuntimeUnavailable(supported=[Wasm])
  }
  let bytes = match spec.artifact.source {
    Memory(bytes) => bytes
    File(path) => read_file(path.to_string())
  }
  let bytes = @shared.VerifiedArtifact::check(bytes, spec.artifact).bytes()
  let prepared = @wasm.PreparedModule::prepare(bytes, declared?=abi)
  if @guest.missing_feature(bytes) is Some(feature) {
    raise @worker.LaunchError::WasmFeatureUnsupported(feature=Some(feature))
  }
  guard is_absolute(self.entry) else {
    raise @worker.LaunchError::LaunchFailed(
      "the WASM worker entry module path is not absolute: \{self.entry}",
    )
  }
  guard file_exists(self.entry) else {
    raise @worker.LaunchError::LaunchFailed(
      "the WASM worker entry module is missing: \{self.entry}",
    )
  }
  let call_ms = self.call_ms.unwrap_or(
    @guest.CallBounds::for_abi(prepared.abi).deadline_ms,
  )
  // The thread starts in this tick, so a cancellation cannot leave it half
  // started.
  ThreadChannel::start(
    self.entry,
    prepared.abi,
    bytes,
    limits,
    call_ms~,
    grace_ms=self.grace_ms,
  )
}

///|
/// Starts WASM workers in browser Web Workers (BRW-1). Before it starts a
/// Web Worker, the launcher checks the module's SHA-256, classifies it,
/// checks its features and caps its memory, so a refusal starts no worker. A
/// browser host starts no process workers and reads no files: an artifact
/// must hold its bytes.
pub struct BrowserLauncher {
  priv entry : EntryUrl
  priv grace_ms : Int32
  priv call_ms : Int32?
}

///|
/// `entry` is the URL of the Web Worker entry module. `call_ms` replaces the
/// per-call deadline of the profile, for tests and proofs.
pub fn BrowserLauncher::new(
  entry : EntryUrl,
  grace_ms~ : Int32 = @shared.EXIT_GRACE_MS,
  call_ms? : Int32,
) -> BrowserLauncher {
  { entry, grace_ms, call_ms, }
}

///|
pub extend BrowserLauncher with @worker.Launcher::{launch}

///|
/// The checks before a Web Worker starts. Returns the verified module bytes
/// and the per-call deadline.
fn BrowserLauncher::admit(
  self : BrowserLauncher,
  spec : @worker.WorkerSpec,
) -> (@worker.WasmAbi, Bytes, Int32) raise @worker.LaunchError {
  guard spec.runtime is Wasm(abi~) else {
    raise @worker.LaunchError::RuntimeUnavailable(supported=[Wasm])
  }
  guard spec.artifact.source is Memory(bytes) else {
    raise ArtifactUnreadable(
      Unreadable(
        detail=Some(
          "a browser host has no file system; give the artifact's bytes",
        ),
      ),
    )
  }
  let bytes = @shared.VerifiedArtifact::check(bytes, spec.artifact).bytes()
  let prepared = @wasm.PreparedModule::prepare(bytes, declared?=abi)
  if @guest.missing_feature(bytes) is Some(feature) {
    raise @worker.LaunchError::WasmFeatureUnsupported(feature=Some(feature))
  }
  let call_ms = self.call_ms.unwrap_or(
    @guest.CallBounds::for_abi(prepared.abi).deadline_ms,
  )
  (prepared.abi, bytes, call_ms)
}

///|
pub impl @worker.Launcher for BrowserLauncher with fn launch(self, spec, limits) {
  let (abi, bytes, call_ms) = self.admit(spec)
  let error : FixedArray[String] = [""]
  let target = start_web_worker(self.entry.to_string(), error)
  guard error[0] == "" else {
    raise @worker.LaunchError::LaunchFailed(
      "the Web Worker did not start: \{error[0]}",
    )
  }
  PortChannel::open(
    target,
    abi,
    bytes,
    limits,
    call_ms~,
    grace_ms=self.grace_ms,
  )
}

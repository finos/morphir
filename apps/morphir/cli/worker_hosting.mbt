///|
/// The worker launchers that a command-line entry gives to the extension
/// commands. The CLI package builds on every target, but each launcher builds
/// only on its own, so the entry for a target makes this value and passes it
/// to `Invocation::prepare`. Without it, as in the WASI entry, the extension
/// commands refuse with `extension.runtime_unavailable`.
pub struct WorkerHosting {
  priv platform : @worker.HostPlatform?
  priv process : &@worker.Launcher?
  priv wasm : &@worker.Launcher?
}

///|
/// No worker host: extension commands refuse before they read a pin.
pub fn WorkerHosting::none() -> WorkerHosting {
  { platform: None, process: None, wasm: None, }
}

///|
/// A worker host on `platform` that starts process workers with `process`
/// and WASM workers with `wasm`. A runtime kind without a launcher is refused
/// with `extension.runtime_unavailable` before anything starts.
pub fn WorkerHosting::new(
  platform : @worker.HostPlatform,
  process? : &@worker.Launcher,
  wasm? : &@worker.Launcher,
) -> WorkerHosting {
  { platform: Some(platform), process, wasm, }
}

///|
/// The runtime kinds that this entry can start.
fn WorkerHosting::kinds(self : WorkerHosting) -> Array[@worker.RuntimeKind] {
  [
    (@worker.RuntimeKind::Process, self.process),
    (@worker.RuntimeKind::Wasm, self.wasm),
  ].filter_map(entry => if entry.1 is Some(_) { Some(entry.0) } else { None })
}

///|
/// The path style of artifact paths on this host.
fn WorkerHosting::path_style(self : WorkerHosting) -> @worker.PathStyle {
  match self.platform {
    Some(Native(machine)) | Some(Node(machine)) => machine.path_style()
    _ => Posix
  }
}

///|
/// The worker host, when this entry has a platform and at least one launcher.
fn WorkerHosting::host(
  self : WorkerHosting,
  limits~ : @worker.Limits = @worker.Limits::host(),
) -> @worker.Host? {
  guard self.platform is Some(platform) && !self.kinds().is_empty() else {
    return None
  }
  Some(@worker.Host::new(RoutedLauncher::{ hosting: self, }, platform, limits~))
}

///|
/// Starts each worker with the launcher for its runtime kind.
priv struct RoutedLauncher {
  hosting : WorkerHosting
}

///|
impl @worker.Launcher for RoutedLauncher with fn launch(self, spec, limits) {
  let launcher = match spec.runtime {
    Process(..) => self.hosting.process
    Wasm(..) => self.hosting.wasm
  }
  guard launcher is Some(launcher) else {
    raise @worker.LaunchError::RuntimeUnavailable(
      supported=self.hosting.kinds(),
    )
  }
  launcher.launch(spec, limits)
}

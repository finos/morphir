///|
/// How the Node host owns a worker's process tree.
priv enum Tree {
  /// Unix: the worker leads a new process group, and the host signals the
  /// group with `process.kill(-pid)`.
  Group
  /// Windows: Node cannot create a job object, so the host stops the tree
  /// from its root with `taskkill /T /F`. It reaches descendants only while
  /// the root runs.
  RootTree
}

///|
fn Tree::host() -> Tree {
  if host_is_windows() {
    RootTree
  } else {
    Group
  }
}

///|
fn Tree::stop_method(self : Tree) -> @worker.StopMethod {
  match self {
    Group => GroupSignal
    RootTree => TreeTermination
  }
}

///|
/// What the host had to do to stop the tree.
priv enum TreeAction {
  /// The worker had exited and nothing of its tree remained.
  NotNeeded
  /// The host stopped the tree and confirmed that it is gone.
  Stopped
  /// The host could not confirm within its bound that the tree is gone.
  Unconfirmed
} derive(Eq)

///|
/// The status and method that a stop reports. `before` is the exit status
/// that the host saw before it acted, `after` the one it saw after.
/// `removed` is whether the host removed the private directory. A directory
/// that stays means a file in it is still in use, so the host cannot confirm
/// that the tree stopped.
fn stop_result(
  tree : Tree,
  reason : @worker.StopReason,
  action : TreeAction,
  before~ : @worker.StopStatus?,
  after~ : @worker.StopStatus?,
  removed~ : Bool = true,
) -> (@worker.StopStatus, @worker.StopMethod) {
  let status : @worker.StopStatus = match (action, before) {
    (Unconfirmed, _) => Unconfirmed(reason)
    _ if !removed => Unconfirmed(reason)
    (_, Some(status)) => status
    (Stopped, None) => Terminated(reason)
    (NotNeeded, None) => after.unwrap_or(Terminated(reason))
  }
  let stop_method : @worker.StopMethod = match action {
    NotNeeded => ExitedAfterExit
    Stopped | Unconfirmed => tree.stop_method()
  }
  (status, stop_method)
}

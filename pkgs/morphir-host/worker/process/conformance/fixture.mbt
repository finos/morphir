///|
/// A start option of the fixture worker.
pub(all) enum FixtureFlag {
  /// The worker starts a grandchild that runs until it is killed.
  Grandchild
  /// The worker stays alive after `exit` and after the end of its stdin.
  IgnoreExit
  /// The worker never reads its stdin and stays alive.
  IgnoreStdin
  /// At `exit` or the end of its stdin, the worker writes 1 MiB to stdout and
  /// exits after the write.
  FloodOnExit
} derive(Eq, Debug)

///|
pub extend FixtureFlag with Eq::{equal, not_equal}

///|
pub extend FixtureFlag with @debug.Debug::{to_repr}

///|
/// The fixture worker's command-line argument for a flag.
pub fn FixtureFlag::argument(self : FixtureFlag) -> String {
  match self {
    Grandchild => "--grandchild"
    IgnoreExit => "--ignore-exit"
    IgnoreStdin => "--ignore-stdin"
    FloodOnExit => "--flood-on-exit"
  }
}

///|
/// How a launcher owns a worker's process tree.
pub(all) enum TreeOwnership {
  /// A process group that the host signals; it also stops descendants after
  /// the worker has exited.
  Group
  /// A job object that the host terminates; it also stops descendants after
  /// the worker has exited.
  Job
  /// A tree that the host terminates from its root (`taskkill /T`). It reaches
  /// descendants only while the root runs.
  RootTree
} derive(Eq, Debug)

///|
pub extend TreeOwnership with Eq::{equal, not_equal}

///|
pub extend TreeOwnership with @debug.Debug::{to_repr}

///|
/// The stop method that a launcher reports when it stops a tree.
pub fn TreeOwnership::stop_method(self : TreeOwnership) -> @worker.StopMethod {
  match self {
    Group => GroupSignal
    Job => JobTermination
    RootTree => TreeTermination
  }
}

///|
/// What a target supplies to the suite: a launcher started on the fixture
/// worker and a view of the host's processes.
pub(open) trait Fixture {
  /// Starts the fixture worker through the launcher with the limits. The
  /// worker's argument array is the flags, then the arguments.
  async fn start(Self, Array[FixtureFlag], Array[String], @worker.Limits) -> &@worker.Channel
  /// Whether a process with the ID still runs.
  fn alive(Self, Int32) -> Bool
  /// How the launcher owns the worker's tree on this host.
  fn ownership(Self) -> TreeOwnership
  /// The environment variables that the launcher documents for a worker.
  fn documented_environment(Self) -> Array[String]
  /// Files that the host holds open while it starts workers, as
  /// `device:inode`. A worker must not inherit a descriptor for one. The
  /// default is none.
  fn held_open(Self) -> Array[String] = _
}

///|
impl Fixture with fn held_open(_self) {
  []
}

//! Gherkin building blocks for `morphir itest`: the components a scenario carries, the fence and
//! processor that materialize an example, and the CLI runner that runs its commands in isolation.
//!
//! A suite registers [`ItestFence`] and [`MaterializeExample`] as extensions, seeds
//! [`ItestRoot`] and [`KeepTemp`] with `Suite::with_component`, and installs [`ItestRunner`]
//! through morphir-bdd's `CustomCliRunner`. Before a scenario's first step, the processor copies
//! the example into a new temporary root and inserts [`ItestDirs`]; each `When I run` then runs
//! in that root's project with itest's own isolation.
mod library;
mod runner;
mod workspace;

pub use library::parse_selection;
pub use runner::{DEFAULT_TIMEOUT, ItestRunner};
pub use workspace::{
    ExampleFile, ExampleSpec, ExampleWorkspace, ItestFence, MaterializeExample, scenario_id,
};

use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex, atomic::AtomicUsize},
    time::Duration,
};
use tempfile::TempDir;

/// Where one itest scenario runs: the temporary root, its project, and the isolated home
/// directories (`root/project`, `root/home`, `root/config`, `root/user`, `root/local`).
#[derive(Debug, Clone)]
pub struct ItestDirs {
    /// The scenario's temporary root. Each isolated subprocess's logs go to `root/step-N/`.
    pub root: PathBuf,
    /// The materialized project, `root/project`: every command's working directory.
    pub project: PathBuf,
    /// How many isolated subprocesses `steps::runner::run_isolated` has spawned for this scenario
    /// so far: one per `When I run`, plus one more for each of the policy step's own internal
    /// `morphir eval` calls. Used only to number `root/step-N/` log directories.
    ///
    /// This is *not* which `When I run` a capture or `stdout is JSON` step belongs to: an internal
    /// `morphir eval` call advances it too, so a policy check on a command that has more than one
    /// assertion would otherwise see its own captures reset partway through. [`ItestDirs::command`]
    /// is the counter the step library keys that on.
    pub step: Arc<AtomicUsize>,
    /// How many `When I run` commands the scenario has run so far. Unlike [`ItestDirs::step`],
    /// only `ItestRunner::run` advances this (once per `When I run`), so the step library keys a
    /// command's captures and `stdout is JSON` flag on this instead.
    pub command: Arc<AtomicUsize>,
    /// The timeout the scenario's most recent `When I run` named, or `None` if it named none (or
    /// no command has run yet). The policy step's own `morphir eval` call reuses it, as legacy
    /// itest gave an assertion its command's `timeout_seconds`.
    pub last_timeout: Arc<Mutex<Option<Duration>>>,
    /// The scenario's most recent `When I run` command line, as `morphir ["arg", …]` (the layout
    /// legacy itest printed a command in), or `None` if no command has run yet. The policy and
    /// golden steps name it when they fail.
    pub last_command_line: Arc<Mutex<Option<String>>>,
    /// Deletes `root` when the last copy of these directories drops; `None` when the root is
    /// kept or was not created by this crate.
    _guard: Option<Arc<TempDir>>,
}

impl ItestDirs {
    /// The directories of the temporary root `root`, with no command run yet. The caller owns
    /// `root` and creates `root/project`; nothing is deleted when these directories drop.
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self::with_guard(root.into(), None)
    }

    fn with_guard(root: PathBuf, temp: Option<TempDir>) -> Self {
        Self {
            project: root.join("project"),
            root,
            step: Arc::new(AtomicUsize::new(0)),
            command: Arc::new(AtomicUsize::new(0)),
            last_timeout: Arc::new(Mutex::new(None)),
            last_command_line: Arc::new(Mutex::new(None)),
            _guard: temp.map(Arc::new),
        }
    }
}

/// The scenario's golden expected files, read before its first step: each file's path, as its
/// golden step names it (relative to the example's directory), to its text. `MaterializeExample`
/// fills it, so a command cannot change an expectation before the golden step compares with it.
#[derive(Debug, Clone, Default)]
pub struct FrozenGoldens(pub HashMap<String, String>);

/// `--keep-temp`: keep each scenario's temporary root after the run, for diagnosis.
#[derive(Debug, Clone, Copy)]
pub struct KeepTemp(pub bool);

/// The directory `morphir itest` searches for examples. Scenario ids are relative to it.
#[derive(Debug, Clone)]
pub struct ItestRoot(pub PathBuf);

/// Keeps the itest step library ([`library`]'s capture, `stdout is JSON`, policy and golden
/// steps) in a binary that links this module. Call this once from `main`, alongside
/// `morphir_bdd::link()`, the way `morphir_bdd::steps::link` keeps its own base steps.
pub fn link() {
    library::link();
}

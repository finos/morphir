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
    path::PathBuf,
    sync::{Arc, atomic::AtomicUsize},
};
use tempfile::TempDir;

/// Where one itest scenario runs: the temporary root, its project, and the isolated home
/// directories (`root/project`, `root/home`, `root/config`, `root/user`, `root/local`).
#[derive(Debug, Clone)]
pub struct ItestDirs {
    /// The scenario's temporary root. Each command's logs go to `root/step-N/`.
    pub root: PathBuf,
    /// The materialized project, `root/project`: every command's working directory.
    pub project: PathBuf,
    /// How many commands the scenario has run so far. The runner increments it before each one.
    pub step: Arc<AtomicUsize>,
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
            _guard: temp.map(Arc::new),
        }
    }
}

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

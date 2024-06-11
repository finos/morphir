pub use crate::workspace::error::*;
pub use crate::workspace::states::*;
use derive_more::From;
use error::Result;
use path_absolutize::*;
use serde::{Deserialize, Serialize};
use std::{
    fmt::Debug,
    path::{Path, PathBuf},
};
use tracing::{debug, instrument};

pub mod config;
mod error;
mod states;

#[instrument(level = "debug")]
pub fn locate_with<S, E>(
    start_path: &S,
    end_dir: &E,
    locator: WorkspaceLocator,
    traversal_action: WorkspaceTraversalAction,
) -> Result<(WorkspaceRoot, WorkspaceConfigFilePath)>
where
    S: AsRef<Path> + Debug,
    E: AsRef<Path> + Debug,
{
    // let run_mode = env::var("RUN_MODE").unwrap_or_else(|_| "development".into());
    // trace!("run_mode: {}", run_mode);
    let start_path = start_path.as_ref();
    let start_path = start_path.absolutize()?;
    let start_buf = start_path.to_path_buf();

    let mut current = start_buf.clone();
    loop {
        if let Some((root, config_file_path)) = locator(&current) {
            debug!(
                "Located workspace at: {:?} with config file at: {:?}",
                root, config_file_path
            );
            return Ok((root, config_file_path));
        } else {
            let end_at: TargetDir = end_dir.as_ref().to_path_buf().into();
            match traversal_action((CurrentDir::from(&current), end_at)) {
                TraversalInstruction::Continue(next) => {
                    debug!("Traversing to next directory: {:?}", next);
                    current = next;
                }
                TraversalInstruction::Stop => {
                    return Err(error::Error::WorkspaceNotFoundAtPath(start_buf));
                }
            }
        }
    }
}

#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
pub struct WorkspaceRoot(PathBuf);
impl WorkspaceRoot {
    pub fn new(path: PathBuf) -> Self {
        WorkspaceRoot(path)
    }

    #[inline]
    pub fn as_path(&self) -> &Path {
        self.0.as_path()
    }
}

impl From<PathBuf> for WorkspaceRoot {
    #[inline]
    fn from(path: PathBuf) -> Self {
        WorkspaceRoot(path)
    }
}

impl AsRef<Path> for WorkspaceRoot {
    #[inline]
    fn as_ref(&self) -> &Path {
        self.as_path()
    }
}

#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
pub struct WorkspaceConfigFilePath(PathBuf);

pub type WorkspaceLocator = fn(&PathBuf) -> Option<(WorkspaceRoot, WorkspaceConfigFilePath)>;

pub type WorkspaceTraversalAction = fn((CurrentDir, TargetDir)) -> TraversalInstruction;

#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize, From)]
pub struct CurrentDir(PathBuf);

impl From<&Path> for CurrentDir {
    fn from(path: &Path) -> Self {
        CurrentDir(path.to_path_buf())
    }
}

impl From<&PathBuf> for CurrentDir {
    fn from(path: &PathBuf) -> Self {
        CurrentDir(path.to_path_buf())
    }
}

#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize, From)]
pub struct TargetDir(PathBuf);

pub enum TraversalInstruction {
    Continue(PathBuf),
    Stop,
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use starbase_sandbox::create_empty_sandbox;

    // #[test]
    // fn test_locate() {
    //     let sandbox = create_empty_sandbox();
    //     let workspace = LocatingWorkspace::new(sandbox.path());
    //     let located = workspace.locate().unwrap();
    //     assert_eq!(sandbox.path(), located.root.as_path());
    // }
}

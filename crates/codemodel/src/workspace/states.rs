use std::env;
use std::fmt::Debug;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use tracing::debug;

use super::config::WorkspaceConfig;
use super::error::Result;
use super::{
    CurrentDir, TargetDir, TraversalInstruction, WorkspaceConfigFilePath, WorkspaceLocator,
    WorkspaceRoot, WorkspaceTraversalAction,
};

#[derive(Debug)]
pub struct WorkspaceLaunchLocation(PathBuf);

impl WorkspaceLaunchLocation {
    pub fn new<P>(start_path: P) -> Self
    where
        P: AsRef<Path> + Debug,
    {
        let start = start_path.as_ref().to_path_buf();
        Self(start)
    }

    #[inline]
    pub fn from_cwd() -> Result<Self> {
        let cwd = env::current_dir()?;
        Ok(Self::new(cwd))
    }

    pub fn locate_workspace_with<E>(
        &self,
        end_dir: &E,
        locator: WorkspaceLocator,
        traversal_action: WorkspaceTraversalAction,
    ) -> Result<LocatedWorkspace>
    where
        E: AsRef<Path> + Debug,
    {
        // let run_mode = env::var("RUN_MODE").unwrap_or_else(|_| "development".into());
        // trace!("run_mode: {}", run_mode);
        let path_buf: &PathBuf = self.as_ref();
        if let Some((root, config_file_path)) = locator(path_buf) {
            debug!(
                "Located workspace at: {:?} with config file at: {:?}",
                root, config_file_path
            );
            Ok(LocatedWorkspace {
                root,
                config_file_path,
            })
        } else {
            let end_at: TargetDir = end_dir.as_ref().to_path_buf().into();
            match traversal_action((CurrentDir::from(path_buf), end_at)) {
                TraversalInstruction::Continue(next) => {
                    let next_location = WorkspaceLaunchLocation::new(next);
                    next_location.locate_workspace_with(end_dir, locator, traversal_action)
                }
                TraversalInstruction::Stop => todo!("Implement"),
            }
        }
    }
}

impl AsRef<PathBuf> for WorkspaceLaunchLocation {
    #[inline]
    fn as_ref(&self) -> &PathBuf {
        &self.0
    }
}

impl AsRef<Path> for WorkspaceLaunchLocation {
    #[inline]
    fn as_ref(&self) -> &Path {
        self.0.as_path()
    }
}

impl From<PathBuf> for WorkspaceLaunchLocation {
    #[inline]
    fn from(path: PathBuf) -> Self {
        Self::new(path)
    }
}

impl From<&Path> for WorkspaceLaunchLocation {
    #[inline]
    fn from(path: &Path) -> Self {
        Self::new(path)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocatedWorkspace {
    root: WorkspaceRoot,
    config_file_path: WorkspaceConfigFilePath,
}

pub struct Workspace {
    root: WorkspaceRoot,
    config_file_path: PathBuf,
    config: WorkspaceConfig,
}

impl Workspace {
    #[inline]
    fn get_config(&self) -> &WorkspaceConfig {
        &self.config
    }
}

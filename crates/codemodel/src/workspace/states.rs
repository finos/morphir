use std::env;
use std::fmt::Debug;
use std::path::{Path, PathBuf};

use super::error::Result;
use super::settings::WorkspaceConfig;
use super::WorkspaceRoot;

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

    pub fn locate(&self) -> Result<LocatedWorkspace> {
        // let run_mode = env::var("RUN_MODE").unwrap_or_else(|_| "development".into());
        // trace!("run_mode: {}", run_mode);
        todo!("Implement locating workspace")
    }
}

pub struct LocatedWorkspace {
    root: WorkspaceRoot,
    config_file_path: PathBuf,
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

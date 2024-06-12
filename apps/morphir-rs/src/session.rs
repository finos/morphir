use std::fmt::Debug;
use std::path::{ PathBuf};
use async_trait::async_trait;
use starbase::{AppSession, AppResult};
use tracing::{ trace, warn};
use crate::models::workspace::WorkspaceRoot;
use morphir_utils::fs::find_upwards;
use morphir_utils::fs_error::FsError;

#[derive(Clone, Debug)]
pub struct Session {
    launch_dir: PathBuf,
    workspace_root: WorkspaceRoot,
}

impl Session {
    pub const WORKSPACE_CONFIG_FILENAMES: &'static [&'static str; 2] = &[".Morphir.toml", ".morphir.toml"];
    pub fn update_workspace_root(&mut self) -> bool {

        let workspace_root_dir = find_upwards(Self::WORKSPACE_CONFIG_FILENAMES, &self.launch_dir);
        match workspace_root_dir {
            Ok(workspace_root_dir) => {
                let workspace_root = WorkspaceRoot::new(workspace_root_dir);
                self.workspace_root = workspace_root;
                true
            }
            Err(error @ FsError::NotFound(_)) => {
                warn!("Workspace discovery failed. {}", error);
                false
            }
            Err(error) => {
                warn!("Workspace discovery failed. {}", error);
                false
            }
        }
    }
}

#[async_trait]
impl AppSession for Session {
    async fn startup(&mut self) -> AppResult {
        trace!("Starting up Morphir session");
        self.update_workspace_root();
        Ok(())
    }
}

impl Default for Session {
    fn default() -> Self {
        let launch_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let workspace_root = launch_dir.clone().into();
        Self {
            launch_dir,
            workspace_root,
        }
    }
}
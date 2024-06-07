use std::path::{Path, PathBuf};
use async_trait::async_trait;
use starbase::{AppSession, AppResult};
use tracing::{info, trace, warn};
use crate::models::tools::ToolId;
use crate::models::workspace::WorkspaceRoot;

#[derive(Clone, Debug)]
pub struct Session {
    tool_id: ToolId,
    launch_dir: PathBuf,
    workspace_root: WorkspaceRoot,
}

#[async_trait]
impl AppSession for Session {
    async fn startup(&mut self) -> AppResult {
        trace!("Starting up {} session", self.tool_id.as_str());
        warn!("TODO: detect workspace root");
        Ok(())
    }
}

impl Default for Session {
    fn default() -> Self {
        let launch_dir = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let workspace_root = launch_dir.clone().into();
        Self {
            tool_id: ToolId::default(),
            launch_dir,
            workspace_root,
        }
    }
}
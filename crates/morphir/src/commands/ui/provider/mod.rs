//! Workspace-capability providers available to the loopback UI host.

pub mod extension;
pub mod native;
mod project_model;

#[cfg(test)]
mod conformance;

use std::time::Duration;

use async_trait::async_trait;

use crate::error::CliError;

use super::protocol::{
    InspectResult, ProjectModelOpenResult, ProviderManifest, WorkbenchSourceRef, WorkspaceSnapshot,
};

#[async_trait]
pub trait WorkspaceCapability: Send + Sync {
    fn watch_refresh_interval(&self) -> Duration {
        Duration::from_millis(500)
    }

    fn manifest(&self) -> ProviderManifest;
    fn initial_sources(&self) -> Vec<WorkbenchSourceRef>;
    async fn inspect(&self, source: &WorkbenchSourceRef) -> Result<InspectResult, CliError>;
    async fn open(&self, source: &WorkbenchSourceRef) -> Result<WorkspaceSnapshot, CliError>;
    async fn load_project_model(
        &self,
        source: &WorkbenchSourceRef,
        project_id: &str,
    ) -> Result<ProjectModelOpenResult, CliError>;
}

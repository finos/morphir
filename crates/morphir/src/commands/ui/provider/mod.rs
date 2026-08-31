//! Workspace-capability providers available to the loopback UI host.

pub mod extension;
pub mod native;

use async_trait::async_trait;

use crate::error::CliError;

use super::protocol::{InspectResult, ProviderManifest, WorkbenchSourceRef, WorkspaceSnapshot};

#[async_trait]
pub trait WorkspaceCapability: Send + Sync {
    fn manifest(&self) -> ProviderManifest;
    fn initial_sources(&self) -> Vec<WorkbenchSourceRef>;
    async fn inspect(&self, source: &WorkbenchSourceRef) -> Result<InspectResult, CliError>;
    async fn open(&self, source: &WorkbenchSourceRef) -> Result<WorkspaceSnapshot, CliError>;
}

//! Capability providers available to the loopback UI host.

pub mod extension;
pub mod native;
mod project_model;

#[cfg(test)]
mod conformance;

use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;

use crate::error::CliError;

use super::protocol::{
    InitialView, InspectResult, PlaygroundCatalog, PlaygroundCompileParams,
    PlaygroundCompileResult, PlaygroundGenerateParams, PlaygroundGenerateResult,
    ProjectModelOpenResult, ProviderManifest, WorkbenchSourceRef, WorkspaceSnapshot,
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

/// What a Morphir UI session can compile and generate, independent of any
/// open workspace.
#[async_trait]
pub trait PlaygroundCapability: Send + Sync {
    fn manifest(&self) -> ProviderManifest;
    async fn catalog(&self) -> Result<PlaygroundCatalog, CliError>;
    async fn compile(
        &self,
        params: PlaygroundCompileParams,
    ) -> Result<PlaygroundCompileResult, CliError>;
    async fn generate(
        &self,
        params: PlaygroundGenerateParams,
    ) -> Result<PlaygroundGenerateResult, CliError>;
}

/// What a Morphir UI session can actually do. A session may carry a
/// workspace, a playground, or both; each capability is present only when a
/// provider for it was constructed. Adding a new capability means adding one
/// field here and touching zero existing call sites, since every field
/// defaults to absent.
#[derive(Default, Clone)]
pub struct SessionCapabilities {
    pub workspace: Option<Arc<dyn WorkspaceCapability>>,
    pub playground: Option<Arc<dyn PlaygroundCapability>>,
    /// Which view the CLI launched. Chooses the `/launch` redirect target.
    pub initial_view: Option<InitialView>,
}

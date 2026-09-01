//! Verified installed workspace extension provider.

use std::path::{Path, PathBuf};

#[cfg(test)]
use std::sync::Arc;

use async_trait::async_trait;
use chrono::{SecondsFormat, Utc};
use morphir_common::home::MorphirHome;
use morphir_daemon::extensions::{
    InvokeOutcome, activate_transport,
    protocol::{InitializeParams, MEP_VERSION, PeerInfo, methods},
};
use morphir_devkit::{ConfigLoadOptions, build_workspace_discovery_request};
use morphir_distribution::{
    Capability, InstalledExtensionSnapshot, activate_installed_snapshot, list_installed,
};
use morphir_workspace as portable;

use crate::error::CliError;

use super::{WorkspaceCapability, native::qualify_snapshot};
use crate::commands::ui::protocol::{
    DevelopmentWorkbenchDescriptor, DevelopmentWorkbenchKind, DevelopmentWorkbenchRoute,
    InspectResult, ProviderKind, ProviderManifest, ProviderProvenance, ProviderStatus,
    WorkbenchCapability, WorkbenchSourceRef, WorkspaceSnapshot, protocol_error, source_key,
};

pub struct ExtensionWorkspaceProvider {
    manifest: ProviderManifest,
    source: WorkbenchSourceRef,
    workspace: PathBuf,
    implementation: ExtensionImplementation,
}

enum ExtensionImplementation {
    Installed {
        home: MorphirHome,
        snapshot: Box<InstalledExtensionSnapshot>,
    },
    #[cfg(test)]
    Fixture(Arc<portable::WorkspaceSnapshot>),
}

impl ExtensionWorkspaceProvider {
    pub fn select(
        home: MorphirHome,
        workspace: &Path,
        session_id: &str,
        requested_id: Option<&str>,
    ) -> Result<Self, CliError> {
        let mut candidates = list_installed(&home)
            .map_err(|error| {
                extension_error(format!("Unable to list installed extensions: {error}"))
            })?
            .into_iter()
            .filter(|candidate| {
                candidate
                    .installed()
                    .capabilities()
                    .contains(&Capability::Workspace)
            })
            .filter(|candidate| {
                requested_id.is_none_or(|requested| {
                    candidate.installed().extension_id().as_str() == requested
                })
            })
            .collect::<Vec<_>>();
        if candidates.is_empty() {
            return Err(extension_error(match requested_id {
                Some(id) => {
                    format!("Installed extension '{id}' does not provide workspace discovery")
                }
                None => "No installed extension provides workspace discovery".into(),
            }));
        }
        if candidates.len() > 1 {
            let ids = candidates
                .iter()
                .map(|candidate| candidate.installed().extension_id().to_string())
                .collect::<Vec<_>>()
                .join(", ");
            return Err(extension_error(format!(
                "More than one installed workspace provider is available ({ids}); select one with --workspace-extension"
            )));
        }
        let snapshot = candidates.pop().expect("one candidate remains");
        let installed = snapshot.installed();
        let provider_id = format!("cli:{session_id}");
        let source = source_for(workspace, &provider_id);
        let manifest = manifest_for(
            &provider_id,
            &format!("{} via Morphir CLI", installed.name()),
            Some(ProviderProvenance {
                extension_id: installed.extension_id().to_string(),
                extension_version: installed.version().to_string(),
            }),
        );
        Ok(Self {
            manifest,
            source,
            workspace: workspace.to_path_buf(),
            implementation: ExtensionImplementation::Installed {
                home,
                snapshot: Box::new(snapshot),
            },
        })
    }

    #[cfg(test)]
    fn from_fixture(
        workspace: &Path,
        session_id: &str,
        snapshot: portable::WorkspaceSnapshot,
    ) -> Self {
        let provider_id = format!("cli:{session_id}");
        Self {
            manifest: manifest_for(
                &provider_id,
                "Fixture workspace extension via Morphir CLI",
                Some(ProviderProvenance {
                    extension_id: "fixture-workspace".into(),
                    extension_version: "1.0.0".into(),
                }),
            ),
            source: source_for(workspace, &provider_id),
            workspace: workspace.to_path_buf(),
            implementation: ExtensionImplementation::Fixture(Arc::new(snapshot)),
        }
    }

    fn validate_source(&self, source: &WorkbenchSourceRef) -> Result<(), CliError> {
        if source.provider_id != self.source.provider_id {
            return Err(protocol_error(format!(
                "Source belongs to provider '{}', expected '{}'",
                source.provider_id, self.source.provider_id
            )));
        }
        if source.locator != self.source.locator {
            return Err(protocol_error(format!(
                "Source locator '{}' is not present in this session",
                source.locator
            )));
        }
        Ok(())
    }

    async fn discover(&self) -> Result<portable::WorkspaceSnapshot, CliError> {
        match &self.implementation {
            ExtensionImplementation::Installed { home, snapshot } => {
                invoke_installed(home, snapshot, &self.workspace).await
            }
            #[cfg(test)]
            ExtensionImplementation::Fixture(snapshot) => Ok(snapshot.as_ref().clone()),
        }
    }
}

#[async_trait]
impl WorkspaceCapability for ExtensionWorkspaceProvider {
    fn watch_refresh_interval(&self) -> std::time::Duration {
        std::time::Duration::from_secs(5)
    }

    fn manifest(&self) -> ProviderManifest {
        self.manifest.clone()
    }

    fn initial_sources(&self) -> Vec<WorkbenchSourceRef> {
        vec![self.source.clone()]
    }

    async fn inspect(&self, source: &WorkbenchSourceRef) -> Result<InspectResult, CliError> {
        self.validate_source(source)?;
        let timestamp = Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true);
        Ok(InspectResult {
            descriptor: DevelopmentWorkbenchDescriptor {
                id: source_key(&self.source),
                source: self.source.clone(),
                name: self.source.display_name.clone(),
                kind: DevelopmentWorkbenchKind::Development,
                route: DevelopmentWorkbenchRoute::Overview,
                opened_at: timestamp.clone(),
                last_used_at: timestamp,
            },
        })
    }

    async fn open(&self, source: &WorkbenchSourceRef) -> Result<WorkspaceSnapshot, CliError> {
        self.validate_source(source)?;
        Ok(qualify_snapshot(&self.source, self.discover().await?))
    }
}

async fn invoke_installed(
    home: &MorphirHome,
    snapshot: &InstalledExtensionSnapshot,
    workspace: &Path,
) -> Result<portable::WorkspaceSnapshot, CliError> {
    let request = build_workspace_discovery_request(workspace, &ConfigLoadOptions::default())
        .map_err(CliError::from)?;
    let artifact = activate_installed_snapshot(home, snapshot).map_err(|error| {
        extension_error(format!(
            "Failed to activate installed workspace provider '{}': {error}",
            snapshot.installed().extension_id()
        ))
    })?;
    let loaded = activate_transport(artifact, workspace)
        .await
        .map_err(|error| {
            extension_error(format!(
                "Failed to load installed workspace provider '{}': {error}",
                snapshot.installed().extension_id()
            ))
        })?;
    let ready = loaded
        .initialize(InitializeParams {
            protocol_versions: vec![MEP_VERSION.into()],
            host: PeerInfo {
                name: "morphir-cli".into(),
                version: env!("CARGO_PKG_VERSION").into(),
            },
        })
        .await
        .map_err(|failure| extension_error(failure.error().to_string()))?;
    if !ready
        .negotiated()
        .capabilities()
        .workspace
        .as_ref()
        .is_some_and(|capability| capability.discover && capability.protocol_versions.contains(&1))
    {
        let _ = ready.shutdown().await;
        return Err(extension_error(format!(
            "Installed workspace provider '{}' did not negotiate discovery protocol 1",
            snapshot.installed().extension_id()
        )));
    }
    let (ready, response) = match ready
        .invoke::<portable::DiscoveryResponse>(methods::WORKSPACE_DISCOVER, request)
        .await
    {
        InvokeOutcome::Success(ready, response) => (ready, response),
        InvokeOutcome::Rejected(ready, error) => {
            let _ = ready.shutdown().await;
            return Err(extension_error(error.to_string()));
        }
        InvokeOutcome::Failed(failure) => {
            return Err(extension_error(failure.error().to_string()));
        }
    };
    ready
        .shutdown()
        .await
        .map_err(|failure| extension_error(failure.error().to_string()))?;
    response
        .into_result()
        .map_err(|failure| extension_error(format!("{}: {}", failure.code, failure.message)))
}

fn manifest_for(
    provider_id: &str,
    name: &str,
    provenance: Option<ProviderProvenance>,
) -> ProviderManifest {
    ProviderManifest {
        id: provider_id.into(),
        name: name.into(),
        kind: ProviderKind::Connected,
        status: ProviderStatus::Available,
        capabilities: [
            "morphir/development/inspect",
            "morphir/workspace/open",
            "morphir/workspace/watch",
        ]
        .into_iter()
        .map(|name| WorkbenchCapability {
            name: name.into(),
            version: "1".into(),
        })
        .collect(),
        provenance,
    }
}

fn source_for(workspace: &Path, provider_id: &str) -> WorkbenchSourceRef {
    WorkbenchSourceRef {
        provider_id: provider_id.into(),
        locator: "workspace:initial".into(),
        display_name: workspace
            .file_name()
            .map(|name| name.to_string_lossy().into_owned())
            .unwrap_or_else(|| "Morphir workspace".into()),
        persistence: None,
    }
}

fn extension_error(message: impl Into<String>) -> CliError {
    CliError::Extension {
        message: message.into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::ui::provider::native::NativeWorkspaceProvider;
    use morphir_devkit::discover_workspace_detailed;

    fn fixture() -> PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../ecosystem/morphir-rust/tests/fixtures/workspace-discovery/valid-monorepo")
    }

    #[tokio::test]
    async fn fake_extension_matches_native_workspace_shape_and_reports_provenance() {
        let portable = discover_workspace_detailed(&fixture(), &ConfigLoadOptions::default())
            .unwrap()
            .snapshot;
        let extension = ExtensionWorkspaceProvider::from_fixture(&fixture(), "session-1", portable);
        let native = NativeWorkspaceProvider::discover(&fixture(), "session-1").unwrap();
        let source = extension.initial_sources().pop().unwrap();

        assert_eq!(
            extension.open(&source).await.unwrap(),
            native.open(&source).await.unwrap()
        );
        assert_eq!(
            extension.manifest().provenance.unwrap().extension_id,
            "fixture-workspace"
        );
        assert!(native.manifest().provenance.is_none());
    }

    #[test]
    fn watch_refresh_interval_avoids_restarting_extensions_too_often() {
        let portable = discover_workspace_detailed(&fixture(), &ConfigLoadOptions::default())
            .unwrap()
            .snapshot;
        let extension = ExtensionWorkspaceProvider::from_fixture(&fixture(), "session-1", portable);

        assert_eq!(
            extension.watch_refresh_interval(),
            std::time::Duration::from_secs(5)
        );
    }
}

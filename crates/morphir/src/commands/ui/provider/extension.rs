//! Verified installed workspace extension provider.

use std::path::{Path, PathBuf};

#[cfg(test)]
use std::sync::Arc;

use async_trait::async_trait;
use cap_std::fs::Dir;
use chrono::{SecondsFormat, Utc};
use morphir_common::home::MorphirHome;
use morphir_daemon::DaemonError;
use morphir_devkit::{ConfigLoadOptions, build_workspace_discovery_request};
use morphir_distribution::{Capability, list_installed};
use morphir_extension_sdk::protocol::methods;
use morphir_host::{CallError, HostError, Session};
use morphir_host_native::{InstalledSource, InstalledSourceError};
use morphir_workspace as portable;

use crate::error::CliError;

use super::{
    WorkspaceCapability,
    native::qualify_snapshot,
    project_model::{load_project_model, open_workspace},
};
use crate::commands::ui::protocol::{
    DevelopmentWorkbenchDescriptor, DevelopmentWorkbenchKind, DevelopmentWorkbenchRoute,
    InspectResult, ProjectModelOpenResult, ProviderKind, ProviderManifest, ProviderProvenance,
    ProviderStatus, WorkbenchCapability, WorkbenchSourceRef, WorkspaceSnapshot, protocol_error,
    source_key,
};

pub struct ExtensionWorkspaceProvider {
    manifest: ProviderManifest,
    source: WorkbenchSourceRef,
    workspace: PathBuf,
    workspace_dir: Dir,
    out: crate::commands::out_context::OutOverrides,
    config_options: ConfigLoadOptions,
    originals_lookup: super::originals::HostOutputLookup,
    implementation: ExtensionImplementation,
}

enum ExtensionImplementation {
    Installed(Box<InstalledSource>),
    #[cfg(test)]
    Fixture {
        expected_request: Arc<portable::DiscoveryRequest>,
        response: Arc<portable::DiscoveryResponse>,
    },
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
        let workspace = workspace.to_path_buf();
        let workspace_dir = open_workspace(&workspace)?;
        let source = source_for(&workspace, &provider_id);
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
            workspace,
            workspace_dir,
            out: Default::default(),
            config_options: ConfigLoadOptions::default(),
            originals_lookup: Default::default(),
            implementation: ExtensionImplementation::Installed(Box::new(InstalledSource::new(
                home, snapshot,
            ))),
        })
    }

    #[cfg(test)]
    pub(super) fn from_fixture(
        workspace: &Path,
        session_id: &str,
        config_options: ConfigLoadOptions,
        expected_request: portable::DiscoveryRequest,
        response: portable::DiscoveryResponse,
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
            workspace_dir: open_workspace(workspace).unwrap(),
            out: Default::default(),
            config_options,
            originals_lookup: Default::default(),
            implementation: ExtensionImplementation::Fixture {
                expected_request: Arc::new(expected_request),
                response: Arc::new(response),
            },
        }
    }

    pub fn with_out_overrides(mut self, out: crate::commands::out_context::OutOverrides) -> Self {
        self.out = out;
        self.originals_lookup = Default::default();
        self
    }

    pub(in crate::commands::ui) fn authorize_originals_lookup(
        mut self,
        ambient: cap_std::AmbientAuthority,
    ) -> Result<Self, CliError> {
        let label = self.workspace.canonicalize()?;
        self.originals_lookup = super::originals::HostOutputLookup::issue(
            &self.workspace_dir,
            &label,
            &self.config_options,
            &self.out,
            ambient,
        )?;
        Ok(self)
    }

    pub(super) async fn resolve_originals(
        &self,
        selection: &super::originals::OriginalsSelection,
        credit: crate::commands::ui::model_originals::RetainedEvidenceCredit,
    ) -> Result<
        super::originals::SourceResolution,
        crate::commands::ui::model_originals::ProviderCaptureError,
    > {
        selection.validate_stored_source(&self.source)?;
        let grant = self.originals_lookup.granted()?;
        let captured = grant.capture_discovery()?;
        let membership = match &self.implementation {
            ExtensionImplementation::Installed(source) => {
                invoke_installed(source, &self.workspace, captured.request().clone()).await?
            }
            #[cfg(test)]
            ExtensionImplementation::Fixture {
                expected_request,
                response,
            } => {
                if captured.request() != expected_request.as_ref() {
                    return Err(extension_error(
                        "Fixture workspace request does not match the provider contract",
                    )
                    .into());
                }
                discovery_result(response.as_ref().clone())?
            }
        };
        drop(captured);
        super::originals::resolve_selected(grant, &self.source, selection, &membership, credit)
    }
    pub(super) fn validate_originals_selection(
        &self,
        selection: &super::originals::OriginalsSelection,
    ) -> Result<(), CliError> {
        selection.validate_stored_source(&self.source)
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
        let request = build_workspace_discovery_request(&self.workspace, &self.config_options)
            .map_err(CliError::from)?;
        match &self.implementation {
            ExtensionImplementation::Installed(source) => {
                invoke_installed(source, &self.workspace, request).await
            }
            #[cfg(test)]
            ExtensionImplementation::Fixture {
                expected_request,
                response,
            } => {
                if request != **expected_request {
                    return Err(extension_error(
                        "Fixture workspace request does not match the provider contract",
                    ));
                }
                discovery_result(response.as_ref().clone())
            }
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

    async fn load_project_model(
        &self,
        source: &WorkbenchSourceRef,
        project_id: &str,
    ) -> Result<ProjectModelOpenResult, CliError> {
        self.validate_source(source)?;
        let snapshot = self.open(source).await?;
        load_project_model(
            &self.workspace_dir,
            &self.source,
            snapshot,
            project_id,
            super::project_model::ProjectModelConfig {
                workspace: self.workspace.clone(),
                options: self.config_options.clone(),
                out: self.out.clone(),
            },
        )
        .await
    }
}

/// Discover the workspace with an installed provider over one MEP session.
async fn invoke_installed(
    source: &InstalledSource,
    workspace: &Path,
    request: portable::DiscoveryRequest,
) -> Result<portable::WorkspaceSnapshot, CliError> {
    let snapshot = source.snapshot();
    let guest = source
        .activate(workspace)
        .await
        .map_err(|error| activation_error(snapshot.installed().extension_id(), error))?;
    let mut session = Session::open(guest.connection, &crate::commands::extension::host_config())
        .await
        .map_err(host_error)?;
    if !session
        .negotiated()
        .capabilities()
        .workspace
        .as_ref()
        .is_some_and(|capability| {
            capability.discover
                && capability
                    .protocol_versions
                    .iter()
                    .any(portable::speaks_workspace_discovery_protocol)
        })
    {
        let _ = session.close().await;
        return Err(extension_error(format!(
            "Installed workspace provider '{}' did not negotiate discovery protocol {}",
            snapshot.installed().extension_id(),
            portable::WORKSPACE_DISCOVERY_PROTOCOL
        )));
    }
    let response = match session
        .call::<_, portable::DiscoveryResponse>(methods::WORKSPACE_DISCOVER, request)
        .await
    {
        Ok(response) => response,
        Err(CallError::Rejected(error)) => {
            let _ = session.close().await;
            return Err(host_error(error));
        }
        Err(CallError::Failed(error) | CallError::Invalid(error)) => return Err(host_error(error)),
        Err(other) => return Err(extension_error(other.to_string())),
    };
    session.close().await.map_err(host_error)?;
    discovery_result(response)
}

/// Why the installed workspace provider did not start, in the words this
/// provider has always used: a verification failure fails to activate it, a
/// guest that does not start fails to load it.
fn activation_error(id: impl std::fmt::Display, error: InstalledSourceError) -> CliError {
    extension_error(match error {
        InstalledSourceError::Verify { error, .. } => {
            format!("Failed to activate installed workspace provider '{id}': {error}")
        }
        InstalledSourceError::VerifyWorker { message, .. } => format!(
            "Failed to activate installed workspace provider '{id}': verification worker failed: {message}"
        ),
        InstalledSourceError::Activate { error, .. } => format!(
            "Failed to load installed workspace provider '{id}': {}",
            DaemonError::from(*error)
        ),
        other => other.to_string(),
    })
}

/// A session failure, in the text the daemon's session reported it with.
fn host_error(error: HostError) -> CliError {
    extension_error(DaemonError::from(error).to_string())
}

fn discovery_result(
    response: portable::DiscoveryResponse,
) -> Result<portable::WorkspaceSnapshot, CliError> {
    response
        .into_result()
        .map_err(|error| CliError::WorkspaceDiscovery {
            error: error.into(),
        })
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
            "morphir/project-model/open",
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

    fn from_snapshot(
        workspace: &Path,
        session_id: &str,
        snapshot: portable::WorkspaceSnapshot,
    ) -> ExtensionWorkspaceProvider {
        let config_options = ConfigLoadOptions::default();
        let request = build_workspace_discovery_request(workspace, &config_options).unwrap();
        ExtensionWorkspaceProvider::from_fixture(
            workspace,
            session_id,
            config_options,
            request,
            portable::DiscoveryResponse::Success { snapshot },
        )
    }

    #[tokio::test]
    async fn fake_extension_matches_native_workspace_shape_and_reports_provenance() {
        let portable = discover_workspace_detailed(&fixture(), &ConfigLoadOptions::default())
            .unwrap()
            .snapshot;
        let extension = from_snapshot(&fixture(), "session-1", portable);
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

    /// Install a workspace provider, id `workspace-fixture`, that answers
    /// discovery with `snapshot`.
    #[cfg(unix)]
    fn install_workspace_fixture(
        root: &Path,
        snapshot: &portable::WorkspaceSnapshot,
    ) -> (
        MorphirHome,
        morphir_distribution::InstalledExtensionSnapshot,
    ) {
        let guest = crate::extensions::installed_fixture::mep_guest(
            &serde_json::json!({
                "protocolVersion": "0.1",
                "extension": {
                    "id": "workspace-fixture",
                    "name": "Workspace fixture",
                    "version": "1.0.0",
                    "types": ["workspace"],
                },
                "capabilities": {
                    "workspace": {
                        "discover": true,
                        "protocolVersions": [portable::WORKSPACE_DISCOVERY_PROTOCOL],
                    }
                },
            }),
            &serde_json::json!({
                methods::WORKSPACE_DISCOVER: {
                    "result": portable::DiscoveryResponse::Success {
                        snapshot: snapshot.clone(),
                    }
                }
            }),
        );
        crate::extensions::installed_fixture::install_process(
            root,
            serde_json::json!({
                "schemaVersion": "1.0",
                "id": "workspace-fixture",
                "name": "Workspace fixture",
                "version": "1.0.0",
                "channels": ["stable"],
                "mepVersions": ["0.1"],
                "capabilities": ["workspace"],
            }),
            &guest,
        )
    }

    // The installed workspace provider reaches its guest through the host:
    // it activates the installed artifact, negotiates discovery, and returns
    // the snapshot the guest answered with.
    #[cfg(unix)]
    #[tokio::test]
    async fn the_installed_workspace_provider_discovers_through_the_host() {
        let temp = tempfile::tempdir().unwrap();
        let expected = discover_workspace_detailed(&fixture(), &ConfigLoadOptions::default())
            .unwrap()
            .snapshot;
        let (home, _snapshot) = install_workspace_fixture(temp.path(), &expected);
        let provider =
            ExtensionWorkspaceProvider::select(home, &fixture(), "session-1", None).unwrap();

        assert_eq!(provider.discover().await.unwrap(), expected);
    }

    // An installed workspace provider whose artifact changed after
    // installation fails verification, in this provider's own words.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_changed_installed_workspace_provider_fails_to_activate() {
        let temp = tempfile::tempdir().unwrap();
        let expected = discover_workspace_detailed(&fixture(), &ConfigLoadOptions::default())
            .unwrap()
            .snapshot;
        let (home, snapshot) = install_workspace_fixture(temp.path(), &expected);
        crate::extensions::installed_fixture::tamper(&home, &snapshot);
        let provider =
            ExtensionWorkspaceProvider::select(home, &fixture(), "session-1", None).unwrap();

        match provider.discover().await.unwrap_err() {
            CliError::Extension { message } => {
                assert!(
                    message.starts_with(
                        "Failed to activate installed workspace provider 'workspace-fixture': "
                    ),
                    "{message}"
                );
                assert!(message.contains("digest mismatch"), "{message}");
            }
            other => panic!("expected an extension error, got {other:?}"),
        }
    }

    #[test]
    fn watch_refresh_interval_avoids_restarting_extensions_too_often() {
        let portable = discover_workspace_detailed(&fixture(), &ConfigLoadOptions::default())
            .unwrap()
            .snapshot;
        let extension = from_snapshot(&fixture(), "session-1", portable);

        assert_eq!(
            extension.watch_refresh_interval(),
            std::time::Duration::from_secs(5)
        );
    }

    #[tokio::test]
    async fn fixture_extension_loads_the_selected_project_through_the_host_boundary() {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(
            root.path().join("morphir.toml"),
            "[project]\nname = \"acme/orders\"\nsource_directory = \"src\"\n",
        )
        .unwrap();
        let content = r#"{"formatVersion":3,"distribution":["Library",[],[],{"modules":[]}]}"#;
        std::fs::write(root.path().join("morphir-ir.json"), content).unwrap();
        let portable = discover_workspace_detailed(root.path(), &ConfigLoadOptions::default())
            .unwrap()
            .snapshot;
        let extension = from_snapshot(root.path(), "session-1", portable);
        let source = extension.initial_sources().pop().unwrap();
        let project_id = extension.open(&source).await.unwrap().projects[0]
            .id
            .clone();

        let model = extension
            .load_project_model(&source, &project_id)
            .await
            .unwrap();

        assert_eq!(model.content, content);
        assert_eq!(model.descriptor.source.provider_id, "cli:session-1");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn actual_installed_provider_captures_only_its_guest_selected_project_originals() {
        use crate::commands::ui::{
            model_originals::*,
            protocol::project_key,
            provider::originals::{OriginalsProvider, OriginalsSelection},
        };
        let home_root = tempfile::tempdir().unwrap();
        let workspace = tempfile::tempdir().unwrap();
        std::fs::write(
            workspace.path().join("morphir.toml"),
            "[project]\nname='acme/installed'\nversion='1.0.0'\n",
        )
        .unwrap();
        let output = workspace.path().join(".morphir/out");
        std::fs::create_dir_all(output.join("compile.dest")).unwrap();
        std::fs::write(
            output.join("compile.dest/model.json"),
            b"actual installed originals",
        )
        .unwrap();
        std::fs::write(output.join("compile.json"), br#"{"schema":1,"task":"compile","module":"","completedAt":"now","ir":{"path":"model.json","layout":"single-file","format":"json","version":"v4"}}"#).unwrap();
        let expected =
            discover_workspace_detailed(workspace.path(), &ConfigLoadOptions::project_only())
                .unwrap()
                .snapshot;
        let (home, _) = install_workspace_fixture(home_root.path(), &expected);
        let mut provider =
            ExtensionWorkspaceProvider::select(home, workspace.path(), "installed-originals", None)
                .unwrap();
        provider.config_options = ConfigLoadOptions::project_only();
        let provider = provider
            .authorize_originals_lookup(cap_std::ambient_authority())
            .unwrap();
        let source = provider.initial_sources().pop().unwrap();
        let selection = OriginalsSelection::parse(&source, &project_key(&source, ".")).unwrap();
        let host = HostModelCaptureCapacity::default();
        let owner = ModelCaptureConnection::new(host.clone());
        let id = owner
            .start_provider(
                OriginalsProvider::Installed(Arc::new(provider)),
                selection,
                CaptureScope::Primary,
            )
            .unwrap()
            .wait()
            .await
            .unwrap()
            .ready()
            .unwrap();
        assert_eq!(owner.inspect(&id).unwrap().source_byte_length(), 26);
        assert_eq!(host.usage().active_workers(), 0);
        owner.release(&id).unwrap();
        assert_eq!(host.usage(), ModelCaptureUsage::default());
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn local_config_sidecar_cannot_invent_members_absent_from_actual_installed_guest() {
        use crate::commands::ui::{
            model_originals::*,
            protocol::project_key,
            provider::originals::{OriginalsProvider, OriginalsSelection},
        };
        let home_root = tempfile::tempdir().unwrap();
        let workspace = tempfile::tempdir().unwrap();
        std::fs::write(
            workspace.path().join("morphir.toml"),
            "[project]\nname='acme/installed'\nversion='1.0.0'\n",
        )
        .unwrap();
        let mut snapshot =
            discover_workspace_detailed(workspace.path(), &ConfigLoadOptions::project_only())
                .unwrap()
                .snapshot;
        assert_eq!(snapshot.projects.len(), 1);
        snapshot.projects.clear(); // Actual installed guest has no selected member.
        let (home, _) = install_workspace_fixture(home_root.path(), &snapshot);
        let mut provider =
            ExtensionWorkspaceProvider::select(home, workspace.path(), "installed-originals", None)
                .unwrap();
        provider.config_options = ConfigLoadOptions::project_only();
        let provider = provider
            .authorize_originals_lookup(cap_std::ambient_authority())
            .unwrap();
        let source = provider.initial_sources().pop().unwrap();
        let selection = OriginalsSelection::parse(&source, &project_key(&source, ".")).unwrap();
        let host = HostModelCaptureCapacity::default();
        let owner = ModelCaptureConnection::new(host.clone());
        let result = owner
            .start_provider(
                OriginalsProvider::Installed(Arc::new(provider)),
                selection,
                CaptureScope::Primary,
            )
            .unwrap()
            .wait()
            .await;
        assert!(matches!(result, Err(ProviderCaptureError::Authority(_))));
        assert!(!workspace.path().join(".morphir/out").exists());
        assert_eq!(host.usage(), ModelCaptureUsage::default());
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn installed_selected_project_without_primary_does_not_walk_ancestor_config() {
        use crate::commands::ui::{
            model_originals::*,
            protocol::project_key,
            provider::originals::{OriginalsProvider, OriginalsSelection},
        };
        let home_root = tempfile::tempdir().unwrap();
        let root = tempfile::tempdir().unwrap();
        let workspace = root.path().join("orders");
        std::fs::create_dir(&workspace).unwrap();
        std::fs::write(
            workspace.join("morphir.toml"),
            "[project]\nname='acme/orders'\nversion='1.0.0'\n",
        )
        .unwrap();
        let snapshot = discover_workspace_detailed(&workspace, &ConfigLoadOptions::project_only())
            .unwrap()
            .snapshot;
        assert_eq!(snapshot.projects.len(), 1);
        let (home, _) = install_workspace_fixture(home_root.path(), &snapshot);
        let mut provider =
            ExtensionWorkspaceProvider::select(home, &workspace, "missing-primary", None).unwrap();
        provider.config_options = ConfigLoadOptions::project_only();
        let provider = provider
            .authorize_originals_lookup(cap_std::ambient_authority())
            .unwrap();
        std::fs::remove_file(workspace.join("morphir.toml")).unwrap();
        // This would fail if a missing selected primary caused ancestor search.
        std::fs::write(root.path().join("morphir.toml"), "[malformed ancestor").unwrap();
        let output = workspace.join(".morphir/out");
        std::fs::create_dir_all(output.join("compile.dest")).unwrap();
        std::fs::write(
            output.join("compile.dest/model.json"),
            b"no primary originals",
        )
        .unwrap();
        std::fs::write(output.join("compile.json"), br#"{"schema":1,"task":"compile","module":"","completedAt":"now","ir":{"path":"model.json","layout":"single-file","format":"json","version":"v4"}}"#).unwrap();
        let source = provider.initial_sources().pop().unwrap();
        let selection = OriginalsSelection::parse(&source, &project_key(&source, ".")).unwrap();
        let host = HostModelCaptureCapacity::default();
        let owner = ModelCaptureConnection::new(host.clone());
        let id = owner
            .start_provider(
                OriginalsProvider::Installed(Arc::new(provider)),
                selection,
                CaptureScope::Primary,
            )
            .unwrap()
            .wait()
            .await
            .unwrap()
            .ready()
            .unwrap();
        assert_eq!(owner.inspect(&id).unwrap().source_byte_length(), 20);
        owner.release(&id).unwrap();
        assert_eq!(host.usage(), ModelCaptureUsage::default());
    }
}

//! Native Morphir workspace discovery provider.

use std::path::{Path, PathBuf};

use async_trait::async_trait;
use cap_std::fs::Dir;
use chrono::{SecondsFormat, Utc};
use morphir_devkit::{ConfigLoadOptions, discover_workspace_detailed};
use morphir_workspace as portable;

use crate::error::CliError;

use super::{
    WorkspaceCapability,
    project_model::{load_project_model, open_workspace},
};
use crate::commands::ui::protocol::{
    DevelopmentWorkbenchDescriptor, DevelopmentWorkbenchKind, DevelopmentWorkbenchRoute,
    DiagnosticSeverity, InspectResult, ProjectModelOpenResult, ProjectSnapshot, ProjectState,
    ProviderKind, ProviderManifest, ProviderStatus, WorkbenchCapability, WorkbenchSourceRef,
    WorkspaceDiagnostic, WorkspaceSnapshot, WorkspaceState, project_key, protocol_error,
    source_key,
};

pub struct NativeWorkspaceProvider {
    manifest: ProviderManifest,
    source: WorkbenchSourceRef,
    workspace: PathBuf,
    workspace_dir: Dir,
}

impl NativeWorkspaceProvider {
    pub fn discover(root: &Path, session_id: &str) -> Result<Self, CliError> {
        let discovery = discover_workspace_detailed(root, &ConfigLoadOptions::default())
            .map_err(|error| CliError::Config { error })?;
        let provider_id = format!("cli:{session_id}");
        let display_name = discovery
            .snapshot
            .name
            .clone()
            .or_else(|| {
                discovery
                    .canonical_root
                    .file_name()
                    .map(|name| name.to_string_lossy().into_owned())
            })
            .unwrap_or_else(|| "Morphir workspace".into());
        let source = WorkbenchSourceRef {
            provider_id: provider_id.clone(),
            locator: "workspace:initial".into(),
            display_name,
            persistence: None,
        };
        let workspace = discovery.canonical_root;
        let workspace_dir = open_workspace(&workspace)?;
        Ok(Self {
            manifest: ProviderManifest {
                id: provider_id,
                name: "Morphir CLI".into(),
                kind: ProviderKind::Connected,
                status: ProviderStatus::Available,
                capabilities: vec![
                    capability("morphir/development/inspect"),
                    capability("morphir/project-model/open"),
                    capability("morphir/workspace/open"),
                    capability("morphir/workspace/watch"),
                ],
                provenance: None,
            },
            source,
            workspace,
            workspace_dir,
        })
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
}

#[async_trait]
impl WorkspaceCapability for NativeWorkspaceProvider {
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
        let discovery = discover_workspace_detailed(&self.workspace, &ConfigLoadOptions::default())
            .map_err(|error| CliError::Config { error })?;
        Ok(qualify_snapshot(&self.source, discovery.snapshot))
    }

    async fn load_project_model(
        &self,
        source: &WorkbenchSourceRef,
        project_id: &str,
    ) -> Result<ProjectModelOpenResult, CliError> {
        self.validate_source(source)?;
        let snapshot = self.open(source).await?;
        load_project_model(&self.workspace_dir, &self.source, snapshot, project_id).await
    }
}

fn capability(name: &str) -> WorkbenchCapability {
    WorkbenchCapability {
        name: name.into(),
        version: "1".into(),
    }
}

pub(super) fn qualify_snapshot(
    root: &WorkbenchSourceRef,
    snapshot: portable::WorkspaceSnapshot,
) -> WorkspaceSnapshot {
    WorkspaceSnapshot {
        id: source_key(root),
        root: root.clone(),
        name: snapshot.name,
        config_anchor: Some(snapshot.config_anchor.as_str().into()),
        state: match snapshot.state {
            portable::WorkspaceState::Open => WorkspaceState::Open,
            portable::WorkspaceState::Error => WorkspaceState::Error,
        },
        projects: snapshot
            .projects
            .into_iter()
            .map(|project| qualify_project(root, project))
            .collect(),
        model_sources: vec![],
        knowledge_base_sources: vec![],
        diagnostics: snapshot
            .diagnostics
            .into_iter()
            .map(|diagnostic| qualify_diagnostic(root, diagnostic))
            .collect(),
    }
}

fn qualify_project(
    root: &WorkbenchSourceRef,
    project: portable::ProjectSnapshot,
) -> ProjectSnapshot {
    let relative_path = project.relative_path.as_str().to_owned();
    ProjectSnapshot {
        id: project_key(root, &relative_path),
        name: project.name,
        version: project.version,
        relative_path,
        config_anchor: project
            .config_anchor
            .map(|anchor| anchor.as_str().to_owned()),
        source_directory: project.source_directory.as_str().to_owned(),
        state: match project.state {
            portable::ProjectState::Unloaded => ProjectState::Unloaded,
            portable::ProjectState::Error => ProjectState::Error,
        },
        model_sources: vec![],
        knowledge_base_sources: vec![],
        diagnostics: project
            .diagnostics
            .into_iter()
            .map(|diagnostic| qualify_diagnostic(root, diagnostic))
            .collect(),
    }
}

fn qualify_diagnostic(
    root: &WorkbenchSourceRef,
    diagnostic: portable::WorkspaceDiagnostic,
) -> WorkspaceDiagnostic {
    WorkspaceDiagnostic {
        severity: match diagnostic.severity {
            portable::DiagnosticSeverity::Info => DiagnosticSeverity::Info,
            portable::DiagnosticSeverity::Warning => DiagnosticSeverity::Warning,
            portable::DiagnosticSeverity::Error => DiagnosticSeverity::Error,
        },
        code: Some(diagnostic.code),
        message: diagnostic.message,
        path: diagnostic.path.map(|path| path.as_str().to_owned()),
        project_id: diagnostic
            .project_path
            .map(|path| project_key(root, path.as_str())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::ui::protocol::ModelWorkbenchRoute;

    fn fixture() -> std::path::PathBuf {
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../ecosystem/morphir-rust/tests/fixtures/workspace-discovery/valid-monorepo")
    }

    #[tokio::test]
    async fn discovers_and_qualifies_the_shared_workspace_fixture() {
        let provider = NativeWorkspaceProvider::discover(&fixture(), "session-1").unwrap();
        let source = provider.initial_sources().pop().unwrap();
        let inspected = provider.inspect(&source).await.unwrap();
        let opened = provider.open(&source).await.unwrap();

        assert_eq!(inspected.descriptor.id, source_key(&source));
        assert_eq!(opened.id, source_key(&source));
        assert_eq!(opened.root.provider_id, "cli:session-1");
        assert!(!opened.projects.is_empty());
        assert!(
            opened
                .projects
                .iter()
                .all(|project| project.id.starts_with("[\"cli:session-1\""))
        );
    }

    #[test]
    fn watch_refresh_interval_is_responsive() {
        let provider = NativeWorkspaceProvider::discover(&fixture(), "session-1").unwrap();

        assert_eq!(
            provider.watch_refresh_interval(),
            std::time::Duration::from_millis(500)
        );
    }

    #[tokio::test]
    async fn rejects_foreign_providers_and_unknown_opaque_locators() {
        let provider = NativeWorkspaceProvider::discover(&fixture(), "session-1").unwrap();
        let source = provider.initial_sources().pop().unwrap();

        let mut foreign = source.clone();
        foreign.provider_id = "cli:other".into();
        assert!(provider.open(&foreign).await.is_err());

        let mut unknown = source;
        unknown.locator = "workspace:/private/path".into();
        assert!(provider.open(&unknown).await.is_err());
    }

    #[tokio::test]
    async fn open_rediscovers_workspace_changes() {
        let root = tempfile::tempdir().unwrap();
        let config = root.path().join("morphir.toml");
        std::fs::write(
            &config,
            "[project]\nname = \"acme/first\"\nsource_directory = \"src\"\n",
        )
        .unwrap();
        let provider = NativeWorkspaceProvider::discover(root.path(), "session-1").unwrap();
        let source = provider.initial_sources().pop().unwrap();

        std::fs::write(
            &config,
            "[project]\nname = \"acme/second\"\nsource_directory = \"src\"\n",
        )
        .unwrap();

        assert_eq!(
            provider.open(&source).await.unwrap().projects[0].name,
            "acme/second"
        );
    }

    #[tokio::test]
    async fn loads_the_selected_projects_confined_model_artifact() {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(
            root.path().join("morphir.toml"),
            "[project]\nname = \"acme/orders\"\nsource_directory = \"src\"\n",
        )
        .unwrap();
        let content = r#"{"formatVersion":3,"distribution":["Library",[],[],{"modules":[]}]}"#;
        std::fs::write(root.path().join("morphir-ir.json"), content).unwrap();
        let provider = NativeWorkspaceProvider::discover(root.path(), "session-1").unwrap();
        let source = provider.initial_sources().pop().unwrap();
        let project_id = provider.open(&source).await.unwrap().projects[0].id.clone();

        let model = provider
            .load_project_model(&source, &project_id)
            .await
            .unwrap();

        assert_eq!(model.content, content);
        assert_eq!(model.descriptor.source.provider_id, "cli:session-1");
        assert_eq!(model.descriptor.route, ModelWorkbenchRoute::Explorer);
        assert!(
            provider
                .load_project_model(&source, "unknown")
                .await
                .is_err()
        );

        std::fs::remove_file(root.path().join("morphir-ir.json")).unwrap();
        assert!(
            provider
                .load_project_model(&source, &project_id)
                .await
                .is_err()
        );

        let artifact = root.path().join("morphir-ir.json");
        std::fs::File::create(&artifact).unwrap();
        let error = provider
            .load_project_model(&source, &project_id)
            .await
            .unwrap_err();
        assert!(error.to_string().contains("must not be empty"));

        let oversized = std::fs::File::create(&artifact).unwrap();
        oversized.set_len(64 * 1024 * 1024 + 1).unwrap();
        let error = provider
            .load_project_model(&source, &project_id)
            .await
            .unwrap_err();
        assert!(error.to_string().contains("exceeds"));
        std::fs::remove_file(&artifact).unwrap();

        std::fs::write(&artifact, [0xff]).unwrap();
        let error = provider
            .load_project_model(&source, &project_id)
            .await
            .unwrap_err();
        assert!(error.to_string().contains("valid UTF-8"));

        #[cfg(unix)]
        {
            std::fs::remove_file(&artifact).unwrap();
            let external = tempfile::NamedTempFile::new().unwrap();
            std::os::unix::fs::symlink(external.path(), &artifact).unwrap();
            let _error = provider
                .load_project_model(&source, &project_id)
                .await
                .unwrap_err();
        }
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn loads_project_models_from_the_workspace_opened_during_discovery() {
        let parent = tempfile::tempdir().unwrap();
        let workspace = parent.path().join("workspace");
        std::fs::create_dir(&workspace).unwrap();
        std::fs::write(
            workspace.join("morphir.toml"),
            "[project]\nname = \"acme/orders\"\nsource_directory = \"src\"\n",
        )
        .unwrap();
        std::fs::write(workspace.join("morphir-ir.json"), "inside").unwrap();
        let provider = NativeWorkspaceProvider::discover(&workspace, "session-1").unwrap();
        let source = provider.initial_sources().pop().unwrap();
        let project_id = provider.open(&source).await.unwrap().projects[0].id.clone();

        std::fs::rename(&workspace, parent.path().join("original-workspace")).unwrap();
        std::fs::create_dir(&workspace).unwrap();
        std::fs::write(
            workspace.join("morphir.toml"),
            "[project]\nname = \"acme/orders\"\nsource_directory = \"src\"\n",
        )
        .unwrap();
        std::fs::write(workspace.join("morphir-ir.json"), "outside").unwrap();

        let model = provider
            .load_project_model(&source, &project_id)
            .await
            .unwrap();

        assert_eq!(model.content, "inside");
    }
}

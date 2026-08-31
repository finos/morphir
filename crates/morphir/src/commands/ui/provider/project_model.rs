//! Confined loading for generated project models shared by every workspace provider.

use std::path::{Path, PathBuf};

use chrono::{SecondsFormat, Utc};

use crate::{
    commands::ui::protocol::{
        ModelWorkbenchDescriptor, ModelWorkbenchDistribution, ModelWorkbenchKind,
        ModelWorkbenchRoute, ProjectModelOpenResult, SourcePersistence, WorkbenchSourceRef,
        WorkspaceSnapshot, protocol_error, source_key,
    },
    error::CliError,
};

const MAX_PROJECT_MODEL_BYTES: u64 = 64 * 1024 * 1024;

pub(super) async fn load_project_model(
    workspace: &Path,
    source: &WorkbenchSourceRef,
    snapshot: WorkspaceSnapshot,
    project_id: &str,
) -> Result<ProjectModelOpenResult, CliError> {
    let workspace = workspace.to_path_buf();
    let source = source.clone();
    let project_id = project_id.to_owned();
    tokio::task::spawn_blocking(move || load(&workspace, &source, snapshot, &project_id))
        .await
        .map_err(|error| protocol_error(format!("Project model loader failed: {error}")))?
}

fn load(
    workspace: &Path,
    source: &WorkbenchSourceRef,
    snapshot: WorkspaceSnapshot,
    project_id: &str,
) -> Result<ProjectModelOpenResult, CliError> {
    let project = snapshot
        .projects
        .into_iter()
        .find(|project| project.id == project_id)
        .ok_or_else(|| protocol_error(format!("Unknown workspace project '{project_id}'")))?;
    let canonical_root = workspace.canonicalize().map_err(CliError::from)?;
    let artifact = project_artifact(&canonical_root, &project.relative_path);
    let canonical_artifact = artifact.canonicalize().map_err(CliError::from)?;
    if !canonical_artifact.starts_with(&canonical_root) {
        return Err(protocol_error(format!(
            "Project model leaves the workspace root: {}/morphir-ir.json",
            project.relative_path
        )));
    }
    let metadata = canonical_artifact.metadata().map_err(CliError::from)?;
    if !metadata.is_file() {
        return Err(protocol_error(format!(
            "Project model is not a file: {}/morphir-ir.json",
            project.relative_path
        )));
    }
    if metadata.len() > MAX_PROJECT_MODEL_BYTES {
        return Err(protocol_error(format!(
            "Project model exceeds {MAX_PROJECT_MODEL_BYTES} bytes: {}/morphir-ir.json",
            project.relative_path
        )));
    }
    let bytes = std::fs::read(&canonical_artifact).map_err(CliError::from)?;
    if bytes.is_empty() {
        return Err(protocol_error("Project model must not be empty"));
    }
    if bytes.len() as u64 > MAX_PROJECT_MODEL_BYTES {
        return Err(protocol_error(format!(
            "Project model exceeds {MAX_PROJECT_MODEL_BYTES} bytes: {}/morphir-ir.json",
            project.relative_path
        )));
    }
    let content = String::from_utf8(bytes)
        .map_err(|_| protocol_error("Project model must contain valid UTF-8"))?;
    let timestamp = Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true);
    let model_source = WorkbenchSourceRef {
        provider_id: source.provider_id.clone(),
        locator: format!("project-model:{project_id}"),
        display_name: format!("{} / morphir-ir.json", project.name),
        persistence: Some(SourcePersistence::Session),
    };
    Ok(ProjectModelOpenResult {
        descriptor: ModelWorkbenchDescriptor {
            id: source_key(&model_source),
            source: model_source,
            name: project.name,
            kind: ModelWorkbenchKind::Model,
            distribution: ModelWorkbenchDistribution::SingleFile,
            route: ModelWorkbenchRoute::Explorer,
            opened_at: timestamp.clone(),
            last_used_at: timestamp,
        },
        content,
    })
}

fn project_artifact(root: &Path, relative_path: &str) -> PathBuf {
    if relative_path == "." {
        root.join("morphir-ir.json")
    } else {
        root.join(relative_path).join("morphir-ir.json")
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use crate::commands::ui::protocol::{
        DiagnosticSeverity, ProjectSnapshot, ProjectState, WorkspaceDiagnostic, WorkspaceState,
        project_key,
    };

    #[tokio::test]
    async fn rejects_a_project_artifact_symlink_outside_the_workspace() {
        let root = tempfile::tempdir().unwrap();
        let external = tempfile::NamedTempFile::new().unwrap();
        std::os::unix::fs::symlink(external.path(), root.path().join("morphir-ir.json")).unwrap();
        let source = WorkbenchSourceRef {
            provider_id: "cli:session-1".into(),
            locator: "workspace:initial".into(),
            display_name: "orders".into(),
            persistence: None,
        };
        let project_id = project_key(&source, ".");
        let snapshot = WorkspaceSnapshot {
            id: source_key(&source),
            root: source.clone(),
            name: Some("orders".into()),
            config_anchor: Some("morphir.toml".into()),
            state: WorkspaceState::Open,
            projects: vec![ProjectSnapshot {
                id: project_id.clone(),
                name: "orders".into(),
                version: None,
                relative_path: ".".into(),
                config_anchor: Some("morphir.toml".into()),
                source_directory: "src".into(),
                state: ProjectState::Unloaded,
                model_sources: vec![],
                knowledge_base_sources: vec![],
                diagnostics: Vec::<WorkspaceDiagnostic>::new(),
            }],
            model_sources: vec![],
            knowledge_base_sources: vec![],
            diagnostics: vec![WorkspaceDiagnostic {
                severity: DiagnosticSeverity::Info,
                code: None,
                message: "fixture".into(),
                path: None,
                project_id: None,
            }],
        };

        let error = load_project_model(root.path(), &source, snapshot, &project_id)
            .await
            .unwrap_err();

        assert!(error.to_string().contains("leaves the workspace root"));
    }
}

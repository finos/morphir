//! Confined loading for generated project models shared by every workspace provider.

use std::io::Read as _;
use std::path::{Component, Path};

use cap_fs_ext::{DirExt as _, FollowSymlinks, OpenOptionsFollowExt as _, OpenOptionsSyncExt as _};
use cap_std::fs::{Dir, File, OpenOptions};
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

trait ProjectModelHooks {
    fn after_artifact_open(&self) -> std::io::Result<()> {
        Ok(())
    }
}

struct NoopProjectModelHooks;

impl ProjectModelHooks for NoopProjectModelHooks {}

pub(super) async fn load_project_model(
    workspace: &Dir,
    source: &WorkbenchSourceRef,
    snapshot: WorkspaceSnapshot,
    project_id: &str,
) -> Result<ProjectModelOpenResult, CliError> {
    let workspace = workspace.try_clone().map_err(CliError::from)?;
    let source = source.clone();
    let project_id = project_id.to_owned();
    tokio::task::spawn_blocking(move || load(&workspace, &source, snapshot, &project_id))
        .await
        .map_err(|error| protocol_error(format!("Project model loader failed: {error}")))?
}

fn load(
    workspace: &Dir,
    source: &WorkbenchSourceRef,
    snapshot: WorkspaceSnapshot,
    project_id: &str,
) -> Result<ProjectModelOpenResult, CliError> {
    load_with_hooks(
        workspace,
        source,
        snapshot,
        project_id,
        &NoopProjectModelHooks,
    )
}

fn load_with_hooks<H: ProjectModelHooks + ?Sized>(
    workspace: &Dir,
    source: &WorkbenchSourceRef,
    snapshot: WorkspaceSnapshot,
    project_id: &str,
    hooks: &H,
) -> Result<ProjectModelOpenResult, CliError> {
    let project = snapshot
        .projects
        .into_iter()
        .find(|project| project.id == project_id)
        .ok_or_else(|| protocol_error(format!("Unknown workspace project '{project_id}'")))?;
    let mut artifact = open_project_artifact(workspace, &project.relative_path)?;
    hooks.after_artifact_open().map_err(CliError::from)?;
    let metadata = artifact.metadata().map_err(CliError::from)?;
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
    let mut bytes = Vec::with_capacity(metadata.len().min(MAX_PROJECT_MODEL_BYTES) as usize);
    artifact
        .by_ref()
        .take(MAX_PROJECT_MODEL_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(CliError::from)?;
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

pub(super) fn open_workspace(workspace: &Path) -> Result<Dir, CliError> {
    Dir::open_ambient_dir(workspace, cap_std::ambient_authority()).map_err(CliError::from)
}

fn open_project_artifact(workspace: &Dir, relative_path: &str) -> Result<File, CliError> {
    let mut directory = workspace.try_clone().map_err(CliError::from)?;
    if relative_path != "." {
        let components = Path::new(relative_path).components().collect::<Vec<_>>();
        if components.is_empty() {
            return Err(project_confinement_error(relative_path));
        }
        for component in components {
            let Component::Normal(component) = component else {
                return Err(project_confinement_error(relative_path));
            };
            let metadata = directory
                .symlink_metadata(component)
                .map_err(CliError::from)?;
            if metadata.file_type().is_symlink() {
                return Err(project_confinement_error(relative_path));
            }
            directory = directory
                .open_dir_nofollow(component)
                .map_err(CliError::from)?;
        }
    }
    let metadata = directory
        .symlink_metadata("morphir-ir.json")
        .map_err(CliError::from)?;
    if metadata.file_type().is_symlink() {
        return Err(project_confinement_error(relative_path));
    }
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No).nonblock(true);
    directory
        .open_with("morphir-ir.json", &options)
        .map_err(CliError::from)
}

fn project_confinement_error(relative_path: &str) -> CliError {
    protocol_error(format!(
        "Project model leaves the workspace root: {relative_path}/morphir-ir.json"
    ))
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use crate::commands::ui::protocol::{
        DiagnosticSeverity, ProjectSnapshot, ProjectState, WorkspaceDiagnostic, WorkspaceState,
        project_key,
    };
    use std::path::PathBuf;

    struct SwapArtifactAfterOpen {
        artifact: PathBuf,
        external: PathBuf,
    }

    impl ProjectModelHooks for SwapArtifactAfterOpen {
        fn after_artifact_open(&self) -> std::io::Result<()> {
            std::fs::remove_file(&self.artifact)?;
            std::os::unix::fs::symlink(&self.external, &self.artifact)
        }
    }

    #[test]
    fn reads_from_the_confined_handle_when_the_artifact_path_is_replaced() {
        let root = tempfile::tempdir().unwrap();
        let artifact = root.path().join("morphir-ir.json");
        std::fs::write(&artifact, "inside").unwrap();
        let external = tempfile::NamedTempFile::new().unwrap();
        std::fs::write(external.path(), "outside").unwrap();
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
                diagnostics: vec![],
            }],
            model_sources: vec![],
            knowledge_base_sources: vec![],
            diagnostics: vec![],
        };
        let hooks = SwapArtifactAfterOpen {
            artifact,
            external: external.path().to_path_buf(),
        };

        let workspace = open_workspace(root.path()).unwrap();
        let result = load_with_hooks(&workspace, &source, snapshot, &project_id, &hooks).unwrap();

        assert_eq!(result.content, "inside");
        assert!(
            std::fs::symlink_metadata(&hooks.artifact)
                .unwrap()
                .file_type()
                .is_symlink()
        );
    }

    #[tokio::test]
    async fn rejects_a_fifo_without_waiting_for_a_writer() {
        let root = tempfile::tempdir().unwrap();
        let artifact = root.path().join("morphir-ir.json");
        assert!(
            std::process::Command::new("mkfifo")
                .arg(&artifact)
                .status()
                .unwrap()
                .success()
        );
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
                diagnostics: vec![],
            }],
            model_sources: vec![],
            knowledge_base_sources: vec![],
            diagnostics: vec![],
        };
        let writer_path = artifact.clone();
        let writer = std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_secs(1));
            let _ = rustix::fs::open(
                writer_path,
                rustix::fs::OFlags::WRONLY | rustix::fs::OFlags::NONBLOCK,
                rustix::fs::Mode::empty(),
            );
        });
        let workspace = open_workspace(root.path()).unwrap();

        let started = std::time::Instant::now();
        let error = load_project_model(&workspace, &source, snapshot, &project_id)
            .await
            .unwrap_err();
        let elapsed = started.elapsed();
        writer.join().unwrap();

        assert!(
            elapsed < std::time::Duration::from_millis(750),
            "FIFO open blocked for {elapsed:?}"
        );
        assert!(error.to_string().contains("not a file"));
    }

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

        let workspace = open_workspace(root.path()).unwrap();
        let error = load_project_model(&workspace, &source, snapshot, &project_id)
            .await
            .unwrap_err();

        assert!(error.to_string().contains("leaves the workspace root"));
    }
}

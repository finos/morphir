use std::{fs, path::Path};

use morphir_devkit::{ConfigLoadOptions, EnvSelection, SourceSelection};
use morphir_workspace as portable;
use serde::Deserialize;
use tempfile::TempDir;

use super::{
    WorkspaceCapability, extension::ExtensionWorkspaceProvider, native::NativeWorkspaceProvider,
};
use crate::{
    commands::ui::protocol::{
        self, DiagnosticSeverity, ProjectState, WorkspaceState, project_key, source_key,
    },
    error::CliError,
};

const CORPUS: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../ecosystem/morphir-rust/tests/fixtures/workspace-discovery/corpus.json"
));

const REQUIRED_CASES: &[&str] = &[
    "root-adjacent-toml",
    "root-adjacent-yaml",
    "ambiguous-modern-root-primary",
    "member-project-discovery",
    "excluded-member-omitted",
    "root-is-both-workspace-and-project",
    "malformed-member-isolated-from-sibling",
    "duplicate-names-retain-path-identity",
    "morphir-home-invalid-is-fatal",
    "member-pattern-escapes-root",
    "exclude-pattern-escapes-root",
];

#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CorpusCase {
    name: String,
    request: portable::DiscoveryRequest,
    expected: portable::DiscoveryResponse,
}

struct MaterializedCase {
    development_root: TempDir,
    _morphir_home: Option<TempDir>,
    _system_config: Option<TempDir>,
    options: ConfigLoadOptions,
}

fn materialize_tree(root: &Path, tree: &portable::FileTree) {
    for (relative, entry) in &tree.entries {
        if relative.as_str() == "." {
            continue;
        }
        let path = root.join(relative.as_str());
        match entry {
            portable::FileEntry::Directory => fs::create_dir_all(&path).unwrap(),
            portable::FileEntry::File { text } => {
                fs::create_dir_all(path.parent().unwrap()).unwrap();
                fs::write(path, text).unwrap();
            }
            portable::FileEntry::Symlink { .. } => {
                panic!("selected provider conformance cases must not contain symlinks")
            }
        }
    }
}

fn explicit_config(tree: &portable::FileTree, root: &Path) -> SourceSelection {
    let mut configs = tree
        .entries
        .iter()
        .filter(|(_, entry)| matches!(entry, portable::FileEntry::File { .. }))
        .map(|(relative, _)| root.join(relative.as_str()));
    let config = configs
        .next()
        .expect("selected configuration mount must contain a file");
    assert!(
        configs.next().is_none(),
        "selected configuration mount must contain exactly one file"
    );
    SourceSelection::Explicit(config)
}

fn materialize(case: &CorpusCase) -> MaterializedCase {
    assert!(
        case.request
            .cli_overlay
            .as_object()
            .is_some_and(serde_json::Map::is_empty),
        "the CLI provider contract does not select cases with command-line overlays"
    );

    let development_root = tempfile::tempdir().unwrap();
    materialize_tree(development_root.path(), &case.request.development_root);

    let morphir_home = case.request.morphir_home.as_ref().map(|tree| {
        let directory = tempfile::tempdir().unwrap();
        materialize_tree(directory.path(), tree);
        directory
    });
    let system_config = case.request.system_config.as_ref().map(|tree| {
        let directory = tempfile::tempdir().unwrap();
        materialize_tree(directory.path(), tree);
        directory
    });

    let mut options = ConfigLoadOptions::project_only();
    options.global = morphir_home
        .as_ref()
        .zip(case.request.morphir_home.as_ref())
        .map_or(SourceSelection::Skip, |(directory, tree)| {
            explicit_config(tree, directory.path())
        });
    options.system = system_config
        .as_ref()
        .zip(case.request.system_config.as_ref())
        .map_or(SourceSelection::Skip, |(directory, tree)| {
            explicit_config(tree, directory.path())
        });
    options.user_override = SourceSelection::Discover;
    options.env = EnvSelection::Explicit(
        case.request
            .environment
            .iter()
            .map(|(name, value)| (name.clone(), value.clone()))
            .collect(),
    );

    MaterializedCase {
        development_root,
        _morphir_home: morphir_home,
        _system_config: system_config,
        options,
    }
}

fn assert_workspace_failure(error: CliError, expected: &portable::DiscoveryFailure, name: &str) {
    let expected = crate::error::WorkspaceDiscoveryError::from(expected.clone());
    assert_eq!(error.to_string(), expected.to_string(), "{name}");
    let CliError::WorkspaceDiscovery { error } = error else {
        panic!("expected structured workspace discovery failure for {name}");
    };
    assert_eq!(error, expected, "{name}");
}

fn expected_ui_snapshot(
    source: &protocol::WorkbenchSourceRef,
    snapshot: &portable::WorkspaceSnapshot,
) -> protocol::WorkspaceSnapshot {
    let diagnostic = |diagnostic: &portable::WorkspaceDiagnostic| protocol::WorkspaceDiagnostic {
        severity: match diagnostic.severity {
            portable::DiagnosticSeverity::Info => DiagnosticSeverity::Info,
            portable::DiagnosticSeverity::Warning => DiagnosticSeverity::Warning,
            portable::DiagnosticSeverity::Error => DiagnosticSeverity::Error,
        },
        code: Some(diagnostic.code.clone()),
        message: diagnostic.message.clone(),
        path: diagnostic.path.as_ref().map(|path| path.as_str().into()),
        project_id: diagnostic
            .project_path
            .as_ref()
            .map(|path| project_key(source, path.as_str())),
    };
    protocol::WorkspaceSnapshot {
        id: source_key(source),
        root: source.clone(),
        name: snapshot.name.clone(),
        config_anchor: Some(snapshot.config_anchor.as_str().into()),
        state: match snapshot.state {
            portable::WorkspaceState::Open => WorkspaceState::Open,
            portable::WorkspaceState::Error => WorkspaceState::Error,
        },
        projects: snapshot
            .projects
            .iter()
            .map(|project| protocol::ProjectSnapshot {
                id: project_key(source, project.relative_path.as_str()),
                name: project.name.clone(),
                version: project.version.clone(),
                relative_path: project.relative_path.as_str().into(),
                config_anchor: project
                    .config_anchor
                    .as_ref()
                    .map(|anchor| anchor.as_str().into()),
                source_directory: project.source_directory.as_str().into(),
                state: match project.state {
                    portable::ProjectState::Unloaded => ProjectState::Unloaded,
                    portable::ProjectState::Error => ProjectState::Error,
                },
                model_sources: vec![],
                knowledge_base_sources: vec![],
                diagnostics: project.diagnostics.iter().map(&diagnostic).collect(),
            })
            .collect(),
        model_sources: vec![],
        knowledge_base_sources: vec![],
        diagnostics: snapshot.diagnostics.iter().map(diagnostic).collect(),
    }
}

fn without_synthetic_mount_roots(
    mut request: portable::DiscoveryRequest,
) -> portable::DiscoveryRequest {
    request
        .development_root
        .entries
        .remove(&portable::RelativePath::root());
    if let Some(tree) = &mut request.morphir_home {
        tree.entries.remove(&portable::RelativePath::root());
    }
    if let Some(tree) = &mut request.system_config {
        tree.entries.remove(&portable::RelativePath::root());
    }
    request
}

#[tokio::test]
async fn native_and_extension_providers_conform_to_the_shared_workspace_corpus() {
    let corpus: Vec<CorpusCase> = serde_json::from_str(CORPUS).unwrap();

    for name in REQUIRED_CASES {
        let case = corpus
            .iter()
            .find(|candidate| candidate.name == *name)
            .unwrap_or_else(|| panic!("shared workspace corpus is missing `{name}`"));
        let materialized = materialize(case);
        let provider_request = morphir_devkit::build_workspace_discovery_request(
            materialized.development_root.path(),
            &materialized.options,
        )
        .unwrap();
        assert_eq!(
            without_synthetic_mount_roots(provider_request.clone()),
            without_synthetic_mount_roots(case.request.clone()),
            "{name}"
        );
        let extension = ExtensionWorkspaceProvider::from_fixture(
            materialized.development_root.path(),
            "conformance",
            materialized.options.clone(),
            provider_request,
            case.expected.clone(),
        );
        let extension_source = extension.initial_sources().pop().unwrap();

        match &case.expected {
            portable::DiscoveryResponse::Success { snapshot } => {
                let native = NativeWorkspaceProvider::discover_for_test(
                    materialized.development_root.path(),
                    "conformance",
                    materialized.options.clone(),
                )
                .unwrap();
                let native_source = native.initial_sources().pop().unwrap();
                let expected = expected_ui_snapshot(&native_source, snapshot);
                let native_snapshot = native.open(&native_source).await.unwrap();
                let extension_snapshot = extension.open(&extension_source).await.unwrap();

                assert_eq!(native_source, extension_source, "{name}");
                assert_eq!(native_snapshot, expected, "native provider: {name}");
                assert_eq!(extension_snapshot, expected, "extension provider: {name}");
            }
            portable::DiscoveryResponse::Failure { error } => {
                let native_error = NativeWorkspaceProvider::discover_for_test(
                    materialized.development_root.path(),
                    "conformance",
                    materialized.options,
                )
                .err()
                .expect("native provider must preserve the corpus failure");
                assert_workspace_failure(native_error, error, name);
                assert_workspace_failure(
                    extension.open(&extension_source).await.unwrap_err(),
                    error,
                    name,
                );
            }
        }
    }
}

#[tokio::test]
async fn configured_workspace_name_does_not_change_provider_source_identity() {
    let root = tempfile::tempdir().unwrap();
    fs::write(
        root.path().join("morphir.toml"),
        "[workspace]\nname = \"Configured workspace\"\nmembers = []\n\n[project]\nname = \"acme/root\"\n",
    )
    .unwrap();
    let options = ConfigLoadOptions::project_only();
    let request = morphir_devkit::build_workspace_discovery_request(root.path(), &options).unwrap();
    let response = portable::discover(request.clone());
    let extension = ExtensionWorkspaceProvider::from_fixture(
        root.path(),
        "named-workspace",
        options.clone(),
        request,
        response,
    );
    let native =
        NativeWorkspaceProvider::discover_for_test(root.path(), "named-workspace", options)
            .unwrap();
    let extension_source = extension.initial_sources().pop().unwrap();
    let native_source = native.initial_sources().pop().unwrap();

    assert_eq!(native_source, extension_source);
    assert_eq!(
        native_source.display_name,
        root.path().file_name().unwrap().to_string_lossy()
    );
    assert_eq!(
        native.open(&native_source).await.unwrap().name.as_deref(),
        Some("Configured workspace")
    );
}

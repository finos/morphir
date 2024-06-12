pub use crate::config::MorphirManifest;
pub use crate::project::ProjectManifest;
pub use crate::workspace::config::WorkspaceManifest;
use toml::Table;

pub enum ManifestKind {
    Workspace,
    Project,
    Ambiguous,
}

impl ManifestKind {
    pub fn detect_from_toml_string(input: &str) -> Option<Self> {
        let manifest = input.parse::<Table>();
        if let Ok(manifest) = manifest {
            let workspace = manifest.get("workspace");
            let project = manifest.get("project");
            match (workspace, project) {
                (Some(_), Some(_)) => Some(ManifestKind::Ambiguous),
                (Some(_), None) => Some(ManifestKind::Workspace),
                _ => Some(ManifestKind::Project),
            }
        } else {
            None
        }
    }
}

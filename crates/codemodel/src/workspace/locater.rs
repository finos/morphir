use std::path::PathBuf;

use super::{WorkspaceConfigFilePath, WorkspaceRoot};
use tracing::debug;
pub type WorkspaceLocator = fn(&PathBuf) -> Option<(WorkspaceRoot, WorkspaceConfigFilePath)>;

pub fn morphir_workspace_locator(
    dir: &PathBuf,
) -> Option<(WorkspaceRoot, WorkspaceConfigFilePath)> {
    let root = WorkspaceRoot::new(dir.clone());
    let config_file_path = WorkspaceConfigFilePath(dir.join("morphir.toml"));
    if config_file_path.is_file() {
        debug!("Found a morphir.toml file at {:?}", config_file_path);
        let toml_contents = std::fs::read_to_string(&config_file_path);
        if let Ok(toml_contents) = toml_contents {
            let manifest_kind =
                crate::manifest::ManifestKind::detect_from_toml_string(&toml_contents);
            if let Some(manifest_kind) = manifest_kind {
                match manifest_kind {
                    crate::manifest::ManifestKind::Workspace => {
                        return Some((root, config_file_path));
                    }
                    _ => return None,
                }
            }
        }
    }
    None
}

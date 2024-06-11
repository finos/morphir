//use ::config::ConfigError;

use serde::{Deserialize, Serialize};

use crate::{project::ProjectManifest, workspace::config::WorkspaceManifest};

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum MorphirManifest {
    Workspace(WorkspaceManifest),
    Project(ProjectManifest),
}

impl MorphirManifest {
    pub fn is_workspace_manifest(&self) -> bool {
        matches!(self, MorphirManifest::Workspace(_))
    }

    pub fn is_project_manifest(&self) -> bool {
        matches!(self, MorphirManifest::Project { .. })
    }

    pub fn workspace(&self) -> Option<&WorkspaceManifest> {
        match self {
            MorphirManifest::Workspace(workspace) => Some(workspace),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ::config::{Config, ConfigError, File, FileFormat};
    use smoothy::*;
    use tracing::info;
    use tracing_test::traced_test;

    #[traced_test]
    #[test]
    fn test_manifest_workspace_toml() -> Result<(), ConfigError> {
        let manifest_source = r#"
            [workspace]
            members = ["proj-a", "proj-b"]
        "#;

        let manifest_file = File::from_str(manifest_source, FileFormat::Toml);

        let config = Config::builder().add_source(manifest_file).build()?;
        let manifest = config.try_deserialize::<MorphirManifest>()?;
        info!("manifest: {:?}", manifest);

        let manifest_toml = toml::to_string(&manifest);
        info!("manifest_toml: {:?}", manifest_toml);

        if let MorphirManifest::Workspace(workspace) = manifest {
            assert_that(&workspace.members).nth(0).is(&"proj-a".into());
            assert_that(&workspace.members).nth(1).is(&"proj-b".into());
        } else {
            panic!("Expected MorphirManifest::Workspace");
        }

        Ok(())
    }

    #[traced_test]
    #[test]
    fn test_manifest_project_toml() -> Result<(), ConfigError> {
        let manifest_source = r#"
            [project]
            name = "proj-a"
        "#;

        let manifest_file = File::from_str(manifest_source, FileFormat::Toml);

        let config = Config::builder().add_source(manifest_file).build()?;
        let manifest = config.try_deserialize::<MorphirManifest>()?;
        info!("manifest: {:?}", manifest);

        let manifest_toml = toml::to_string(&manifest);
        info!("manifest_toml: {:?}", manifest_toml);

        if let MorphirManifest::Project(project) = manifest {
            assert_that(project.name()).is(&"proj-a".into());
        } else {
            panic!("Expected MorphirManifest::Project");
        }

        Ok(())
    }
}

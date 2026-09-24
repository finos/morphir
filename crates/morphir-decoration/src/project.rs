//! A configured decorator's file boundary. Relative paths are confined to the
//! project directory; values and targets are checked before sidecar replacement.

use crate::sidecar::{DecorationSidecar, SidecarError};
use crate::value_type::{ValueTypeError, ValueValidator};
use morphir_core::ir::classic;
use morphir_core::naming::{PackageName, Path as IrPath};
use morphir_core::node_address::{ArtifactSelector, NodeCatalog, NodeIndex, NodeUri};
use serde::Deserialize;
use serde_json::Value;
use std::collections::BTreeMap;
use std::path::{Component, Path, PathBuf};

#[derive(Debug, thiserror::Error)]
pub enum ProjectError {
    #[error("project I/O at {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("invalid project config: {0}")]
    Config(String),
    #[error("invalid {kind} IR: {message}")]
    Ir { kind: &'static str, message: String },
    #[error(transparent)]
    Value(#[from] ValueTypeError),
    #[error(transparent)]
    Sidecar(#[from] SidecarError),
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DecorationConfig {
    #[serde(rename = "displayName")]
    _display_name: Option<String>,
    ir: String,
    entry_point: String,
    storage_location: String,
}

#[derive(Deserialize)]
struct ProjectConfig {
    #[serde(default)]
    decorations: BTreeMap<String, DecorationConfig>,
}

pub struct DecorationProject {
    pub name: String,
    pub sidecar_path: PathBuf,
    root: PathBuf,
    sidecar_relative: String,
    catalog: NodeCatalog,
    validator: ValueValidator,
    v3: Option<classic::Distribution>,
}

impl DecorationProject {
    /// Load `morphir.json`, the configured decoration IR and the target IR.
    /// The target IR is explicit so no stale compile output is inferred.
    pub fn open(config_path: &Path, name: &str, target_ir: &Path) -> Result<Self, ProjectError> {
        let root = config_root(config_path)?;
        let config_text =
            std::fs::read_to_string(config_path).map_err(|source| io(config_path, source))?;
        let config: ProjectConfig = serde_json::from_str(&config_text)
            .map_err(|error| ProjectError::Config(error.to_string()))?;
        let decoration = config.decorations.get(name).ok_or_else(|| {
            ProjectError::Config(format!("decoration {name:?} is not configured"))
        })?;
        let type_path = confined(&root, &decoration.ir)?;
        let sidecar_path = confined(&root, &decoration.storage_location)?;
        let type_text =
            std::fs::read_to_string(&type_path).map_err(|source| io(&type_path, source))?;
        let target_text =
            std::fs::read_to_string(target_ir).map_err(|source| io(target_ir, source))?;
        let target_value =
            morphir_core::ir::json::read(&target_text).map_err(|error| ProjectError::Ir {
                kind: "target",
                message: format!("{error:?}"),
            })?;
        let target_version = target_value.get("formatVersion").unwrap_or(&Value::Null);
        let is_v4 = target_version.as_u64() == Some(4) || target_version.as_str() == Some("4.0.0");
        let mut catalog = NodeCatalog::new();
        let v3 = if is_v4 {
            let (file, _) =
                morphir_core::ir::json::read_ir_file(&target_text).map_err(|error| {
                    ProjectError::Ir {
                        kind: "target",
                        message: error.to_string(),
                    }
                })?;
            let index = NodeIndex::v4_file(&file).map_err(|error| ProjectError::Ir {
                kind: "target",
                message: error.to_string(),
            })?;
            catalog.add_current(index);
            catalog
                .add_v4_json_snapshot(target_text.as_bytes(), None)
                .map_err(|error| ProjectError::Ir {
                    kind: "target",
                    message: error.to_string(),
                })?;
            None
        } else {
            let distribution: classic::Distribution =
                serde_json::from_str(&target_text).map_err(|error| ProjectError::Ir {
                    kind: "target",
                    message: error.to_string(),
                })?;
            let classic::DistributionBody::Library(package, _, _) = &distribution.distribution;
            let package_path = package
                .segments
                .iter()
                .map(ToString::to_string)
                .collect::<Vec<_>>()
                .join("/");
            let package = PackageName::new(IrPath::new(&package_path));
            let index = NodeIndex::v3(&distribution, ArtifactSelector::Package(package)).map_err(
                |error| ProjectError::Ir {
                    kind: "target",
                    message: error.to_string(),
                },
            )?;
            catalog.add_current(index);
            catalog
                .add_v3_json_snapshot(target_text.as_bytes(), None)
                .map_err(|error| ProjectError::Ir {
                    kind: "target",
                    message: error.to_string(),
                })?;
            Some(distribution)
        };
        let type_version = morphir_core::ir::json::read(&type_text)
            .map_err(|error| ProjectError::Ir {
                kind: "decoration type",
                message: format!("{error:?}"),
            })?
            .get("formatVersion")
            .cloned()
            .unwrap_or(Value::Null);
        let validator = match type_version {
            Value::Number(ref number) if number.as_u64() == Some(3) => {
                let distribution: classic::Distribution = serde_json::from_str(&type_text)
                    .map_err(|error| ProjectError::Ir {
                        kind: "decoration type",
                        message: error.to_string(),
                    })?;
                ValueValidator::v3(&distribution, &decoration.entry_point)?
            }
            Value::String(ref version) if version == "3.0.0" => {
                let distribution: classic::Distribution = serde_json::from_str(&type_text)
                    .map_err(|error| ProjectError::Ir {
                        kind: "decoration type",
                        message: error.to_string(),
                    })?;
                ValueValidator::v3(&distribution, &decoration.entry_point)?
            }
            _ => {
                let (file, _) =
                    morphir_core::ir::json::read_ir_file(&type_text).map_err(|error| {
                        ProjectError::Ir {
                            kind: "decoration type",
                            message: error.to_string(),
                        }
                    })?;
                ValueValidator::v4(&file.distribution, &decoration.entry_point)?
            }
        };
        Ok(Self {
            name: name.to_owned(),
            sidecar_path,
            root,
            sidecar_relative: decoration.storage_location.clone(),
            catalog,
            validator,
            v3,
        })
    }

    pub fn load(&self) -> Result<DecorationSidecar, ProjectError> {
        let path = self.checked_sidecar_path()?;
        let sidecar = DecorationSidecar::load(&path)?;
        self.validate(&sidecar)?;
        Ok(sidecar)
    }

    pub fn validate(&self, sidecar: &DecorationSidecar) -> Result<(), ProjectError> {
        for (text, value) in sidecar.targets() {
            let uri = NodeUri::parse(text).map_err(|error| SidecarError::InvalidTarget {
                target: text.clone(),
                reason: error.to_string(),
            })?;
            self.catalog
                .resolve_node(&uri)
                .map_err(|error| SidecarError::InvalidTarget {
                    target: text.clone(),
                    reason: error.to_string(),
                })?;
            self.validator.validate(value)?;
        }
        Ok(())
    }

    pub fn set(&self, target: NodeUri, value: Value) -> Result<(), ProjectError> {
        let path = self.checked_sidecar_path()?;
        let mut sidecar = match DecorationSidecar::load(&path) {
            Ok(sidecar) => sidecar,
            Err(SidecarError::Io { source, .. })
                if source.kind() == std::io::ErrorKind::NotFound =>
            {
                DecorationSidecar::empty()
            }
            Err(error) => return Err(error.into()),
        };
        sidecar.insert(target, value);
        let path = self.checked_sidecar_path()?;
        sidecar.save_typed_with_catalog(&path, &self.catalog, &self.validator)?;
        Ok(())
    }

    pub fn migrate_v3(&self) -> Result<(), ProjectError> {
        let distribution = self
            .v3
            .as_ref()
            .ok_or_else(|| ProjectError::Config("V3 migration requires a V3 target IR".into()))?;
        let path = self.checked_sidecar_path()?;
        let old = std::fs::read_to_string(&path).map_err(|source| io(&path, source))?;
        let classic::DistributionBody::Library(package, _, _) = &distribution.distribution;
        let package_path = package
            .segments
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>()
            .join("/");
        let index = NodeIndex::v3(
            distribution,
            ArtifactSelector::Package(PackageName::new(IrPath::new(&package_path))),
        )
        .map_err(|error| ProjectError::Ir {
            kind: "target",
            message: error.to_string(),
        })?;
        let migrated = DecorationSidecar::migrate_v3(&old, distribution, &index)?;
        let path = self.checked_sidecar_path()?;
        migrated.save_typed_with_catalog(&path, &self.catalog, &self.validator)?;
        Ok(())
    }

    fn checked_sidecar_path(&self) -> Result<PathBuf, ProjectError> {
        confined(&self.root, &self.sidecar_relative)
    }
}

fn io(path: &Path, source: std::io::Error) -> ProjectError {
    ProjectError::Io {
        path: path.display().to_string(),
        source,
    }
}

fn config_root(config_path: &Path) -> Result<PathBuf, ProjectError> {
    config_path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."))
        .canonicalize()
        .map_err(|source| io(config_path, source))
}

fn confined(root: &Path, relative: &str) -> Result<PathBuf, ProjectError> {
    let path = Path::new(relative);
    if path.as_os_str().is_empty()
        || path
            .components()
            .any(|part| !matches!(part, Component::Normal(_)))
    {
        return Err(ProjectError::Config(format!(
            "path {relative:?} must stay inside the project"
        )));
    }
    let joined = root.join(path);
    let mut ancestor = joined.as_path();
    while !ancestor.exists() {
        ancestor = ancestor.parent().ok_or_else(|| {
            ProjectError::Config(format!("path {relative:?} has no project ancestor"))
        })?;
    }
    let real = ancestor
        .canonicalize()
        .map_err(|source| io(ancestor, source))?;
    if !real.starts_with(root) {
        return Err(ProjectError::Config(format!(
            "path {relative:?} leaves the project"
        )));
    }
    Ok(joined)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bare_default_config_uses_the_current_directory() {
        assert_eq!(
            config_root(Path::new("morphir.json")).unwrap(),
            std::env::current_dir().unwrap()
        );
    }
}

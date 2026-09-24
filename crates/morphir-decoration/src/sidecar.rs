use crate::value_type::ValueValidator;
use morphir_core::ir::classic;
use morphir_core::node_address::{NodeCatalog, NodeIndex, NodeUri, convert_v3_node_id};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::io::Write;
use std::path::Path;

pub const FORMAT_VERSION: &str = "1.0.0-draft.1";

#[derive(Debug, thiserror::Error)]
pub enum SidecarError {
    #[error("sidecar I/O at {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },
    #[error("invalid sidecar JSON: {0}")]
    InvalidJson(String),
    #[error("unsupported sidecar format version: {0}")]
    UnsupportedVersion(String),
    #[error("invalid sidecar target '{target}': {reason}")]
    InvalidTarget { target: String, reason: String },
    #[error("duplicate semantic target after V3 conversion: {0}")]
    DuplicateTarget(String),
    #[error("invalid decoration value: {0}")]
    InvalidValue(String),
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DecorationSidecar {
    format_version: String,
    targets: BTreeMap<String, Value>,
}

impl DecorationSidecar {
    pub fn empty() -> Self {
        Self {
            format_version: FORMAT_VERSION.into(),
            targets: BTreeMap::new(),
        }
    }

    pub fn parse(text: &str) -> Result<Self, SidecarError> {
        let value = morphir_core::ir::json::read(text)
            .map_err(|error| SidecarError::InvalidJson(error.message))?;
        let sidecar: Self = serde_json::from_value(value)
            .map_err(|error| SidecarError::InvalidJson(error.to_string()))?;
        if sidecar.format_version != FORMAT_VERSION {
            return Err(SidecarError::UnsupportedVersion(sidecar.format_version));
        }
        for target in sidecar.targets.keys() {
            let uri = NodeUri::parse(target).map_err(|error| SidecarError::InvalidTarget {
                target: target.clone(),
                reason: error.to_string(),
            })?;
            if uri.to_string() != *target {
                return Err(SidecarError::InvalidTarget {
                    target: target.clone(),
                    reason: "sidecar URI key must use canonical spelling".into(),
                });
            }
        }
        Ok(sidecar)
    }

    pub fn load(path: &Path) -> Result<Self, SidecarError> {
        let text = std::fs::read_to_string(path).map_err(|source| SidecarError::Io {
            path: path.display().to_string(),
            source,
        })?;
        Self::parse(&text)
    }

    pub fn targets(&self) -> &BTreeMap<String, Value> {
        &self.targets
    }

    pub fn insert(&mut self, target: NodeUri, value: Value) {
        self.targets.insert(target.to_string(), value);
    }

    pub fn to_json(&self) -> Result<String, SidecarError> {
        serde_json::to_string_pretty(self)
            .map(|json| format!("{json}\n"))
            .map_err(|error| SidecarError::InvalidJson(error.to_string()))
    }

    /// Validate every target and value before touching the old file. The
    /// caller must use the loaded IR index and configured `entryPoint` type in
    /// this callback; storage cannot infer either from the JSON sidecar.
    fn save_validated(
        &self,
        path: &Path,
        validate: impl Fn(&NodeUri, &Value) -> Result<(), SidecarError>,
    ) -> Result<(), SidecarError> {
        for (text, value) in &self.targets {
            let uri = NodeUri::parse(text).map_err(|error| SidecarError::InvalidTarget {
                target: text.clone(),
                reason: error.to_string(),
            })?;
            validate(&uri, value)?;
        }
        let bytes = self.to_json()?;
        let parent = path.parent().unwrap_or_else(|| Path::new("."));
        std::fs::create_dir_all(parent).map_err(|source| SidecarError::Io {
            path: parent.display().to_string(),
            source,
        })?;
        let mut temp =
            tempfile::NamedTempFile::new_in(parent).map_err(|source| SidecarError::Io {
                path: parent.display().to_string(),
                source,
            })?;
        temp.write_all(bytes.as_bytes())
            .map_err(|source| SidecarError::Io {
                path: path.display().to_string(),
                source,
            })?;
        temp.as_file()
            .sync_all()
            .map_err(|source| SidecarError::Io {
                path: path.display().to_string(),
                source,
            })?;
        temp.persist(path).map_err(|error| SidecarError::Io {
            path: path.display().to_string(),
            source: error.error,
        })?;
        #[cfg(unix)]
        std::fs::File::open(parent)
            .and_then(|dir| dir.sync_all())
            .map_err(|source| SidecarError::Io {
                path: parent.display().to_string(),
                source,
            })?;
        Ok(())
    }

    /// Persist a working-artifact sidecar only when every URI resolves in the
    /// loaded V3 or V4 index and every value matches the configured type.
    pub fn save_for_index(
        &self,
        path: &Path,
        index: &NodeIndex,
        validate_value: impl Fn(&Value) -> Result<(), SidecarError>,
    ) -> Result<(), SidecarError> {
        self.save_validated(path, |uri, value| {
            index
                .resolve_node(uri)
                .map_err(|error| SidecarError::InvalidTarget {
                    target: uri.to_string(),
                    reason: error.to_string(),
                })?;
            validate_value(value)
        })
    }

    /// Persist only values accepted by the configured Morphir type entry point.
    pub fn save_typed(
        &self,
        path: &Path,
        index: &NodeIndex,
        validator: &ValueValidator,
    ) -> Result<(), SidecarError> {
        self.save_for_index(path, index, |value| {
            validator
                .validate(value)
                .map_err(|error| SidecarError::InvalidValue(error.to_string()))
        })
    }

    /// Also accepts revision-pinned targets when their exact verified snapshot
    /// has been registered in the resolver catalog.
    pub fn save_typed_with_catalog(
        &self,
        path: &Path,
        catalog: &NodeCatalog,
        validator: &ValueValidator,
    ) -> Result<(), SidecarError> {
        self.save_validated(path, |uri, value| {
            catalog
                .resolve_node(uri)
                .map_err(|error| SidecarError::InvalidTarget {
                    target: uri.to_string(),
                    reason: error.to_string(),
                })?;
            validator
                .validate(value)
                .map_err(|error| SidecarError::InvalidValue(error.to_string()))
        })
    }

    /// Convert all legacy V3 keys before writing anything. An unsupported,
    /// stale, or colliding key leaves the original sidecar untouched.
    pub fn migrate_v3(
        text: &str,
        distribution: &classic::Distribution,
        index: &NodeIndex,
    ) -> Result<Self, SidecarError> {
        let value = morphir_core::ir::json::read(text)
            .map_err(|error| SidecarError::InvalidJson(error.message))?;
        let old: BTreeMap<String, Value> = serde_json::from_value(value)
            .map_err(|error| SidecarError::InvalidJson(error.to_string()))?;
        let mut sidecar = Self::empty();
        for (key, value) in old {
            let uri = convert_v3_node_id(distribution, index, &key).map_err(|error| {
                SidecarError::InvalidTarget {
                    target: key.clone(),
                    reason: error.to_string(),
                }
            })?;
            let canonical = uri.to_string();
            if sidecar.targets.insert(canonical.clone(), value).is_some() {
                return Err(SidecarError::DuplicateTarget(canonical));
            }
        }
        Ok(sidecar)
    }
}

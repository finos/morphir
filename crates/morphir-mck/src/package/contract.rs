use super::json::{array, fields, nonempty};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{fmt, str::FromStr};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Contract {
    #[serde(rename = "0.1.0-draft.1")]
    Integrity,
    #[serde(rename = "0.1.0-draft.2")]
    Resolution,
}
impl Contract {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Integrity => "0.1.0-draft.1",
            Self::Resolution => "0.1.0-draft.2",
        }
    }
    pub fn operations(self) -> &'static [Operation] {
        match self {
            Self::Integrity => &[
                Operation::Normalize,
                Operation::HashBytes,
                Operation::Validate,
                Operation::VerifyLibrarySet,
            ],
            Self::Resolution => &[Operation::ResolveLibrary],
        }
    }
}
impl fmt::Display for Contract {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}
impl FromStr for Contract {
    type Err = String;
    fn from_str(value: &str) -> Result<Self, String> {
        match value {
            "0.1.0-draft.1" => Ok(Self::Integrity),
            "0.1.0-draft.2" => Ok(Self::Resolution),
            _ => Err(format!(
                "unsupported package contract {value}; expected 0.1.0-draft.1 or 0.1.0-draft.2"
            )),
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Operation {
    Normalize,
    HashBytes,
    Validate,
    VerifyLibrarySet,
    ResolveLibrary,
}
impl Operation {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Normalize => "normalize",
            Self::HashBytes => "hash-bytes",
            Self::Validate => "validate",
            Self::VerifyLibrarySet => "verify-library-set",
            Self::ResolveLibrary => "resolve-library",
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Artifact {
    Manifest,
    Lock,
}
#[derive(Debug, Clone, Serialize)]
pub struct Schemas {
    pub manifest: Value,
    pub lock: Value,
}
#[derive(Debug, Clone, Serialize)]
pub struct LibraryFile {
    pub path: String,
    pub hex: String,
}
#[derive(Debug, Clone, Serialize)]
pub struct Library {
    pub manifest: String,
    pub files: Vec<LibraryFile>,
}
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "op", rename_all = "kebab-case")]
pub enum Request {
    Normalize {
        input: String,
    },
    HashBytes {
        hex: String,
    },
    Validate {
        artifact: Artifact,
        input: String,
        schemas: Schemas,
    },
    VerifyLibrarySet {
        lock: String,
        libraries: Vec<Library>,
        schemas: Schemas,
    },
    ResolveLibrary {
        input: String,
    },
}
impl Request {
    pub fn operation(&self) -> Operation {
        match self {
            Self::Normalize { .. } => Operation::Normalize,
            Self::HashBytes { .. } => Operation::HashBytes,
            Self::Validate { .. } => Operation::Validate,
            Self::VerifyLibrarySet { .. } => Operation::VerifyLibrarySet,
            Self::ResolveLibrary { .. } => Operation::ResolveLibrary,
        }
    }
}
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Capabilities {
    suite: &'static str,
    pub contract_version: Contract,
    pub implementation: String,
    pub implementation_version: String,
    pub operations: Vec<Operation>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profiles: Option<Vec<String>>,
}
impl Capabilities {
    pub(super) fn parse(value: &Value, contract: Contract) -> Result<Self, String> {
        let names = if contract == Contract::Integrity {
            vec![
                "suite",
                "contractVersion",
                "implementation",
                "implementationVersion",
                "operations",
            ]
        } else {
            vec![
                "suite",
                "contractVersion",
                "implementation",
                "implementationVersion",
                "operations",
                "profiles",
            ]
        };
        fields(value, &names, &[])?;
        if value["suite"] != "package" || value["contractVersion"] != contract.as_str() {
            return Err("unsupported package adapter contract".into());
        }
        let operations: Vec<Operation> = array(&value["operations"])?
            .iter()
            .map(|value| {
                let op: Operation = serde_json::from_value(value.clone())
                    .map_err(|_| format!("unknown package operation {value}"))?;
                if !contract.operations().contains(&op) {
                    return Err(format!("unknown package operation {value}"));
                }
                Ok(op)
            })
            .collect::<Result<_, String>>()?;
        if operations
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len()
            != operations.len()
        {
            return Err("duplicate package capability".into());
        }
        let profiles = if contract == Contract::Resolution {
            let values = array(&value["profiles"])?;
            if values.len() > 1 || values.iter().any(|v| v != "flat-library") {
                return Err("unknown or duplicate package profile".into());
            }
            Some(values.iter().map(|_| "flat-library".to_owned()).collect())
        } else {
            None
        };
        Ok(Self {
            suite: "package",
            contract_version: contract,
            implementation: nonempty(&value["implementation"])?.into(),
            implementation_version: nonempty(&value["implementationVersion"])?.into(),
            operations,
            profiles,
        })
    }
    pub fn supports(&self, operation: Operation) -> bool {
        self.operations.contains(&operation)
            && (self.contract_version == Contract::Integrity
                || self
                    .profiles
                    .as_ref()
                    .is_some_and(|profiles| profiles.iter().any(|p| p == "flat-library")))
    }
}

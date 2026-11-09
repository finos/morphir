//! Version and `critical` rules shared by the five toolchain contracts.
//!
//! A reader lists the exact drafts it supports as SemVer requirements. A draft
//! matches only exactly, so `=0.1.0-draft.1` refuses `0.1.0-draft.2` and the
//! released `0.1.0`. Unknown members are ignored unless `critical` names them.

use crate::diagnostic::{Code, Diagnostic, Result};
use crate::reader::Node;
use semver::{Version, VersionReq};
use serde_json::Value;
use std::collections::BTreeSet;

/// The contract version every document in this crate writes.
pub const CONTRACT_VERSION: &str = "0.1.0-draft.1";

/// The versions this reader accepts, as SemVer requirements.
pub const SUPPORTED_VERSIONS: &[&str] = &["=0.1.0-draft.1"];

/// Check `schemaVersion` and `critical` before any other member is read.
pub(crate) fn check(root: &Value, understood: &[&str]) -> Result<()> {
    let object = Node::root(root).object()?;
    let version = object.req("schemaVersion", |node| {
        node.parse(Code::InvalidValue, |text| {
            Version::parse(text)
                .map_err(|error| format!("'{text}' is not a SemVer version: {error}"))
        })
    })?;
    let supported = SUPPORTED_VERSIONS.iter().any(|requirement| {
        VersionReq::parse(requirement)
            .expect("supported requirements are valid")
            .matches(&version)
    });
    if !supported {
        return Err(Diagnostic::new(
            Code::UnsupportedContractVersion,
            "schemaVersion",
            format!(
                "contract version {version} is not supported; this reader supports {}",
                SUPPORTED_VERSIONS.join(", ")
            ),
        ));
    }
    object.opt("critical", |node| {
        let paths = node.array(|item| item.str().map(str::to_owned))?;
        if paths.iter().collect::<BTreeSet<_>>().len() != paths.len() {
            return Err(Diagnostic::new(
                Code::InconsistentDocument,
                "critical",
                "critical member paths must be unique",
            ));
        }
        match paths
            .iter()
            .find(|path| !understood.contains(&path.as_str()))
        {
            Some(path) => Err(Diagnostic::new(
                Code::UnsupportedCriticalMember,
                path.as_str(),
                format!("critical member '{path}' is not understood by this reader"),
            )),
            None => Ok(()),
        }
    })?;
    Ok(())
}

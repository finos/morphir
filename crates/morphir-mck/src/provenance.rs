//! Driver and kit provenance collected for the consolidated draft report.
//! The historical sidecar writer has been retired.

use serde::Serialize;

use crate::kit::embedded::{DRIVER_DIRTY, PROVENANCE};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Driver {
    pub name: &'static str,
    pub version: &'static str,
    /// The commit this build came from, or `None` for a build with no Git
    /// metadata, such as one from a source archive.
    pub commit: Option<&'static str>,
    /// The Rust sources differed from `commit` at build time.
    pub dirty: bool,
}

impl Driver {
    /// This build.
    pub fn current() -> Self {
        Self {
            name: "morphir",
            version: env!("CARGO_PKG_VERSION"),
            commit: PROVENANCE.revision,
            dirty: DRIVER_DIRTY,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum KitSourceKind {
    Embedded,
    Vendored,
    Local,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KitProvenance {
    pub source: KitSourceKind,
    pub revision: Option<String>,
    /// The digest of every file a managed run uses, when the kit's full
    /// closure could be collected.
    pub snapshot_digest: Option<String>,
    /// The legacy corpus identity, when the kit has no errors.
    pub corpus_hash: Option<String>,
    /// Embedded: built from edited kit files. Local: differs from the kit
    /// embedded in this build. Vendored: always false, since it was verified.
    pub modified: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_driver_without_a_commit_is_never_reported_dirty_and_clean_at_once() {
        let driver = Driver::current();
        assert_eq!(driver.name, "morphir");
        if driver.commit.is_none() {
            assert!(!driver.dirty);
        }
    }
}

//! The provenance sidecar written beside a report (`spec/mck/cli-contract.md`,
//! "Provenance sidecar"; schema `spec/mck/provenance.schema.json`).
//!
//! IR report version 1 is closed, so what it cannot carry lives here: the
//! driver build that ran, the digests of the kit bytes that ran, and the
//! adapter command. A build from edited sources or with no commit to name
//! says so rather than claiming a clean commit.

use std::io;
use std::path::{Path, PathBuf};

use serde::Serialize;

use crate::kit::embedded::{DRIVER_DIRTY, PROVENANCE};

pub const PROVENANCE_VERSION: u32 = 1;

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

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AdapterProvenance {
    pub command: Vec<String>,
    /// `None` when the adapter never answered capabilities.
    pub binding: Option<String>,
    pub format_versions: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Provenance {
    pub provenance_version: u32,
    pub driver: Driver,
    pub kit: KitProvenance,
    pub adapter: AdapterProvenance,
}

impl Provenance {
    /// `<report>.provenance.json`.
    pub fn path_for(report: &Path) -> PathBuf {
        let mut name = report.as_os_str().to_owned();
        name.push(".provenance.json");
        PathBuf::from(name)
    }

    pub fn to_json(&self) -> String {
        format!("{}\n", crate::json::to_tab_json(self))
    }

    pub fn write_beside(&self, report: &Path) -> io::Result<PathBuf> {
        let path = Self::path_for(report);
        std::fs::write(&path, self.to_json())?;
        Ok(path)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_sidecar_sits_beside_its_report() {
        assert_eq!(
            Provenance::path_for(Path::new("out/rust.json")),
            PathBuf::from("out/rust.json.provenance.json")
        );
    }

    #[test]
    fn a_driver_without_a_commit_is_never_reported_dirty_and_clean_at_once() {
        let driver = Driver::current();
        assert_eq!(driver.name, "morphir");
        if driver.commit.is_none() {
            assert!(!driver.dirty);
        }
    }
}

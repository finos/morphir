//! `kit status`: what kit this is and whether it can be identified. Local
//! only; nothing here touches the network.

use std::io;
use std::path::Path;

use serde::Serialize;

use super::embedded::{PROVENANCE, embedded_source};
use super::hash::ALGORITHM;
use super::load::{Kit, load_kit};
use super::vendor::Managed;
use crate::DRIVER_CONTRACT;

pub use super::manifest::MANIFEST_NAME;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum KitMode {
    /// The kit compiled into this build.
    Embedded,
    /// A raw authoring checkout: used as is, never reported as an upstream snapshot.
    Local,
    /// A managed snapshot, verified against its `mck-kit.lock.json`.
    Vendored,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct KitStatus {
    pub mode: KitMode,
    pub label: String,
    /// The commit the kit was read from, when this build can prove it.
    pub revision: Option<String>,
    /// Embedded: the kit files differed from `revision` at build time.
    /// Local: the kit differs from the embedded kit.
    pub modified: bool,
    pub algorithm: &'static str,
    /// `None` when the kit has errors and so has no identity.
    pub corpus_hash: Option<String>,
    pub files: usize,
    pub cases: usize,
    pub errors: usize,
    /// The driver contract this CLI implements.
    pub driver_contract: u32,
    /// Vendored only: the manifest's source kind and full-inventory digest.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub snapshot_digest: Option<String>,
}

impl KitStatus {
    pub fn is_ok(&self) -> bool {
        self.errors == 0 && self.corpus_hash.is_some()
    }
}

/// True when `repo_root` holds a managed snapshot. A managed kit must be
/// verified against its manifest before use, never silently treated as raw.
pub fn is_managed(repo_root: Option<&Path>) -> bool {
    repo_root.is_some_and(|root| root.join(MANIFEST_NAME).exists())
}

pub fn embedded_status() -> io::Result<KitStatus> {
    let kit = load_kit(embedded_source())?;
    status_of(
        &kit,
        KitMode::Embedded,
        PROVENANCE.revision.map(str::to_owned),
        PROVENANCE.dirty,
    )
}

pub fn local_status(kit: &Kit) -> io::Result<KitStatus> {
    let embedded = load_kit(embedded_source())?.corpus_hash()?;
    let modified = kit.corpus_hash()? != embedded;
    let revision = if modified {
        None
    } else {
        PROVENANCE
            .revision
            .filter(|_| !PROVENANCE.dirty)
            .map(str::to_owned)
    };
    status_of(kit, KitMode::Local, revision, modified)
}

fn status_of(
    kit: &Kit,
    mode: KitMode,
    revision: Option<String>,
    modified: bool,
) -> io::Result<KitStatus> {
    Ok(KitStatus {
        mode,
        label: kit.source.label(),
        revision,
        modified,
        algorithm: ALGORITHM,
        corpus_hash: kit.corpus_hash()?.map(|digest| digest.as_str().to_owned()),
        files: kit.files.len(),
        cases: kit.cases.len(),
        errors: kit.errors.len(),
        driver_contract: DRIVER_CONTRACT,
        source: None,
        snapshot_digest: None,
    })
}

/// The status of a managed snapshot `open_managed` has already verified.
pub fn vendored_status(managed: &Managed) -> io::Result<KitStatus> {
    let lock = &managed.lock;
    let mut status = status_of(
        &managed.kit,
        KitMode::Vendored,
        lock.source.revision().map(|r| r.as_str().to_owned()),
        false,
    )?;
    status.label = managed.root.display().to_string();
    status.source = Some(lock.source.kind());
    status.snapshot_digest = Some(lock.snapshot_digest.as_str().to_owned());
    Ok(status)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kit::source::{KIT_PATH, KitSource};

    #[test]
    fn the_embedded_kit_has_an_identity() {
        let status = embedded_status().unwrap();
        assert!(status.is_ok(), "{status:?}");
        assert_eq!(status.mode, KitMode::Embedded);
        assert!(status.corpus_hash.unwrap().starts_with("sha256-"));
    }

    #[test]
    fn an_unedited_checkout_matches_the_embedded_kit_and_an_edited_one_does_not() {
        let checkout = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join(KIT_PATH);
        let kit = load_kit(KitSource::directory(&checkout, None)).unwrap();
        let status = local_status(&kit).unwrap();
        assert_eq!((status.mode, status.modified), (KitMode::Local, false));

        let copy = tempfile::tempdir().unwrap();
        let kit_dir = copy.path().join(KIT_PATH);
        std::fs::create_dir_all(&kit_dir).unwrap();
        std::fs::write(
            kit_dir.join("types.md"),
            "## types-0001: t\n```yaml canonical\na: 1\n```\n",
        )
        .unwrap();
        let edited =
            local_status(&load_kit(KitSource::directory(&kit_dir, None)).unwrap()).unwrap();
        assert!(edited.is_ok());
        assert_eq!((edited.modified, edited.revision), (true, None));
    }

    #[test]
    fn a_manifest_at_the_repository_root_marks_a_managed_kit() {
        let root = tempfile::tempdir().unwrap();
        assert!(!is_managed(Some(root.path())));
        assert!(!is_managed(None));
        std::fs::write(root.path().join(MANIFEST_NAME), "{}").unwrap();
        assert!(is_managed(Some(root.path())));
    }
}

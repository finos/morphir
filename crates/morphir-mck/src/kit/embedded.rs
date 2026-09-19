//! The IR kit compiled into this build, so checking and running the kit needs
//! no checkout, no network and no Git. The build script writes the file map.

use std::borrow::Cow;

use super::source::KitSource;

mod generated {
    include!(concat!(env!("OUT_DIR"), "/embedded_kit.rs"));
}

/// Which commit the embedded kit was read from. `revision` is `None` when the
/// build had no Git metadata (a source archive); `dirty` is true when the kit
/// files differed from that commit, so a build never claims a clean revision
/// it cannot prove.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EmbeddedProvenance {
    pub revision: Option<&'static str>,
    pub dirty: bool,
}

/// Whether the Rust sources this build came from differed from `revision`.
pub const DRIVER_DIRTY: bool = generated::DRIVER_DIRTY;

pub const PROVENANCE: EmbeddedProvenance = EmbeddedProvenance {
    revision: generated::REVISION,
    dirty: generated::DIRTY,
};

pub fn embedded_source() -> KitSource {
    let files = generated::FILES
        .iter()
        .map(|(path, bytes)| ((*path).to_owned(), Cow::Borrowed(*bytes)))
        .collect();
    KitSource::map("embedded kit", files)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kit::load::load_kit;
    use crate::kit::source::KIT_PATH;

    #[test]
    fn the_embedded_kit_is_the_checkout_kit_with_its_fixtures() {
        let embedded = load_kit(embedded_source()).unwrap();
        assert_eq!(embedded.errors, vec![]);

        let directory = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .join(KIT_PATH);
        let checkout = load_kit(KitSource::directory(&directory, None)).unwrap();
        assert_eq!(
            embedded.corpus_hash().unwrap(),
            checkout.corpus_hash().unwrap()
        );
        assert!(embedded.corpus_hash().unwrap().is_some());
    }

    #[test]
    fn a_revision_is_a_full_commit_id() {
        if let Some(revision) = PROVENANCE.revision {
            assert_eq!(revision.len(), 40);
            assert!(revision.bytes().all(|b| b.is_ascii_hexdigit()));
        }
    }

    /// An unknown revision has no dirty state to report.
    const _: () = assert!(PROVENANCE.revision.is_some() || !PROVENANCE.dirty);
}

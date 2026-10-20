//! Parent-selected immutable bytes from existing reviewed source receipts.
//! These views issue no digest, membership, lineage or runtime proof. The
//! verifier must check the fixed anchors and actual bytes using its own owner.
mod data;
mod identity_data;

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum SourceSet {
    Legacy,
    IdentityController,
    NativeFirst,
    InstalledClientFirst,
}
const INSTALLED_MANIFEST: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/installed-client-first-v1/source-manifest.json"
));
const INSTALLED_PAIRED: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/installed-client-first-v1/bundle-receipt.json"
));
const INSTALLED_FILE: &[(&str, &[u8])] = &[(
    "installed-client-first-v1/materialization.json",
    include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/installed-client-first-v1/materialization.json"
    )),
)];
const NATIVE_MANIFEST: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/native-original-first-v1/source-manifest.json"
));
const NATIVE_PAIRED: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/native-original-first-v1/bundle-receipt.json"
));
const NATIVE_FILES: &[(&str, &[u8])] = &[
    (
        "native-original-first-v1/input.json",
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/native-original-first-v1/input.json"
        )),
    ),
    (
        "native-original-first-v1/expected.json",
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/native-original-first-v1/expected.json"
        )),
    ),
];

const IDENTITY_PAIRED: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/identity-controller-source-pairs-v3/reviewed-addition-receipt.json"
));
const IDENTITY_MANIFEST: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/identity-controller-source-pairs-v3/source-manifest.json"
));

const ACCEPTANCE: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/provenance.json"
));
const PAIRED: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/paired-source-corpus-v1/receipt.json"
));
const MANIFEST: &[u8] = include_bytes!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/paired-source-corpus-v1/source-manifest.json"
));

macro_rules! original {
    ($path:literal) => {
        (
            $path,
            include_bytes!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../spec/workbench/model-originals/0.1.0-draft.1/acceptance/",
                $path
            )) as &[u8],
        )
    };
}

const ORIGINAL_FILES: &[(&str, &[u8])] = &[
    original!("wire49.json"),
    original!("preceding60.json"),
    original!("preceding35.json"),
    original!("discovery7.json"),
];

struct Replacement<'source> {
    path: &'source str,
    bytes: &'source [u8],
}

pub(super) struct ReviewedSources<'source> {
    set: SourceSet,
    replacements: Vec<Replacement<'source>>,
}

pub(super) struct FileView<'view> {
    path: &'view str,
    bytes: &'view [u8],
}

impl<'view> FileView<'view> {
    pub(super) fn path(&self) -> &'view str {
        self.path
    }
    pub(super) fn bytes(&self) -> &'view [u8] {
        self.bytes
    }
}

impl<'source> ReviewedSources<'source> {
    /// The caller can select only this compiled reviewed source set. No
    /// expected digest or arbitrary source-file table enters through this API.
    pub(super) fn selected() -> Self {
        Self {
            set: SourceSet::Legacy,
            replacements: Vec::new(),
        }
    }
    pub(super) fn native_selected() -> Self {
        Self {
            set: SourceSet::NativeFirst,
            replacements: Vec::new(),
        }
    }
    pub(super) fn installed_client_selected() -> Self {
        Self {
            set: SourceSet::InstalledClientFirst,
            replacements: Vec::new(),
        }
    }

    /// A second fixed parent-selected bundle; it cannot accept hashes, paths
    /// or caller bytes. Historical selected() remains the unchanged old23 set.
    pub(super) fn identity_selected() -> Self {
        Self {
            set: SourceSet::IdentityController,
            replacements: Vec::new(),
        }
    }
    pub(super) fn source_set(&self) -> SourceSet {
        self.set
    }

    fn supplied<'view>(&'view self, path: &str, compiled: &'static [u8]) -> &'view [u8] {
        match self
            .replacements
            .iter()
            .find(|replacement| replacement.path == path)
        {
            Some(replacement) => replacement.bytes,
            _ => compiled,
        }
    }

    pub(super) fn acceptance_receipt(&self) -> &[u8] {
        self.supplied("acceptance/provenance.json", ACCEPTANCE)
    }
    pub(super) fn paired_receipt(&self) -> &[u8] {
        match self.set {
            SourceSet::Legacy => self.supplied("paired-source-corpus-v1/receipt.json", PAIRED),
            SourceSet::IdentityController => self.supplied(
                "identity-controller-source-pairs-v3/reviewed-addition-receipt.json",
                IDENTITY_PAIRED,
            ),
            SourceSet::NativeFirst => self.supplied(
                "native-original-first-v1/bundle-receipt.json",
                NATIVE_PAIRED,
            ),
            SourceSet::InstalledClientFirst => self.supplied(
                "installed-client-first-v1/bundle-receipt.json",
                INSTALLED_PAIRED,
            ),
        }
    }
    pub(super) fn manifest(&self) -> &[u8] {
        match self.set {
            SourceSet::Legacy => {
                self.supplied("paired-source-corpus-v1/source-manifest.json", MANIFEST)
            }
            SourceSet::IdentityController => self.supplied(
                "identity-controller-source-pairs-v3/source-manifest.json",
                IDENTITY_MANIFEST,
            ),
            SourceSet::NativeFirst => self.supplied(
                "native-original-first-v1/source-manifest.json",
                NATIVE_MANIFEST,
            ),
            SourceSet::InstalledClientFirst => self.supplied(
                "installed-client-first-v1/source-manifest.json",
                INSTALLED_MANIFEST,
            ),
        }
    }
    pub(super) fn files(&self) -> impl Iterator<Item = FileView<'_>> {
        ORIGINAL_FILES
            .iter()
            .chain(data::AUTHORED_FILES)
            .chain(match self.set {
                SourceSet::Legacy => &[][..],
                SourceSet::IdentityController => identity_data::IDENTITY_FILES,
                SourceSet::NativeFirst | SourceSet::InstalledClientFirst => NATIVE_FILES,
            })
            .chain(if self.set == SourceSet::InstalledClientFirst {
                INSTALLED_FILE
            } else {
                &[][..]
            })
            .map(|(path, bytes)| FileView {
                path,
                bytes: self.supplied(path, bytes),
            })
    }

    /// Test transport changes supplied bytes while the verifier's reviewed
    /// anchor constants remain fixed. Production cannot construct a replacement.
    #[cfg(test)]
    pub(super) fn with_replacement(mut self, path: &'source str, bytes: &'source [u8]) -> Self {
        match self
            .replacements
            .iter_mut()
            .find(|replacement| replacement.path == path)
        {
            Some(replacement) => replacement.bytes = bytes,
            None => self.replacements.push(Replacement { path, bytes }),
        }
        self
    }
}

#[cfg(test)]
mod tests;

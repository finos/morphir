//! Exact byte views generated from the SAME frozen new3 manifest rows.
//! No semantic packet/role registry or runtime file reads.
macro_rules! identity_file {
    ($path:literal) => {
        (
            $path,
            include_bytes!(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../spec/workbench/model-originals/0.1.0-draft.1/reviewed-sources/",
                $path
            )) as &[u8],
        )
    };
}
pub(super) const IDENTITY_FILES: &[(&str, &[u8])] = &[
    identity_file!(
        "identity-controller-source-pairs-v3/cases/identity-provider-separation/input.json"
    ),
    identity_file!(
        "identity-controller-source-pairs-v3/cases/identity-provider-separation/expected.json"
    ),
    identity_file!(
        "identity-controller-source-pairs-v3/cases/identity-label-and-persistence-do-not-rekey/input.json"
    ),
    identity_file!(
        "identity-controller-source-pairs-v3/cases/identity-label-and-persistence-do-not-rekey/expected.json"
    ),
    identity_file!(
        "identity-controller-source-pairs-v3/cases/identity-same-name-distinct-project-paths/input.json"
    ),
    identity_file!(
        "identity-controller-source-pairs-v3/cases/identity-same-name-distinct-project-paths/expected.json"
    ),
];

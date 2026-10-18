//! Downstream bindings name exact HTTP kits through the public Workbench API.
use morphir_mck::workbench::{
    HTTP_POLICY_BOUNDARY_VERSION, HTTP_POLICY_CLIENT_VERSION, HTTP_POLICY_PROVIDER_VERSION,
};

#[test]
fn http_policy_versions_are_available_to_downstream_bindings() {
    assert_eq!(
        [
            HTTP_POLICY_BOUNDARY_VERSION,
            HTTP_POLICY_CLIENT_VERSION,
            HTTP_POLICY_PROVIDER_VERSION
        ],
        ["0.1.0-draft.23", "0.1.0-draft.24", "0.1.0-draft.25"],
    );
}

#[test]
fn codec_comparison_version_is_available_to_downstream_bindings() {
    assert_eq!(
        morphir_mck::workbench::CODEC_COMPARISON_VERSION,
        "0.1.0-draft.26"
    );
}

#[test]
fn worksheet_version_is_available_to_downstream_bindings() {
    assert_eq!(
        morphir_mck::workbench::WORKSHEET_PROFILE_VERSION,
        "0.1.0-draft.1"
    );
    assert_eq!(morphir_mck::workbench::WORKSHEET_VERSION, "0.1.0-draft.27");
}

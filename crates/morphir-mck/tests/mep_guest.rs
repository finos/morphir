use morphir_mck::mep::{check_report, load_kit};
use std::path::Path;

#[test]
fn shared_guest_profile_has_independent_semantics_and_no_observations() {
    let kit = load_kit(
        &Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/mep/mck/guest-moonbit-bool.json"),
    )
    .unwrap();
    assert_eq!(kit.profile(), "moonbit-model-bool-library-v1");
    assert!(kit.case_ids().len() >= 18);
    assert!(kit.case_ids().contains(&"legacy-initialize"));
    assert!(kit.case_ids().contains(&"narrow-initialize"));
    assert!(check_report(&kit, &serde_json::json!({"qualified":true})).is_err());
}

#[test]
fn guest_profile_requires_exact_draft_contract_and_fixed_expected_ir() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("kit.json");
    std::fs::write(
        &path,
        r#"{"contractVersion":"0.1.0-draft.2","profile":"moonbit-model-bool-library-v1"}"#,
    )
    .unwrap();
    assert!(load_kit(&path).is_err());
}

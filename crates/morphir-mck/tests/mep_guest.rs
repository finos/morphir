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

#[test]
fn both_artifact_expectation_maps_require_the_complete_inventory() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("kit.json");
    let original: serde_json::Value = serde_json::from_str(include_str!(
        "../../../spec/mep/mck/guest-moonbit-bool.json"
    ))
    .unwrap();
    for field in ["expectedArtifacts", "expectedJsonArtifacts"] {
        for missing in ["library.mbt", "moon.mod", "moon.pkg"] {
            let mut value = original.clone();
            value[field].as_object_mut().unwrap().remove(missing);
            std::fs::write(&path, value.to_string()).unwrap();
            assert!(
                load_kit(&path).is_err(),
                "accepted {field} without {missing}"
            );
        }
    }
}

#[test]
fn python_json_profile_has_separate_complete_inventory() {
    let kit = load_kit(
        &Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/mep/mck/guest-python-json.json"),
    )
    .unwrap();
    assert_eq!(kit.profile(), "python-json-library-v1");
    for case in [
        "compile-json-vthree",
        "compile-json-vfour",
        "compile-model-vthree",
        "compile-model-vfour",
        "generate-model-vthree",
        "generate-model-vfour",
        "id-u64-max",
        "id-string",
        "legacy-initialize",
        "bounded-request-cannot-widen",
        "unsupported-ion",
        "unsupported-distribution",
        "bad-version",
    ] {
        assert!(kit.case_ids().contains(&case), "missing {case}");
    }
    assert!(check_report(&kit, &serde_json::json!({"qualified":true})).is_err());
}

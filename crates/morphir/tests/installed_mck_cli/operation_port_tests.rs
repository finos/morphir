//! Actual frozen014 with explicit new mode must stay incomplete without hooks.
//! Existing two absent-mode qualification bodies remain byte-for-byte intact.
use super::*;
fn actual_unhooked_mode(target: Target) {
    let inputs = Inputs::from_environment(target);
    let mut setup = Setup::new(&inputs);
    assert_eq!(
        setup.configuration.consumer_observation(),
        morphir_mck::workbench::ConsumerObservationSelection::Disabled
    );
    let original: Value = serde_json::from_str(&setup.policy_text).unwrap();
    assert!(original.get("consumerObservation").is_none());
    let mut selected = original.clone();
    selected["consumerObservation"] = json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut restored = selected.clone();
    restored
        .as_object_mut()
        .unwrap()
        .remove("consumerObservation");
    assert_eq!(restored, original);
    setup.policy_text = selected.to_string();
    setup.configuration = RunConfiguration::from_json(&setup.policy_text).unwrap();
    fs::write(&setup.policy, &setup.policy_text).unwrap();
    let path = setup.root.path().join("unhooked-operation-report.json");
    let output = execute(
        setup.run(&inputs, target, &path),
        setup.root.path(),
        "unhooked-operation",
    );
    // execute actually reaps the CLI before report assertions. The adapter
    // owns genuine child/reader/socket/capture cleanup, never this harness.
    assert_eq!(output.status.code(), Some(1), "{}", output.stderr);
    let raw = bounded_text(&path, morphir_mck::workbench::MAX_REPORT_BYTES as u64);
    let report = Report::from_json(&raw).unwrap();
    assert!(!report.qualified());
    let measured: Value = serde_json::from_str(&raw).unwrap();
    assert_eq!(measured["qualified"], false);
    assert_eq!(measured["errors"][0]["phase"], "installed-consumer");
    assert_eq!(measured["errors"][0]["code"], "framing");
    assert!(
        measured["records"]
            .as_array()
            .unwrap()
            .iter()
            .all(|row| row["evidence"]
                .get("measurement")
                .is_none_or(Value::is_null)),
        "missing operation hooks must not fabricate completed measurement DATA"
    );
    assert_eq!(fs::read(setup.kit.join("cases.json")).unwrap(), CASES);
    assert_eq!(
        fs::read_to_string(&setup.policy).unwrap(),
        setup.policy_text
    );
    assert_eq!(fs::read_to_string(&path).unwrap(), raw);
}
#[test]
#[ignore = "requires same explicit installed5inputs; frozen014 has no operation hooks"]
fn actual_unhooked_installed_node_cannot_complete_explicit_operation_port_mode() {
    actual_unhooked_mode(Target::Node)
}
#[test]
#[ignore = "requires same explicit installed5inputs; frozen014 has no operation hooks"]
fn actual_unhooked_installed_native_cannot_complete_explicit_operation_port_mode() {
    actual_unhooked_mode(Target::Native)
}

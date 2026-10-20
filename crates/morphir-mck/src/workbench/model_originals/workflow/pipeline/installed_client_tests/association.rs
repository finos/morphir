//! Synthetic UNIT DATA relationship controls. No child/host execution,
//! executable authenticity, source build provenance or campaign-role credit.
//! Mount as child `association` of existing installed_client_tests::factual.
use super::*;

fn native_data() -> Value {
    let mut data = unit_data();
    data["implementation"]["launch"] = json!({
        "kind":"native-executable", "program":operand("/unit-native/morphir"),
        "byteLength":6,
        "sha256":include_str!("association_controls/vectors.json")
            .parse::<Value>().unwrap()["nativeSha256"]
    });
    for process in data["processes"].as_array_mut().unwrap() {
        process["program"] = operand("/unit-native/morphir");
        process["arguments"].as_array_mut().unwrap().remove(0);
    }
    data
}
fn operand(value: &str) -> Value {
    json!({"kind":"unix-bytes","bytes":{"kind":"utf8","text":value}})
}

#[test]
fn a01_explicit_synthetic_node_and_native_relationships_reach_only_expected_blocked() {
    for data in [unit_data(), native_data()] {
        assert_eq!(evaluate(&data), ObservationError::ExpectedBlocked);
        replay(&blocked_report(&data)).unwrap();
    }
}

#[test]
fn a02_missing_or_unobserved_implementation_cannot_use_expected_blocked_as_validation() {
    let mut data = unit_data();
    data.as_object_mut().unwrap().remove("implementation");
    decode_refuses(&data);
    let mut data = unit_data();
    data["implementation"] = json!({"kind":"unobserved"});
    assert_factual(&data, InstalledClientFault::ImplementationMissing);
}

#[test]
fn a03_association_must_precede_first_canonical_action() {
    let mut data = unit_data();
    data["implementation"]["beforeAction"] = json!(3);
    assert_factual(&data, InstalledClientFault::ImplementationBinding);
}

#[test]
fn a04_actual_program_and_resolved_canonical_argv_are_bound() {
    let mut data = unit_data();
    let first = data["processes"][0]["arguments"].clone();
    data["processes"][0]["arguments"] = data["processes"][1]["arguments"].clone();
    data["processes"][1]["arguments"] = first;
    assert_factual(&data, InstalledClientFault::ImplementationProcess);
    let mut data = unit_data();
    data["processes"][0]["program"] = operand("/other-node");
    assert_factual(&data, InstalledClientFault::ImplementationProcess);
    let mut data = unit_data();
    data["processes"][2]["arguments"][0] = operand("/other-package/bin/morphir.js");
    assert_factual(&data, InstalledClientFault::ImplementationProcess);
    let mut data = native_data();
    data["processes"][0]["arguments"]
        .as_array_mut()
        .unwrap()
        .insert(0, operand("/arbitrary-prefix"));
    assert_factual(&data, InstalledClientFault::ImplementationProcess);
}

#[test]
fn a05_metadata_and_sut_ordinals_actual_directory_and_tool_commands_are_distinct() {
    for (pointer, replacement) in [
        ("/processes/0/processOrdinal", json!(0)),
        ("/implementation/metadataTools/1/processOrdinal", json!(0)),
        (
            "/implementation/metadataTools/0/directory",
            operand("/other-source"),
        ),
        (
            "/implementation/metadataTools/1/program",
            operand("/other-git"),
        ),
        (
            "/implementation/metadataTools/0/arguments/0",
            operand("status"),
        ),
        (
            "/implementation/metadataTools/0/query",
            json!("tracked-status"),
        ),
        (
            "/implementation/metadataTools/0/completion/exit/value",
            json!(1),
        ),
    ] {
        let mut data = unit_data();
        *data.pointer_mut(pointer).unwrap() = replacement;
        assert_factual(&data, InstalledClientFault::ImplementationProcess);
    }
}

#[test]
fn a06_package_and_source_census_digests_are_recomputed_from_descriptors() {
    for pointer in [
        "/implementation/package/sha256",
        "/implementation/source/sha256",
        "/implementation/package/entries/0/sha256",
        "/implementation/source/entries/1/sha256",
    ] {
        let mut data = unit_data();
        *data.pointer_mut(pointer).unwrap() = json!("00".repeat(32));
        assert_factual(&data, InstalledClientFault::ImplementationDigest);
    }
}

#[test]
fn a07_actual_git_revision_inventory_and_status_must_match_source_claims() {
    for (pointer, replacement) in [
        ("/implementation/source/head", json!("bb".repeat(20))),
        ("/implementation/source/objectFormat", json!("sha256")),
        ("/implementation/source/trackedStatus", json!("changed")),
        (
            "/implementation/metadataTools/1/stdout/text",
            json!("100644 1111111111111111111111111111111111111111 0\tmodel.mbt\u{0}"),
        ),
    ] {
        let mut data = unit_data();
        *data.pointer_mut(pointer).unwrap() = replacement;
        assert_factual(&data, InstalledClientFault::ImplementationBinding);
    }
    let mut data = unit_data();
    data["implementation"]["source"]["root"] = operand("/other-source");
    for tool in data["implementation"]["metadataTools"]
        .as_array_mut()
        .unwrap()
    {
        tool["directory"] = operand("/other-source");
    }
    // Directory agreement remains valid; real revision stdout still names
    // /unit-source and therefore contradicts the new root claim.
    assert_factual(&data, InstalledClientFault::ImplementationBinding);
}

#[test]
fn a08_source_symlinks_are_literal_targets_and_git_modes_are_not_file_claims() {
    for (field, replacement) in [
        ("targetBytes", json!({"kind":"utf8","text":"other.mbt"})),
        ("byteLength", json!(8)),
    ] {
        let mut data = unit_data();
        data["implementation"]["source"]["entries"][0][field] = replacement;
        assert_factual(&data, InstalledClientFault::ImplementationDigest);
    }
    let mut data = unit_data();
    let link = &mut data["implementation"]["source"]["entries"][0];
    link["kind"] = json!("file");
    link["mode"] = json!("regular");
    link.as_object_mut().unwrap().remove("targetBytes");
    // Independently authored valid alternate digest isolates the kind/mode
    // mismatch against actual synthetic Git inventory mode120000.
    data["implementation"]["source"]["sha256"] = include_str!("association_controls/vectors.json")
        .parse::<Value>()
        .unwrap()["sourceAsFileSha256"]
        .clone();
    assert_factual(&data, InstalledClientFault::ImplementationBinding);
}

#[test]
fn a09_saved_replay_rechecks_relationships_before_unchanged_blocked_verdict() {
    let mut report: Value = serde_json::from_str(&blocked_report(&unit_data())).unwrap();
    let data = &mut report["records"][0]["evidence"]["measurement"];
    assert!(data["implementation"].is_object());
    data["implementation"]["beforeAction"] = json!(3);
    // Exact live first fault is new association failure, not the frozen
    // ExpectedBlocked. Same saved replay must reject the stale first failure.
    assert_factual(data, InstalledClientFault::ImplementationBinding);
    let failure = replay(&report.to_string()).unwrap_err();
    assert!(failure.contains("saved first failure differs"), "{failure}");
}

//! SYNTHETIC unit DATA successor only. Actual spec cwd and confined argv must
//! relate to the observed physical destination, not an invented client result.
//! Child of existing installed_client_tests::factual; original F01-F12/A01-A09 unchanged.
use super::*;

fn operand(text: &str) -> Value {
    json!({"kind":"unix-bytes","bytes":{"kind":"utf8","text":text}})
}
fn output(data: &mut Value, text: &str) {
    data["implementation"]["commandPaths"]["destination"] = operand(text);
    let args = data["processes"][2]["arguments"].as_array_mut().unwrap();
    assert_eq!(args[6], operand("--output"));
    args[7] = operand(text);
}

#[test]
fn d01_real_cwd_plus_relative_operand_matches_observed_root_and_saved_replay() {
    let data = unit_data();
    for process in data["processes"].as_array().unwrap() {
        assert_eq!(process["directory"], operand("/"));
    }
    assert_eq!(
        data["implementation"]["commandPaths"]["destination"],
        operand("unit-output")
    );
    assert_eq!(data["destination"]["root"], json!("/unit-output"));
    assert_eq!(evaluate(&data), ObservationError::ExpectedBlocked);
    replay(&blocked_report(&data)).unwrap();
}
#[test]
fn d02_every_actual_process_directory_is_required() {
    for index in 0..3 {
        let mut data = unit_data();
        data["processes"][index]
            .as_object_mut()
            .unwrap()
            .remove("directory");
        decode_refuses(&data);
    }
}
#[test]
fn d03_nonabsolute_or_disagreeing_actual_canonical_directory_is_process_fault() {
    for replacement in ["relative-cwd", "/other-cwd"] {
        let mut data = unit_data();
        data["processes"][1]["directory"] = operand(replacement);
        assert_factual(&data, InstalledClientFault::ImplementationProcess);
    }
}
#[test]
fn d04_consistently_wrong_actual_cwd_cannot_match_physical_destination() {
    let mut data = unit_data();
    for process in data["processes"].as_array_mut().unwrap() {
        process["directory"] = operand("/elsewhere");
    }
    assert_factual(&data, InstalledClientFault::ImplementationBinding);
}
#[test]
fn d05_absolute_or_escaping_output_is_refused_even_when_argv_matches_claim() {
    for replacement in [
        "/unit-output",
        "../unit-output",
        "unit-output/../outside",
        ".",
        "",
    ] {
        let mut data = unit_data();
        output(&mut data, replacement);
        assert_factual(&data, InstalledClientFault::ImplementationProcess);
    }
}
#[test]
fn d06_existing_stdout_consistency_does_not_replace_cwd_to_snapshot_root_binding() {
    let mut data = unit_data();
    data["destination"]["root"] = json!("/other-unit-output");
    stdout_change(&mut data, 2, |claim| {
        claim["published"][0] = json!("/other-unit-output/originals")
    });
    // Old process stdout/destination predicates stay satisfied. Only the new
    // relation '/' + 'unit-output' != '/other-unit-output' must refuse.
    assert_factual(&data, InstalledClientFault::ImplementationBinding);
}
#[test]
fn d07_publish_actual_relative_argv_must_equal_source_resolved_output_operand() {
    let mut data = unit_data();
    data["processes"][2]["arguments"][7] = operand("other-output");
    assert_factual(&data, InstalledClientFault::ImplementationProcess);
    let mut report: Value = serde_json::from_str(&blocked_report(&unit_data())).unwrap();
    let measurement = &mut report["records"][0]["evidence"]["measurement"];
    measurement["processes"][1]["directory"] = operand("/other-cwd");
    assert_factual(measurement, InstalledClientFault::ImplementationProcess);
    let error = replay(&report.to_string()).unwrap_err();
    assert!(error.contains("saved first failure differs"), "{error}");
}

#[test]
fn d08_actual_relative_stdout_resolves_under_same_cwd_without_granting_paths() {
    let mut data = unit_data();
    stdout_change(&mut data, 2, |claim| {
        claim["published"][0] = json!("unit-output/originals")
    });
    assert_eq!(evaluate(&data), ObservationError::ExpectedBlocked);
    replay(&blocked_report(&data)).unwrap();
    // Existing absolute stdout positive remains d01. Neither representation
    // grants the snapshot root; source-issued cwd/output must identify it.
    for path in [
        "unit-other/originals",
        "../unit-output/originals",
        "unit-output/../other",
        "/unit-other/originals",
    ] {
        let mut data = unit_data();
        stdout_change(&mut data, 2, |claim| claim["published"][0] = json!(path));
        assert_factual(&data, InstalledClientFault::ProcessClaims);
    }
}

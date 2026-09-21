//! Fixed contract fixture and hostile-input coverage, independent of the writer.
#[test]
fn draft_schema_is_a_separate_closed_contract() {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../spec/ir/mck/report-draft.schema.json");
    assert!(
        path.exists(),
        "draft report schema must be published separately"
    );
}

use morphir_mck::report::draft::{DraftReport, Negotiation, Session};
use serde_json::{Value, json};

fn example() -> Value {
    serde_json::from_str(include_str!(
        "../../../spec/ir/mck/report-draft.example.json"
    ))
    .unwrap()
}

fn read(value: Value) -> Result<DraftReport, morphir_mck::report::draft::ReportError> {
    DraftReport::from_json(&value.to_string())
}

#[test]
fn fixed_example_round_trips_and_exposes_typed_data() {
    let report = read(example()).unwrap();
    assert_eq!(report.summary().pass, 1);
    let Negotiation::Succeeded { capabilities } = &report.adapter.negotiation else {
        panic!("fixed example must negotiate capabilities");
    };
    assert_eq!(capabilities.as_capabilities().binding, "morphir-example");
    assert!(matches!(report.execution.session, Session::Finished));
    assert_eq!(
        serde_json::from_str::<Value>(&report.to_json()).unwrap(),
        example()
    );
}

#[test]
fn rejects_other_contract_versions_and_unknown_fields() {
    for version in [json!(1), json!(2), json!("2.0.0"), json!("2.0.0-draft.2")] {
        let mut value = example();
        value["contractVersion"] = version;
        assert!(read(value).is_err());
    }
    for pointer in [
        "",
        "/driver",
        "/kit",
        "/adapter",
        "/adapter/negotiation",
        "/adapter/negotiation/capabilities",
        "/selection",
        "/execution",
        "/execution/session",
        "/records/0",
    ] {
        let mut value = example();
        value
            .pointer_mut(pointer)
            .unwrap()
            .as_object_mut()
            .unwrap()
            .insert("unexpected".into(), json!(true));
        assert!(read(value).is_err(), "unknown field accepted at {pointer}");
    }
}

#[test]
fn rejects_invalid_timestamps_record_ids_durations_and_commands() {
    for (pointer, bad) in [
        ("/startedAt", json!("yesterday")),
        ("/startedAt", json!("2026-02-30T00:00:00Z")),
        ("/records/0/caseId", json!("../../hostile-0001")),
        ("/records/0/durationMs", json!(-0.1)),
        ("/records/0/irVersion", json!(0)),
        ("/records/0/path", json!(null)),
        ("/adapter/command", json!([])),
        ("/adapter/command", json!([""])),
        ("/adapter/command", json!(["", "adapter"])),
    ] {
        let mut value = example();
        *value.pointer_mut(pointer).unwrap() = bad;
        assert!(read(value).is_err(), "accepted invalid {pointer}");
    }
}

#[test]
fn capability_support_tables_are_checked_semantically() {
    for (field, bad) in [
        ("formatVersions", json!("unknown")),
        ("formatVersions", json!("[4.0.0, 4.1.0)")),
        ("versions", json!([3, 4])),
        ("versions", json!([])),
    ] {
        let mut value = example();
        value["adapter"]["negotiation"]["capabilities"][field] = bad;
        assert!(read(value).is_err(), "accepted invalid {field}");
    }
}

#[test]
fn filters_use_valid_rust_regex_and_reject_other_syntax() {
    let mut value = example();
    value["selection"] = json!({"kind":"filter","syntax":"rust-regex","pattern":"^types-"});
    assert!(read(value.clone()).is_ok());
    value["selection"]["pattern"] = json!("(?=lookahead)");
    assert!(read(value.clone()).is_err());
    value["selection"]["pattern"] = json!("^types-");
    value["selection"]["syntax"] = json!("javascript");
    assert!(read(value).is_err());
}

#[test]
fn negotiation_and_session_failures_must_agree() {
    let mut value = example();
    value["adapter"]["negotiation"] = json!({"status":"failed","message":"adapter unavailable"});
    value["records"] = json!([]);
    assert!(read(value.clone()).is_err());
    value["execution"]["session"] = json!({"status":"failed","errors":[]});
    assert!(read(value.clone()).is_err());
    value["execution"]["session"]["errors"] = json!([{"phase":"exchange","message":"pipe closed"}]);
    assert!(read(value.clone()).is_err());
    value["execution"]["session"]["errors"] =
        json!([{"phase":"spawn","message":"adapter unavailable"}]);
    assert!(read(value.clone()).is_ok());
    value["adapter"]["negotiation"] = example()["adapter"]["negotiation"].clone();
    assert!(read(value).is_err());
}

#[test]
fn schema_validates_fixture_and_rejects_hostile_shapes_without_the_reader() {
    let schema: Value = serde_json::from_str(morphir_mck::report::draft::SCHEMA).unwrap();
    let validator = jsonschema::draft7::options()
        .should_validate_formats(true)
        .build(&schema)
        .unwrap();
    assert!(validator.is_valid(&example()));
    for (pointer, bad) in [
        ("/suite", json!("package")),
        ("/driver/name", json!("different-driver")),
        ("/kit/source", json!("remote")),
        (
            "/adapter/negotiation/capabilities/contractVersion",
            json!(2),
        ),
        ("/execution/session", json!({"status":"failed","errors":[]})),
        ("/records/0/durationMs", json!(-1)),
        ("/startedAt", json!("not-a-timestamp")),
    ] {
        let mut value = example();
        *value.pointer_mut(pointer).unwrap() = bad;
        assert!(
            !validator.is_valid(&value),
            "schema accepted invalid {pointer}"
        );
    }
}

#[test]
fn nullable_provenance_is_required_and_diagnostics_are_closed() {
    for (pointer, field) in [
        ("/driver", "commit"),
        ("/kit", "revision"),
        ("/kit", "snapshotDigest"),
        ("/kit", "corpusHash"),
    ] {
        let mut value = example();
        value
            .pointer_mut(pointer)
            .unwrap()
            .as_object_mut()
            .unwrap()
            .remove(field);
        assert!(read(value).is_err(), "missing {pointer}/{field} accepted");
    }
    let mut value = example();
    value["records"][0]["observedDiagnostic"] = json!({"code":"invalid", "stage":"syntax"});
    assert!(read(value.clone()).is_ok());
    value["records"][0]["observedDiagnostic"]["extra"] = json!(true);
    assert!(read(value).is_err());
}

#[test]
fn failed_sessions_preserve_completed_records_and_failed_negotiation_kit_errors() {
    for phase in ["exchange", "shutdown"] {
        let mut value = example();
        value["execution"]["session"] =
            json!({"status":"failed","errors":[{"phase":phase,"message":"adapter closed"}]});
        let report = read(value).unwrap();
        assert_eq!(report.summary().pass, 1);
    }
    let mut value = example();
    value["adapter"]["negotiation"] = json!({"status":"failed","message":"bad capabilities"});
    value["execution"]["session"] =
        json!({"status":"failed","errors":[{"phase":"capabilities","message":"bad capabilities"}]});
    value["records"][0]["result"] = json!("kit-error");
    assert_eq!(read(value.clone()).unwrap().summary().kit_error, 1);
    value["records"] = json!([]);
    assert!(read(value).is_ok());
}

#[test]
fn serde_deserialization_uses_the_validated_reader() {
    let mut value = example();
    value["records"][0]["durationMs"] = json!(-1);
    assert!(serde_json::from_value::<DraftReport>(value).is_err());
}

#[test]
fn capabilities_wrapper_revalidates_public_protocol_values() {
    use morphir_mck::report::draft::NegotiatedCapabilities;
    let report = read(example()).unwrap();
    let Negotiation::Succeeded { capabilities } = &report.adapter.negotiation else {
        unreachable!()
    };
    let mut capabilities = capabilities.as_capabilities().clone();
    let wrapped = NegotiatedCapabilities::from_capabilities(&capabilities).unwrap();
    assert_eq!(
        serde_json::to_value(&wrapped).unwrap(),
        example()["adapter"]["negotiation"]["capabilities"]
    );
    capabilities.versions = vec![3];
    assert!(NegotiatedCapabilities::from_capabilities(&capabilities).is_err());
}

#[test]
fn record_integer_fields_accept_integral_json_number_spellings() {
    let mut value = example();
    value["records"][0]["irVersion"] = json!(4.0);
    value["records"][0]["fenceIndex"] = json!(0.0);
    let report =
        read(value).expect("JSON Schema integers include integral floating-point spellings");
    assert_eq!(report.records[0].ir_version, 4);
    assert_eq!(report.records[0].fence_index, 0);
}

#[test]
fn record_integer_fields_reject_fractions_and_out_of_range_values() {
    for (field, bad) in [
        ("irVersion", json!(4.5)),
        ("fenceIndex", json!(0.5)),
        ("irVersion", json!(9_223_372_036_854_775_808.0)),
        ("fenceIndex", json!(18_446_744_073_709_551_616.0)),
    ] {
        let mut value = example();
        value["records"][0][field] = bad;
        assert!(read(value).is_err(), "accepted invalid {field}");
    }
}

#[test]
fn failed_negotiation_cannot_report_executed_case_outcomes() {
    for result in ["pass", "fail", "skipped"] {
        let mut value = example();
        value["adapter"]["negotiation"] = json!({"status":"failed","message":"bad capabilities"});
        value["execution"]["session"] = json!({"status":"failed","errors":[{"phase":"capabilities","message":"bad capabilities"}]});
        value["records"][0]["result"] = json!(result);
        assert!(
            read(value).is_err(),
            "accepted {result} before negotiation succeeded"
        );
    }
}

#[test]
fn normalization_preserves_exact_integer_encodings_at_native_bounds() {
    let mut value = example();
    value["records"][0]["irVersion"] = json!(i64::MAX);
    value["records"][0]["fenceIndex"] = json!(usize::MAX);
    let report = read(value).unwrap();
    assert_eq!(report.records[0].ir_version, i64::MAX);
    assert_eq!(report.records[0].fence_index, usize::MAX);
}

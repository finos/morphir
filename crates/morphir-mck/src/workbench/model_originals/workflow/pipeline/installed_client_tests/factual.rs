//! Source-first UNIT DATA controls. No actual child/host/socket/filesystem
//! observer, authority issuer, UI Observation, native42 proof or role credit.
//! Intended mount: child `factual` of existing pipeline::installed_client_tests.
//! Use SAME parent source()/policy()/CORPUS/POLICY/calls_for and prepared gate.
use super::*;
use crate::workbench::model_originals::workflow::{
    Decode,
    installed_measurements::InstalledClientMeasurements,
    observation_check::{CompareResource, InstalledClientFault},
};
use serde_json::{Value, json};

const DATA: &str = include_str!("factual_controls/unit-data.json");

fn unit_data() -> Value {
    // TEST authoring only. Production receives strict literal Document and
    // retained exact raw socket strings; it cannot normalize through Value.
    serde_json::from_str(DATA).unwrap()
}
fn evaluate(data: &Value) -> ObservationError {
    let source = source(CORPUS);
    let policy = policy(POLICY);
    let raw = data.to_string();
    let mut result = None;
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            assert_eq!(inventory.len(), 24);
            let document = owners.decode.literal_with_raw(&raw).unwrap().0;
            let actual =
                InstalledClientMeasurements::decode(&document, &mut owners.decode).unwrap();
            let invocation = inventory.invocation();
            result = Some(
                invocation
                    .compiled_source()
                    .report_context()
                    .check_installed_process(&actual, &mut owners.comparison)
                    .expect_err("this original remains blocked after factual comparison"),
            );
            Ok(())
        },
    )
    .unwrap();
    result.unwrap()
}
fn assert_factual(data: &Value, fault: InstalledClientFault) {
    assert_eq!(evaluate(data), ObservationError::InstalledClient(fault));
}
fn decode_refuses(data: &Value) {
    let source = source(CORPUS);
    let policy = policy(POLICY);
    let raw = data.to_string();
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |_, owners| {
            let document = owners.decode.literal_with_raw(&raw).unwrap().0;
            assert!(InstalledClientMeasurements::decode(&document, &mut owners.decode).is_err());
            Ok(())
        },
    )
    .unwrap();
}
fn payload_change(data: &mut Value, sequence: usize, change: impl FnOnce(&mut Value)) {
    let field = &mut data["host"]["events"][sequence]["event"]["payload"];
    let mut payload: Value = serde_json::from_str(field.as_str().unwrap()).unwrap();
    change(&mut payload);
    *field = Value::String(payload.to_string());
}
fn stdout_change(data: &mut Value, process: usize, change: impl FnOnce(&mut Value)) {
    let field = &mut data["processes"][process]["stdout"]["text"];
    let mut claim: Value = serde_json::from_str(field.as_str().unwrap()).unwrap();
    change(&mut claim);
    *field = Value::String(format!("{}\n", claim));
}
fn blocked_report(data: &Value) -> String {
    // UNIT construction through genuine compiled keys + SAME bounded renderer.
    // No live or successful production measurement constructor is invented.
    let source = source(CORPUS);
    let policy = policy(POLICY);
    let raw = data.to_string();
    let mut encoded = None;
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            let document = owners.decode.literal_with_raw(&raw).unwrap().0;
            let actual =
                InstalledClientMeasurements::decode(&document, &mut owners.decode).unwrap();
            let invocation = inventory.invocation();
            let error = invocation
                .compiled_source()
                .report_context()
                .check_installed_process(&actual, &mut owners.comparison)
                .expect_err("unchanged original ExpectedBlocked");
            assert_eq!(error, ObservationError::ExpectedBlocked);
            let mut measurement =
                Some(wire::ClientProcessMeasurement::retain(actual, &mut owners.decode).unwrap());
            let mut records = Vec::new();
            for (index, case) in inventory.cases().iter().enumerate() {
                records.push(RuntimeRecord {
                    case_id: case.case().id(),
                    execution: ExecutionRef::from_compiled(case),
                    evidence: if index == 0 {
                        Evidence::ClientProcessMeasured {
                            measurement: measurement.take().unwrap(),
                            verdict: Verdict::Failed { failure_index: 0 },
                        }
                    } else {
                        Evidence::NotAttempted {
                            prior_failure_index: 0,
                        }
                    },
                });
            }
            let fault = RunFault::Record(WorkflowRecordError::Observation(error));
            let errors = vec![fault.summary()];
            let report = RuntimeReport {
                format_version: VERSION,
                suite: "workbench",
                corpus_hash: source.digest(),
                capabilities: None,
                records,
                negotiation: None,
                errors,
                qualified: false,
            };
            encoded = Some(
                render(PreparedExecution {
                    report,
                    attempt: Attempt { fault: Some(fault) },
                    shutdown: None,
                })
                .unwrap()
                .text()
                .to_owned(),
            );
            Ok(())
        },
    )
    .unwrap();
    encoded.unwrap()
}
fn replay(raw: &str) -> Result<(), String> {
    let source = source(CORPUS);
    let policy = policy(POLICY);
    let report = StoredReport::from_json(raw)?;
    replay_installed(&source, &policy, &report)
}

#[test]
fn f01_honest_unit_facts_compare_then_unchanged_blocked_and_saved_replay() {
    let data = unit_data();
    assert_eq!(evaluate(&data), ObservationError::ExpectedBlocked);
    let report = blocked_report(&data);
    let saved: Value = serde_json::from_str(&report).unwrap();
    assert_eq!(saved["records"].as_array().unwrap().len(), 24);
    assert_eq!(
        saved["records"][0]["evidence"]["kind"],
        "client-process-measured"
    );
    assert_eq!(
        saved["records"][0]["evidence"]["verdict"],
        json!({"kind":"failed","failureIndex":0})
    );
    assert_eq!(saved["qualified"], false);
    for row in &saved["records"].as_array().unwrap()[1..] {
        assert_eq!(
            row["evidence"],
            json!({"kind":"not-attempted","priorFailureIndex":0})
        );
    }
    replay(&report).unwrap();
}

#[test]
fn f02_original_file_bytes_length_and_digest_tamper_fail_before_blocked() {
    for pointer in [
        "/destination/rawEntries/1/bytes/hex",
        "/destination/rawEntries/3/bytes/hex",
    ] {
        let mut data = unit_data();
        let bytes = data.pointer_mut(pointer).unwrap();
        let mut hex = bytes.as_str().unwrap().to_owned();
        let tail = hex.len() - 2;
        hex.replace_range(tail.., "fe");
        *bytes = Value::String(hex);
        assert_factual(&data, InstalledClientFault::DestinationBytes);
    }
    for (pointer, value) in [
        ("/destination/files/1/byteLength", json!(3)),
        (
            "/destination/files/1/sha256",
            json!("0000000000000000000000000000000000000000000000000000000000000000"),
        ),
    ] {
        let mut data = unit_data();
        *data.pointer_mut(pointer).unwrap() = value;
        assert_factual(&data, InstalledClientFault::DestinationBytes);
    }
    // Expected values are resolved from genuine plan, not copied into this
    // test as another scalar oracle. The DATA mutation keeps old summary/error.
    let mut report: Value = serde_json::from_str(&blocked_report(&unit_data())).unwrap();
    report["records"][0]["evidence"]["measurement"]["destination"]["rawEntries"][3]["bytes"]["hex"] =
        json!("000102fe");
    assert!(
        replay(&report.to_string()).is_err(),
        "Blocked must not hide byte tamper"
    );
}

#[test]
fn f03_complete_destination_set_types_duplicates_and_coverage_are_checked() {
    for entry in [
        json!({"kind":"file","path":"unrelated.log","bytes":{"kind":"hex","hex":"01"}}),
        json!({"kind":"file","path":"originals/compile.json","bytes":{"kind":"hex","hex":"01"}}),
    ] {
        let mut data = unit_data();
        data["destination"]["rawEntries"]
            .as_array_mut()
            .unwrap()
            .push(entry);
        assert_factual(&data, InstalledClientFault::DestinationEntries);
    }
    let mut data = unit_data();
    let duplicate = data["destination"]["rawEntries"][3].clone();
    data["destination"]["rawEntries"]
        .as_array_mut()
        .unwrap()
        .push(duplicate);
    assert_factual(&data, InstalledClientFault::DestinationEntries);
    let mut data = unit_data();
    data["destination"]["rawEntries"]
        .as_array_mut()
        .unwrap()
        .remove(3);
    assert_factual(&data, InstalledClientFault::DestinationEntries);
    let mut data = unit_data();
    data["destination"]["rawEntries"][1] =
        json!({"kind":"physical-directory","path":"originals/morphir-ir.json"});
    assert_factual(&data, InstalledClientFault::DestinationEntries);
    let mut data = unit_data();
    data["destination"]["coverage"] = json!("incomplete");
    assert_factual(&data, InstalledClientFault::DestinationCoverage);
    let mut data = unit_data();
    data["destination"]["rawEntries"][3]["path"] = json!("../outside.bin");
    decode_refuses(&data);
}

#[test]
fn f04_postwait_scratch_raw_census_cannot_be_hidden_by_empty_summary() {
    let mut data = unit_data();
    data["scratch"]["rawEntries"]
        .as_array_mut()
        .unwrap()
        .push(json!({
            "kind":"file","path":"residue","bytes":{"kind":"hex","hex":"01"}
        }));
    assert_factual(&data, InstalledClientFault::ScratchEntries);
    let mut data = unit_data();
    data["scratch"]["coverage"] = json!("incomplete");
    assert_factual(&data, InstalledClientFault::ScratchCoverage);
    let mut data = unit_data();
    data["scratch"]["afterAction"] = json!(5);
    assert_factual(&data, InstalledClientFault::ScratchCoverage);
    // Does not assert detection of coherent replacement of *all* raw census.
}

#[test]
fn f05_source_action_order_real_status_and_stdout_claims_are_not_verdicts() {
    let mut data = unit_data();
    data["processes"].as_array_mut().unwrap().swap(0, 1);
    assert_factual(&data, InstalledClientFault::ProcessOrder);
    let mut data = unit_data();
    data["processes"][2]["actionIndex"] = json!(7);
    assert_factual(&data, InstalledClientFault::ProcessOrder);
    let mut data = unit_data();
    data["processes"][2]["completion"]["exit"]["value"] = json!(1);
    assert_factual(&data, InstalledClientFault::ProcessOutcome);
    let mut data = unit_data();
    data["processes"][2]["completion"] = json!({"kind":"incomplete"});
    assert_factual(&data, InstalledClientFault::ProcessOutcome);
    let mut data = unit_data();
    stdout_change(&mut data, 2, |claim| {
        claim["representation"] = json!("typed-model")
    });
    assert_factual(&data, InstalledClientFault::ProcessClaims);
    let mut data = unit_data();
    stdout_change(&mut data, 2, |claim| {
        claim["published"] = json!(["/foreign/originals"])
    });
    assert_factual(&data, InstalledClientFault::ProcessClaims);
}

#[test]
fn f06_literal_protocol_ids_binding_payload_and_release_are_verified_unchanged() {
    // Positive has IDs1/2 on BOTH actual socket groups, not global rewriting.
    assert_eq!(evaluate(&unit_data()), ObservationError::ExpectedBlocked);
    let mut data = unit_data();
    payload_change(&mut data, 22, |frame| frame["id"] = json!(999));
    assert_factual(&data, InstalledClientFault::SocketFrame);
    let mut data = unit_data();
    payload_change(&mut data, 22, |frame| {
        frame["result"]["content"] = json!("AA==")
    });
    assert_factual(&data, InstalledClientFault::SocketFrame);
    let mut data = unit_data();
    payload_change(&mut data, 14, |frame| {
        frame["params"]["semantic"] = json!("projection")
    });
    assert_factual(&data, InstalledClientFault::SocketFrame);
    let mut data = unit_data();
    payload_change(&mut data, 28, |frame| {
        frame["result"]["captureId"] = json!("foreign")
    });
    assert_factual(&data, InstalledClientFault::SocketFrame);
    let mut data = unit_data();
    data["host"]["events"][15]["event"]["bytes"] = json!({"kind":"hex","hex":"7b7d"});
    assert_factual(&data, InstalledClientFault::RecordAdoption);
    let mut data = unit_data();
    let payload = &mut data["host"]["events"][22]["event"]["payload"];
    let text = payload.as_str().unwrap();
    assert!(text.contains("\"id\":5"));
    *payload = Value::String(text.replacen("\"id\":5", "\"id\":5,\"id\":5", 1));
    assert_factual(&data, InstalledClientFault::SocketFrame);
}

#[test]
fn f07_actual_event_order_unique_ingress_and_send_completion_are_distinct() {
    for outcome in ["failed", "timed-out"] {
        let mut data = unit_data();
        data["host"]["events"][29]["event"]["outcome"] = json!(outcome);
        assert_factual(&data, InstalledClientFault::SendOutcome);
    }
    let mut data = unit_data();
    data["host"]["events"][29]["event"]["preparedSequence"] = json!(500);
    assert_factual(&data, InstalledClientFault::SocketOrder);
    let mut data = unit_data();
    data["host"]["events"][7]["connection"] = json!(0);
    assert_factual(&data, InstalledClientFault::SocketAssociation);
    let mut data = unit_data();
    let duplicate = data["host"]["events"][14].clone();
    data["host"]["events"]
        .as_array_mut()
        .unwrap()
        .insert(15, duplicate);
    assert_factual(&data, InstalledClientFault::SocketOrder);
    // Actual foreign *live owner* rejection belongs to parent's owner tests;
    // labels in this pure DATA cannot prove per-child/auth authority.
}

#[test]
fn f08_unobserved_dynamic_facts_are_honest_and_cannot_be_forged_complete() {
    assert_eq!(evaluate(&unit_data()), ObservationError::ExpectedBlocked);
    for name in [
        "dynamicCommit",
        "dynamicScratchCleanup",
        "clientReleaseAcceptance",
    ] {
        let mut data = unit_data();
        data[name] = json!("observed-complete");
        decode_refuses(&data);
    }
    let mut data = unit_data();
    data["commitTimestamp"] = json!(1);
    decode_refuses(&data);
}

#[test]
fn f09_full24_source_hash_inventory_order_and_execution_keys_precede_facts() {
    for raw in [
        include_str!("../installed_client_controls/wrong-order.json"),
        include_str!("../installed_client_controls/missing-last.json"),
        include_str!("../installed_client_controls/last-input-space.json"),
    ] {
        let (result, calls) = calls_for(raw, ReviewedSources::installed_client_selected());
        assert!(result.is_err());
        assert_eq!(calls, 0);
    }
    let baseline: Value = serde_json::from_str(&blocked_report(&unit_data())).unwrap();
    for (pointer, value) in [
        ("/records/0/execution/origin/id", json!("foreign-original")),
        (
            "/records/0/execution/origin/sha256",
            json!("0000000000000000000000000000000000000000000000000000000000000000"),
        ),
        ("/records/0/execution/role", json!("model-originals-server")),
        ("/records/0/execution/runIndex", json!(1)),
    ] {
        let mut report = baseline.clone();
        *report.pointer_mut(pointer).unwrap() = value;
        assert!(replay(&report.to_string()).is_err(), "{pointer}");
    }
    let source = source(CORPUS);
    let policy = policy(POLICY);
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            let document = owners.decode.literal_with_raw(DATA).unwrap().0;
            let data = InstalledClientMeasurements::decode(&document, &mut owners.decode).unwrap();
            let other = inventory.cases()[2]
                .current()
                .expect("existing original client row");
            assert_eq!(
                other
                    .report_context()
                    .check_installed_process(&data, &mut owners.comparison),
                Err(ObservationError::InstalledClient(
                    InstalledClientFault::SourceBinding
                ))
            );
            Ok(())
        },
    )
    .unwrap();
    let mut report = baseline.clone();
    report["corpusHash"] =
        json!("0000000000000000000000000000000000000000000000000000000000000000");
    assert!(replay(&report.to_string()).is_err());
    let mut report = baseline.clone();
    report["records"].as_array_mut().unwrap().swap(1, 2);
    assert!(replay(&report.to_string()).is_err());
    let mut report = baseline;
    report["records"].as_array_mut().unwrap().pop();
    assert!(replay(&report.to_string()).is_err());
}

#[test]
fn f10_saved_blocked_error_index_verdict_suffix_and_role_are_recomputed() {
    let baseline: Value = serde_json::from_str(&blocked_report(&unit_data())).unwrap();
    for (pointer, value) in [
        ("/qualified", json!(true)),
        ("/records/0/evidence/verdict", json!({"kind":"checked"})),
        ("/records/0/evidence/verdict/failureIndex", json!(1)),
        (
            "/records/1/evidence",
            json!({"kind":"attempt-failed","failureIndex":0}),
        ),
        ("/records/1/evidence/priorFailureIndex", json!(1)),
        ("/records/0/evidence/kind", json!("native-measured")),
        ("/errors/0/code", json!("forged-code")),
    ] {
        let mut report = baseline.clone();
        *report.pointer_mut(pointer).unwrap() = value;
        assert!(replay(&report.to_string()).is_err(), "{pointer}");
    }
}

#[test]
fn f11_same_comparison_first_fault_wins_and_retry_does_no_work() {
    let source = source(CORPUS);
    let mut explicit: Value = serde_json::from_str(POLICY).unwrap();
    explicit["comparison"]["comparisonBytes"] = json!(0);
    let policy = policy(&explicit.to_string());
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |inventory, owners| {
            let raw = DATA;
            let document = owners.decode.literal_with_raw(raw).unwrap().0;
            let actual =
                InstalledClientMeasurements::decode(&document, &mut owners.decode).unwrap();
            let first = owners.comparison.preflight_owned_text(1).unwrap_err();
            assert_eq!(
                first,
                ObservationError::Resource(CompareResource::ComparisonBytes)
            );
            let used = owners.comparison.usage();
            let invocation = inventory.invocation();
            for _ in 0..2 {
                assert_eq!(
                    invocation
                        .compiled_source()
                        .report_context()
                        .check_installed_process(&actual, &mut owners.comparison),
                    Err(first)
                );
                assert_eq!(owners.comparison.usage(), used);
            }
            Ok(())
        },
    )
    .unwrap();
    // Before-copy exact/one-less receiver/frame reservations are separately
    // frozen owner controls, not inferred comparator weights in these tests.
}

#[test]
fn f12_saved_data_cannot_decode_live_authority_or_build_attestation_claims() {
    for (name, claim) in [
        ("liveInvocation", json!({"kind":"authorized"})),
        ("perChildSocketAttestation", json!(123)),
        (
            "buildProvenance",
            json!({"source":"0141628","identicalTo":"0143"}),
        ),
    ] {
        let mut data = unit_data();
        data[name] = claim;
        decode_refuses(&data);
    }
    let mut data = unit_data();
    data["destination"]["rawEntries"][3]["bytes"] = json!({"kind":"repeat-u8","byte":0,"length":4});
    decode_refuses(&data);
    replay(&blocked_report(&unit_data())).unwrap();
    // A coherent rewrite of all saved raw claims isn't cryptographically
    // authenticated. This test claims only closed decode/source consistency,
    // never live provenance, socket PID attestation or whole qualification.
}

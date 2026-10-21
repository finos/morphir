//! DATA-only projections/mutations of byte-exact actual52 reports. No live issuer
//! or claim that a historical healthy execution suffered the projected later fault.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::{
    installed::adapter::processes::ConsumerFailureKind, wire::FailureSummary,
};
fn native_partial() -> Value {
    genuine(
        include_str!("../../consumer_operation_controls/native-release-ack-loss.json"),
        "c2dfa3fae80639b98f829bffe815fc10e75ad05313351972bf245862db738073",
    )
}
fn drained_prefix(mut report: Value) -> Value {
    let measured = report.pointer(MEASUREMENT).unwrap();
    let operation = &measured["consumerObservation"];
    assert_eq!(operation["completion"], json!({"kind":"drained"}));
    let ordinal = &operation["association"]["processOrdinal"];
    let process = measured["processes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|process| &process["processOrdinal"] == ordinal)
        .unwrap();
    let prefix = json!({"kind":"recorded","process":process,"operation":operation,"context":{"kind":"prefix","implementation":measured["implementation"],"host":{"association":measured["host"]["association"],"selection":measured["host"]["selection"],"events":measured["host"]["events"]}}});
    raw(&mut report).clone_from(&prefix);
    report
}
fn endpoint<'a>(report: &'a mut Value, role: &str) -> &'a mut Value {
    raw(report)["operation"]["endpoints"]
        .as_array_mut()
        .unwrap()
        .iter_mut()
        .find(|endpoint| endpoint["role"] == role)
        .unwrap()
}
fn change(report: &mut Value, role: &str, kind: &str, alter: impl FnOnce(&mut Value)) {
    let mut alter = Some(alter);
    let mut found = 0;
    for row in endpoint(report, role)["frames"].as_array_mut().unwrap() {
        let mut frame: Value = serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
        if frame["kind"] == kind {
            alter.take().unwrap()(&mut frame);
            row["literal"] = frame.to_string().into();
            found += 1;
        }
    }
    assert_eq!(found, 1, "one actual retained {role}/{kind}");
}
fn foreign() -> Value {
    json!({"kind":"unix-bytes","bytes":{"kind":"utf8","text":"/foreign"}})
}
#[test]
fn retained_partial_rows_require_the_supported_revision() {
    for role in ["outer", "transfer-helper"] {
        let mut report = actual_partial();
        change(&mut report, role, "open", |frame| {
            let before = frame["version"].as_str().unwrap().len();
            frame["version"] = json!("0.1.0-draft.9");
            assert_eq!(before, frame["version"].as_str().unwrap().len());
        });
        exact(&report, "InstalledClient(ConsumerTranscript)");
    }
}
#[test]
fn retained_close_counters_match_acknowledged_business_rows() {
    for role in ["outer", "transfer-helper"] {
        for field in [
            "attemptedHooks",
            "startedFactFrames",
            "retainedBusinessFacts",
        ] {
            let mut report = drained_prefix(node());
            change(&mut report, role, "close", |close| {
                let count = close[field].as_u64().unwrap();
                close[field] = json!(count + 1);
            });
            exact(&report, "InstalledClient(ConsumerTranscript)");
        }
    }
}
#[test]
fn retained_close_helper_forms_match_the_selected_lane_and_role() {
    let native = drained_prefix(native());
    let frames = raw(&mut native.clone())["operation"]["endpoints"][0]["frames"].clone();
    let native_close: Value = serde_json::from_str(
        frames.as_array().unwrap().last().unwrap()["literal"]
            .as_str()
            .unwrap(),
    )
    .unwrap();
    let mut node_report = drained_prefix(node());
    change(&mut node_report, "outer", "close", |close| {
        close["helper"] = native_close["helper"].clone()
    });
    exact(&node_report, "InstalledClient(ConsumerAssociation)");
    let mut native = native;
    change(&mut native, "outer", "close", |close| {
        close["helper"] = json!({"kind":"in-process"})
    });
    exact(&native, "InstalledClient(ConsumerAssociation)");
    let mut helper = drained_prefix(node());
    change(&mut helper, "transfer-helper", "close", |close| {
        close["helper"] = json!({"kind":"in-process"})
    });
    exact(&helper, "InstalledClient(ConsumerTranscript)");
}
#[test]
fn successful_published_process_requires_successful_native_completion() {
    for dimension in 0..3 {
        let mut report = drained_prefix(native());
        assert_eq!(
            raw(&mut report)["process"]["completion"],
            json!({"kind":"finished","exit":{"kind":"code","value":0}})
        );
        let claim: Value = serde_json::from_str(
            raw(&mut report)["process"]["stdout"]["text"]
                .as_str()
                .unwrap(),
        )
        .unwrap();
        assert_eq!(claim["observation"], "published");
        assert_eq!(claim["operation"], "originals");
        change(&mut report, "outer", "close", |close| match dimension {
            0 => close["helper"]["wait"]["rawStatus"] = json!("256"),
            1 => close["helper"]["stdout"]["read"]["kind"] = json!("short-read"),
            _ => {
                close["helper"]["stdout"]["disposal"] =
                    json!({"kind":"failed","operation":"close","errorCode":"9"})
            }
        });
        exact(&report, "InstalledClient(ConsumerHelper)");
    }
}
#[test]
fn truthful_failed_helper_data_is_retained_for_interrupted_and_drained_transport() {
    for drained in [false, true] {
        for dimension in 0..3 {
            let mut report = drained_prefix(native());
            let prefix = raw(&mut report);
            prefix["process"]["completion"] =
                json!({"kind":"finished","exit":{"kind":"code","value":1}});
            prefix["process"]["stdout"] = json!({"kind":"utf8","text":json!({"profile":"morphir/cli/originals-command","contractVersion":"0.1.0","observation":"not-published","error":"originals.helper_lost","cleanup":"unknown"}).to_string()});
            let outer = endpoint(&mut report, "outer");
            let frames = outer["frames"].as_array_mut().unwrap();
            let mut removed = 0;
            frames.retain(|row| {
                let frame: Value = serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
                let keep = frame["fact"]["kind"] != "destination-commit-finished";
                if !keep {
                    removed += 1
                };
                keep
            });
            assert_eq!(removed, 1);
            for (sequence, row) in frames.iter_mut().enumerate() {
                let mut body: Value =
                    serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
                body["sequence"] = json!(sequence);
                if body["kind"] == "close" {
                    for field in [
                        "attemptedHooks",
                        "startedFactFrames",
                        "retainedBusinessFacts",
                    ] {
                        body[field] = json!(1);
                    }
                }
                row["literal"] = body.to_string().into();
            }
            change(&mut report, "outer", "close", |close| match dimension {
                0 => close["helper"]["wait"]["rawStatus"] = json!("256"),
                1 => close["helper"]["stdout"]["read"]["kind"] = json!("short-read"),
                _ => {
                    close["helper"]["stdout"]["disposal"] =
                        json!({"kind":"failed","operation":"close","errorCode":"9"})
                }
            });
            if !drained {
                raw(&mut report)["operation"]["completion"] = json!({"kind":"interrupted","firstFailure":{"phase":"installed-consumer","code":"io","message":"private consumer operation transport refused"}});
                let outer = endpoint(&mut report, "outer");
                outer["terminal"] = json!({"kind":"close-ack-written"});
                outer["fault"] = json!("io");
            }
            evaluate(&report).unwrap();
            assert!(summary_matches(&report, ConsumerFailureKind::Io));
        }
    }
}
#[test]
fn partial_native_helper_started_is_unique() {
    let mut report = native_partial();
    let frames = endpoint(&mut report, "outer")["frames"]
        .as_array_mut()
        .unwrap();
    assert_eq!(frames.len(), 2);
    let mut row = frames[1].clone();
    let mut body: Value = serde_json::from_str(row["literal"].as_str().unwrap()).unwrap();
    assert_eq!(body["kind"], "helper-started");
    body["sequence"] = json!(2);
    row["literal"] = body.to_string().into();
    frames.push(row);
    exact(&report, "InstalledClient(ConsumerAssociation)");
}
#[test]
fn partial_native_helper_launch_binds_program_arguments_and_directory() {
    for dimension in 0..5 {
        let mut report = native_partial();
        change(
            &mut report,
            "outer",
            "helper-started",
            |body| match dimension {
                0 => body["launch"]["program"] = foreign(),
                1 => body["launch"]["directory"] = foreign(),
                2 => body["launch"]["arguments"][0] = foreign(),
                3 => body["launch"]["arguments"][1] = foreign(),
                _ => {
                    body["launch"]["arguments"][2] = json!({"kind":"unix-bytes","bytes":{"kind":"utf8","text":"relative-config"}})
                }
            },
        );
        exact(&report, "InstalledClient(ConsumerAssociation)");
    }
}
#[test]
fn copied_publish_labels_cannot_turn_the_compiled_connect_action_into_publish() {
    let healthy = node();
    let mut connect = healthy.pointer(MEASUREMENT).unwrap()["processes"]
        .as_array()
        .unwrap()
        .iter()
        .find(|process| process["command"] == "connect")
        .unwrap()
        .clone();
    assert_eq!(connect["actionIndex"], 2);
    assert_eq!(connect["processOrdinal"], 3);
    connect["command"] = json!("publish");
    let mut report = drained_prefix(healthy);
    let prefix = raw(&mut report);
    prefix["process"] = connect;
    prefix["operation"]["association"]["processOrdinal"] = json!(3);
    prefix["operation"]["association"]["actionIndex"] = json!(2);
    exact(&report, "InstalledClient(ConsumerAssociation)");
}
#[test]
fn drained_cannot_replace_an_actual_ack_loss_interruption() {
    let mut report = actual_partial();
    raw(&mut report)["operation"]["completion"] = json!({"kind":"drained"});
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
#[test]
fn drained_cannot_retain_an_endpoint_fault() {
    let mut report = drained_prefix(node());
    endpoint(&mut report, "outer")["fault"] = json!("io");
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
#[test]
fn drained_requires_physical_terminal_data_beyond_close_ack_written() {
    let mut report = drained_prefix(node());
    endpoint(&mut report, "outer")["terminal"] = json!({"kind":"close-ack-written"});
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
#[test]
fn drained_cannot_retain_an_unwritten_close_ack() {
    let mut report = drained_prefix(node());
    let outer = endpoint(&mut report, "outer");
    outer["terminal"] = json!({"kind":"close-retained"});
    let row = outer["frames"].as_array_mut().unwrap().last_mut().unwrap();
    let total = row["delivery"]["total"].clone();
    row["delivery"] = json!({"kind":"prefix","written":0,"total":total});
    exact(&report, "InstalledClient(ConsumerTranscript)");
}
fn summary_matches(report: &Value, kind: ConsumerFailureKind) -> bool {
    let source = source(CORPUS);
    let configuration: Value = serde_json::from_str(CONFIGURATION).unwrap();
    let policy = policy(&configuration["checker"].to_string());
    let mut result = None;
    let text = report["records"][0]["evidence"]["consumerFailure"].to_string();
    prepared_installed_client(
        &source,
        &policy,
        ReviewedSources::installed_client_selected(),
        |_, owners| {
            let document = owners.decode.literal_with_raw(&text).unwrap().0;
            let actual = StoredConsumerPartial::decode(&document, &mut owners.decode).unwrap();
            result = Some(
                actual
                    .matches_first(FailureSummary::consumer(kind), &mut owners.decode)
                    .unwrap(),
            );
            Ok(())
        },
    )
    .unwrap();
    result.unwrap()
}
#[test]
fn truthful_drained_prefix_stays_drained_when_a_later_failure_is_projected() {
    // Conditional DATA-only positive from the actual healthy record. A later
    // independent failure changes the outer report, not this immutable record.
    for healthy in [node(), native()] {
        let report = drained_prefix(healthy);
        evaluate(&report).unwrap();
        assert!(summary_matches(&report, ConsumerFailureKind::Io));
        assert_eq!(
            report["records"][0]["evidence"]["consumerFailure"]["operation"]["completion"]["kind"],
            "drained"
        );
    }
}
#[test]
fn interrupted_prefix_requires_its_own_earliest_summary() {
    let report = actual_partial();
    assert!(summary_matches(&report, ConsumerFailureKind::Io));
    assert!(!summary_matches(&report, ConsumerFailureKind::Framing));
}

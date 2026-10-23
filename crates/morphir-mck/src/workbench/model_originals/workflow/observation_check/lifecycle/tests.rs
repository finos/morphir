//! Literal observation controls against an unchanged genuinely compiled original.
//! No recorded DATA in these controls is a producer or full-case qualification.
use super::super::{CompareLimits, CompareOwner, ObservationError};
use crate::workbench::model_originals::workflow::{
    Decoder, domain, observed, record_boundary_support,
};
use serde_json::{Value, json};

fn owner() -> CompareOwner {
    CompareOwner::new(CompareLimits::new(1_000_000, 16_777_216, 100_000).unwrap())
}
fn effect(kind: &str) -> Value {
    json!({"attempt":"attempt-A","kind":kind,"ordinal":0})
}
fn pending(kind: &str) -> Value {
    json!({"kind":"pending","effect":effect(kind),"input":{"kind":"none"},"port":"promise"})
}
fn frame(text: &str) -> Value {
    json!({"kind":"literal","text":text})
}
fn resolved(kind: &str, text: &str) -> Value {
    let corpus: Value = serde_json::from_str(include_str!(
        "../../source_compile/controls/bound-corpus.json"
    ))
    .unwrap();
    let text = if kind == "manifest-fetch" {
        corpus["cases"][0]["input"]["runs"][0]["fixture"]["runtime"]["manifest"]["body"]["text"]
            .as_str()
            .unwrap()
    } else {
        text
    };
    json!({"kind":"promise-resolved","effect":effect(kind),"reply":{"kind":"frame","value":frame(text)}})
}
fn observation(events: Vec<Value>) -> Value {
    let mut original: Value = serde_json::from_str(include_str!(
        "../../source_compile/controls/bound-corpus.json"
    ))
    .unwrap();
    let actions = original["cases"][0]["input"]["runs"][0]["actions"]
        .as_array_mut()
        .unwrap();
    let checkpoints: Vec<_> = actions.iter().filter(|a| a["kind"] == "checkpoint").map(|a| json!({
        "name":a["name"],"eventCount":events.len(),"pendingEffects":[],"preparedCoreEffects":[],
        "heldCoreResultBytes":0,"owner":{"kind":"none"},"currentOpening":null,"currentModel":null,
        "captureCleanup":{"kind":"none"},"executionOwner":{"kind":"none"},
        "navigation":{"destinationCount":0,"inspectionOwner":null,"outputOwner":null,"searchOwner":null}
    })).collect();
    json!({"role":"model-originals-client","checkpoints":checkpoints,"effects":events,
        "outbound":[],"coreResults":[],"downloads":[],"richOwners":[],
        "outcome":{"kind":"clean","finalCheckpoint":"owned-transport-and-workers-exited"},
        "teardown":{"kind":"confirmed","pendingEffects":0,"heldCoreResults":0,"stillOwnedWorkers":0,
        "productReleaseInferred":false,"workersStarted":0,"workersExited":0,"disposedTransports":0}})
}
fn decode(raw: &Value, decoder: &mut Decoder) -> observed::Observation {
    decoder.decode(&raw.to_string()).unwrap()
}

#[test]
fn shared_lifecycle_01_original_port_count_and_blocked_case_are_distinct() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let actual = decode(
            &observation(vec![
                pending("manifest-fetch"),
                resolved("manifest-fetch", "{}"),
            ]),
            decoder,
        );
        let mut comparison = owner();
        let checked = context
            .check_client_lifecycle(&actual, decoder, expansion, &mut comparison)
            .unwrap();
        let source: Value = serde_json::from_str(include_str!(
            "../../source_compile/controls/bound-corpus.json"
        ))
        .unwrap();
        let bytes=source["cases"][0]["input"]["runs"][0]["fixture"]["runtime"]["manifest"]["body"]["text"].as_str().unwrap().len();
        assert_eq!(
            checked.payload_comparison_bytes(),
            2 * bytes,
            "complete actual/source manifest operands are charged once"
        );
        let domain::ExpectedWorkflow::ModelOriginalsClient { checks, .. } =
            context.paired().expected()
        else {
            panic!()
        };
        let check = checks
            .0
            .iter()
            .find(|c| {
                matches!(
                    c,
                    domain::ExpectedClientCheck::PortCounts {
                        effect_kind: domain::EffectKind::ManifestFetch,
                        ..
                    }
                )
            })
            .unwrap();
        checked.check_port_counts(check, &mut comparison).unwrap();
        assert!(matches!(
            context.check_observation(&actual, &mut owner()),
            Err(ObservationError::ExpectedBlocked)
        ));
    });
}

#[test]
fn shared_lifecycle_02_foreign_gapped_and_duplicate_terminal_refuse() {
    for variant in 0..3 {
        record_boundary_support::with_v3_work(|context, decoder, expansion| {
            let mut raw = observation(vec![
                pending("manifest-fetch"),
                resolved("manifest-fetch", "{}"),
            ]);
            match variant {
                0 => raw["effects"][0]["effect"]["attempt"] = json!("foreign-attempt"),
                1 => raw["effects"][0]["effect"]["ordinal"] = json!(1),
                _ => {
                    raw["effects"]
                        .as_array_mut()
                        .unwrap()
                        .push(resolved("manifest-fetch", "{}"));
                    for c in raw["checkpoints"].as_array_mut().unwrap() {
                        c["eventCount"] = json!(3);
                    }
                }
            }
            let actual = decode(&raw, decoder);
            assert!(
                context
                    .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
                    .is_err()
            );
        });
    }
}

#[test]
fn shared_lifecycle_03_prefix_membership_and_held_bytes_are_independent() {
    for variant in 0..4 {
        record_boundary_support::with_v3_work(|context, decoder, expansion| {
            let mut raw = observation(vec![
                pending("manifest-fetch"),
                resolved("manifest-fetch", "{}"),
            ]);
            match variant {
                0 => raw["checkpoints"][0]["eventCount"] = json!(3),
                1 => raw["checkpoints"][0]["pendingEffects"] = json!([effect("manifest-fetch")]),
                2 => {
                    raw["checkpoints"][0]["preparedCoreEffects"] = json!([effect("manifest-fetch")])
                }
                _ => raw["checkpoints"][0]["heldCoreResultBytes"] = json!(1),
            }
            let actual = decode(&raw, decoder);
            assert!(
                context
                    .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
                    .is_err()
            );
        });
    }
}

#[test]
fn shared_lifecycle_04_prepared_work_raw_equality_and_retirement() {
    for variant in 0..3 {
        record_boundary_support::with_v3_work(|context, decoder, expansion| {
            let mut events = vec![
                pending("inspection"),
                json!({"kind":"work-started","effect":effect("inspection"),"work":"actual-work","owner":{"kind":"inline-production-invocation"}}),
                json!({"kind":"prepared-core-result","effect":effect("inspection"),"work":"actual-work","rawReply":frame("{}"),"actualResultByteLength":2}),
                resolved("inspection", "{}"),
                json!({"kind":"held-result-retired","effect":effect("inspection"),"byteLength":2,"disposition":"delivered-to-production-port"}),
                json!({"kind":"work-exited","effect":effect("inspection"),"work":"actual-work"}),
            ];
            match variant {
                0 => {
                    events.swap(1, 2);
                }
                1 => events[3] = resolved("inspection", "[]"),
                _ => {}
            }
            let mut raw = observation(events);
            // Real original ExecutePendingCore occurs after checkpoint0. No
            // work/result event is allowed into that earlier reducer cut.
            raw["checkpoints"][0]["eventCount"] = json!(1);
            raw["checkpoints"][0]["pendingEffects"] = json!([effect("inspection")]);
            let actual = decode(&raw, decoder);
            let result = context.check_client_lifecycle(&actual, decoder, expansion, &mut owner());
            assert_eq!(result.is_ok(), variant == 2);
        });
    }
}

#[test]
fn shared_lifecycle_05_existing_comparison_fault_is_sticky() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let actual = decode(
            &observation(vec![
                pending("manifest-fetch"),
                resolved("manifest-fetch", "{}"),
            ]),
            decoder,
        );
        let mut comparison = CompareOwner::new(CompareLimits::new(0, 0, 0).unwrap());
        let first = context
            .check_client_lifecycle(&actual, decoder, expansion, &mut comparison)
            .err()
            .unwrap();
        let before = (decoder.usage(), expansion.usage(), comparison.usage());
        let again = context
            .check_client_lifecycle(&actual, decoder, expansion, &mut comparison)
            .err()
            .unwrap();
        assert_eq!(first, again);
        assert_eq!(
            before,
            (decoder.usage(), expansion.usage(), comparison.usage())
        );
    });
}

#[test]
fn shared_lifecycle_06_opening_alias_does_not_issue_an_unselected_picker_route() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let actual = decode(
            &observation(vec![
                json!({"kind":"pending","effect":effect("picker"),"input":{"kind":"none"},"port":"picker-receive-callback"}),
                json!({"kind":"callback-delivered","effect":effect("picker"),"actualRawCallbackArgument":frame("{}")}),
            ]),
            decoder,
        );
        assert!(
            context
                .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
                .is_err(),
            "a connected opening must not issue a browser picker by reusing its alias"
        );
    });
}

#[test]
fn shared_lifecycle_07_original_count_refuses_missing_registration() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let actual = decode(&observation(vec![]), decoder);
        let checked = context
            .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
            .unwrap();
        let domain::ExpectedWorkflow::ModelOriginalsClient { checks, .. } =
            context.paired().expected()
        else {
            panic!()
        };
        let original = checks
            .0
            .iter()
            .find(|check| {
                matches!(
                    check,
                    domain::ExpectedClientCheck::PortCounts {
                        effect_kind: domain::EffectKind::ManifestFetch,
                        ..
                    }
                )
            })
            .unwrap();
        assert!(matches!(
            checked.check_port_counts(original, &mut owner()),
            Err(ObservationError::Lifecycle {
                kind: super::LifecycleFault::Counts,
                ..
            })
        ));
    });
}

#[test]
fn shared_lifecycle_08_rejected_port_can_hold_a_later_actual_work_result() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let mut raw = observation(vec![
            pending("inspection"),
            json!({"kind":"work-started","effect":effect("inspection"),"work":"actual-work","owner":{"kind":"inline-production-invocation"}}),
            json!({"kind":"promise-rejected","effect":effect("inspection"),"error":{"kind":"error","name":"AbortError","message":"actual cancellation"}}),
            json!({"kind":"prepared-core-result","effect":effect("inspection"),"work":"actual-work","rawReply":frame("{}"),"actualResultByteLength":2}),
            json!({"kind":"late-signal","effect":effect("inspection"),"actualSignal":{"kind":"frame","value":frame("{}")},"disposition":"ignored-by-settled-port","causalSource":{"kind":"actual-held-worker-result"}}),
            json!({"kind":"held-result-retired","effect":effect("inspection"),"byteLength":2,"disposition":"discarded-after-production-guard"}),
            json!({"kind":"work-exited","effect":effect("inspection"),"work":"actual-work"}),
        ]);
        raw["checkpoints"][0]["eventCount"] = json!(1);
        raw["checkpoints"][0]["pendingEffects"] = json!([effect("inspection")]);
        raw["checkpoints"][1]["eventCount"] = json!(4);
        raw["checkpoints"][1]["preparedCoreEffects"] = json!([effect("inspection")]);
        raw["checkpoints"][1]["heldCoreResultBytes"] = json!(2);
        let actual = decode(&raw, decoder);
        context
            .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
            .unwrap();
    });
}

#[test]
fn shared_lifecycle_09_non_core_values_cannot_replace_an_actual_manifest_reply() {
    for reply in [
        json!({"kind":"bytes","value":{"kind":"hex","hex":"00ff80"}}),
        json!({"kind":"sha256","value":"0000000000000000000000000000000000000000000000000000000000000000"}),
        json!({"kind":"file-selection","file":"unselected-file"}),
        json!({"kind":"void","operation":"adapter.cancel-model-open"}),
    ] {
        record_boundary_support::with_v3_work(|context, decoder, expansion| {
            let mut raw = observation(vec![
                pending("manifest-fetch"),
                resolved("manifest-fetch", "{}"),
            ]);
            raw["effects"][1]["reply"] = reply;
            let actual = decode(&raw, decoder);
            assert!(matches!(
                context.check_client_lifecycle(&actual, decoder, expansion, &mut owner()),
                Err(ObservationError::Lifecycle {
                    kind: super::LifecycleFault::Reply,
                    ..
                })
            ));
        });
    }
}

#[test]
fn shared_lifecycle_10_compact_frame_cannot_allocate_past_original_wire_allowance() {
    use crate::workbench::model_originals::workflow::expansion::ExpansionResource;
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let mut raw = observation(vec![
            pending("manifest-fetch"),
            resolved("manifest-fetch", "{}"),
        ]);
        raw["effects"][1]["reply"]["value"] =
            json!({"kind":"segments","parts":[{"kind":"repeat","text":" ","count":5000000}]});
        let actual = decode(&raw, decoder);
        let before = expansion.usage().amount(ExpansionResource::FrameBytes);
        assert!(matches!(
            context.check_client_lifecycle(&actual, decoder, expansion, &mut owner()),
            Err(ObservationError::Lifecycle {
                kind: super::LifecycleFault::Limits,
                ..
            })
        ));
        assert_eq!(
            before,
            expansion.usage().amount(ExpansionResource::FrameBytes)
        );
    });
}

#[test]
fn shared_lifecycle_11_rpc_kind_must_match_actual_source_selected_request() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let source: Value = serde_json::from_str(include_str!(
            "../../source_compile/controls/bound-corpus.json"
        ))
        .unwrap();
        let peer = &source["cases"][0]["input"]["runs"][0]["fixture"]["literalPeers"][0];
        for route in ["initialize", "capture"] {
            let mut raw = observation(vec![
                json!({"kind":"pending","effect":effect(route),"input":{"kind":"outbound-frame","index":0},"port":"promise"}),
                json!({"kind":"promise-resolved","effect":effect(route),"reply":{"kind":"frame","value":peer["frames"][0]}}),
            ]);
            raw["outbound"] = json!([peer["requests"][0]]);
            let actual = decode(&raw, decoder);
            let result = context.check_client_lifecycle(&actual, decoder, expansion, &mut owner());
            assert_eq!(
                result.is_ok(),
                route == "initialize",
                "a selected initialize request is not capture work"
            );
            if route == "initialize" {
                let request = peer["requests"][0]["text"].as_str().unwrap();
                let reply = peer["frames"][0]["text"].as_str().unwrap();
                let parsed: Value = serde_json::from_str(request).unwrap();
                let method = parsed["method"].as_str().unwrap();
                assert_eq!(
                    result.unwrap().payload_comparison_bytes(),
                    2 * (request.len() + reply.len() + method.len())
                );
            }
        }
    });
}

#[test]
fn shared_lifecycle_18_one_outbound_request_cannot_create_two_distinct_pending_ports() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let source: Value = serde_json::from_str(include_str!(
            "../../source_compile/controls/bound-corpus.json"
        ))
        .unwrap();
        let peer = &source["cases"][0]["input"]["runs"][0]["fixture"]["literalPeers"][0];
        let mut second = effect("initialize");
        second["ordinal"] = json!(1);
        let mut raw = observation(vec![
            json!({"kind":"pending","effect":effect("initialize"),"input":{"kind":"outbound-frame","index":0},"port":"promise"}),
            json!({"kind":"promise-resolved","effect":effect("initialize"),"reply":{"kind":"frame","value":peer["frames"][0]}}),
            json!({"kind":"pending","effect":second,"input":{"kind":"outbound-frame","index":0},"port":"promise"}),
            json!({"kind":"promise-resolved","effect":second,"reply":{"kind":"frame","value":peer["frames"][0]}}),
        ]);
        raw["outbound"] = json!([peer["requests"][0]]);
        let actual = decode(&raw, decoder);
        let refusal = context
            .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
            .err();
        assert_eq!(
            refusal,
            Some(ObservationError::Lifecycle {
                event: 2,
                kind: super::LifecycleFault::Input,
            }),
            "one actual source-selected outbound request is owned by one pending port"
        );
    });
}

#[test]
fn shared_lifecycle_19_adapter_vectors_do_not_pay_for_owned_ledger_storage() {
    use crate::workbench::model_originals::workflow::expansion::{
        ExpansionError, ExpansionResource,
    };
    use std::{borrow::Cow, mem::size_of};
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let raw = observation(vec![
            pending("manifest-fetch"),
            json!({"kind":"promise-rejected","effect":effect("manifest-fetch"),"error":{"kind":"error","name":"AbortError","message":"actual refusal"}}),
        ]);
        let actual = decode(&raw, decoder);
        // Leave only the already-priced adapter vectors/header/alias copies.
        // A genuine registration still owns additional keys/container backing.
        let adapter_bytes = 2
            * (size_of::<crate::workbench::model_originals::EffectRef>()
                + size_of::<Option<Cow<'_, str>>>())
            + size_of::<super::CheckedClientLifecycle<'_, '_>>()
            + 2 * "attempt-A".len();
        let used = expansion
            .usage()
            .amount(ExpansionResource::LiteralStorageBytes);
        expansion
            .measure_metadata(1_073_741_824 - used as usize - adapter_bytes, 0)
            .unwrap();
        let refusal = context
            .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
            .err();
        assert!(
            matches!(
                refusal,
                Some(ObservationError::Lifecycle {
                    kind: super::LifecycleFault::Expansion(ExpansionError::Resource(
                        ExpansionResource::LiteralStorageBytes
                    )),
                    ..
                })
            ),
            "ledger backing cannot consume zero remaining metadata credit: {refusal:?}"
        );
    });
}

#[test]
fn shared_lifecycle_20_prepared_ledger_backing_and_alias_clone_have_exact_boundaries() {
    use crate::workbench::model_originals::{
        EffectEvent, EffectKind, EffectLedger, EffectLedgerError, EffectLedgerLimits, EffectPort,
        EffectRef,
    };
    let layout = EffectLedger::storage_layout(1, 0).unwrap();
    for allowance in [
        0,
        layout.bytes - 1,
        layout.bytes,
        layout.bytes + "actual-port".len() - 1,
        layout.bytes + "actual-port".len(),
    ] {
        record_boundary_support::with_v3_work(|_, decoder, expansion| {
            let mut ledger = EffectLedger::new(EffectLedgerLimits::new(1, 4, 16, 16, 16).unwrap());
            let mut comparison = owner();
            let mut metadata = super::LifecycleMetadata {
                limit: allowance,
                used: 0,
            };
            let prepared = ledger.prepare_funded_storage(1, 0, |cost| {
                metadata.charge(cost, decoder, expansion, &mut comparison)
            });
            assert_eq!(prepared.is_ok(), allowance >= layout.bytes);
            assert_eq!(ledger.port_count(), 0);
            assert_eq!(ledger.event_count(), 0);
            if prepared.is_err() {
                return;
            }
            let effect = EffectRef::new("actual-port", EffectKind::ManifestFetch, 0).unwrap();
            assert_eq!(
                ledger.record(&effect, EffectEvent::Pending(EffectPort::Promise)),
                Err(EffectLedgerError::Storage),
                "a funded ledger cannot bypass the debit callback"
            );
            let inserted =
                ledger.record_funded(&effect, EffectEvent::Pending(EffectPort::Promise), |cost| {
                    metadata.charge(cost, decoder, expansion, &mut comparison)
                });
            let enough = allowance == layout.bytes + "actual-port".len();
            assert_eq!(inserted.is_ok(), enough);
            assert_eq!(ledger.port_count(), usize::from(enough));
            assert_eq!(ledger.event_count(), usize::from(enough));
            if enough {
                assert_eq!(metadata.used, allowance);
                assert_eq!(ledger.pending_effects().next(), Some(&effect));
            } else {
                assert!(comparison.ready().is_err());
                assert_eq!(metadata.used, layout.bytes);
            }
        });
    }
    assert!(
        EffectLedger::storage_layout(usize::MAX, 1).is_err(),
        "overflow refuses before reserve/retention"
    );
}

#[test]
fn shared_lifecycle_21_prepared_work_insertion_requires_same_remaining_work_credit() {
    use crate::workbench::model_originals::workflow::OperandResource;
    use crate::workbench::model_originals::{
        EffectEvent, EffectKind, EffectLedger, EffectLedgerLimits, EffectPort, EffectRef,
        FixtureAlias, WorkOwner,
    };
    for boundary in 0..3 {
        record_boundary_support::with_v3_work(|_, decoder, expansion| {
            let work = FixtureAlias::new("actual-work").unwrap();
            let effect = EffectRef::new("actual-port", EffectKind::Inspection, 0).unwrap();
            let mut ledger = EffectLedger::new(EffectLedgerLimits::new(1, 4, 16, 16, 16).unwrap());
            let mut comparison = owner();
            let mut metadata = super::LifecycleMetadata {
                limit: 1_048_576,
                used: 0,
            };
            ledger
                .prepare_funded_storage(1, 1, |cost| {
                    metadata.charge(cost, decoder, expansion, &mut comparison)
                })
                .unwrap();
            ledger
                .record_funded(&effect, EffectEvent::Pending(EffectPort::Promise), |cost| {
                    metadata.charge(cost, decoder, expansion, &mut comparison)
                })
                .unwrap();
            let mut measured_cost = None;
            let probe = ledger.record_funded(
                &effect,
                EffectEvent::WorkStarted {
                    work: &work,
                    owner: WorkOwner::Inline,
                },
                |cost| {
                    measured_cost = Some(cost);
                    Err(())
                },
            );
            assert!(probe.is_err());
            assert_eq!(ledger.event_count(), 1);
            let cost = measured_cost.unwrap();
            let allowance = match boundary {
                0 => 0,
                1 => cost.work_bytes - 1,
                _ => cost.work_bytes,
            };
            let remaining = decoder.remaining(OperandResource::ByteVisits).unwrap();
            decoder.bytes(remaining - allowance).unwrap();
            let before = metadata.used;
            let started = ledger.record_funded(
                &effect,
                EffectEvent::WorkStarted {
                    work: &work,
                    owner: WorkOwner::Inline,
                },
                |cost| metadata.charge(cost, decoder, expansion, &mut comparison),
            );
            assert_eq!(started.is_ok(), boundary == 2);
            assert_eq!(metadata.used, before);
            assert_eq!(ledger.event_count(), if boundary == 2 { 2 } else { 1 });
            assert_eq!(
                ledger.recorded_work(&effect).unwrap().is_some(),
                boundary == 2
            );
            assert_eq!(ledger.pending_effects().next(), Some(&effect));
            assert_eq!(comparison.ready().is_ok(), boundary == 2);
        });
    }
}

#[test]
fn shared_lifecycle_12_selected_core_success_requires_actual_work_and_result() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let mut raw = observation(vec![pending("inspection"), resolved("inspection", "{}")]);
        raw["checkpoints"][0]["eventCount"] = json!(1);
        raw["checkpoints"][0]["pendingEffects"] = json!([effect("inspection")]);
        let actual = decode(&raw, decoder);
        assert!(
            context
                .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
                .is_err(),
            "selected execute-pending-core cannot be replaced by unwitnessed Promise success"
        );
    });
}

#[test]
fn shared_lifecycle_13_existing_decode_and_expansion_faults_stop_all_new_work() {
    use crate::workbench::model_originals::workflow::OperandResource;
    for failed in 0..2 {
        record_boundary_support::with_v3_work(|context, decoder, expansion| {
            let actual = decode(&observation(vec![]), decoder);
            if failed == 0 {
                assert!(decoder.bytes(usize::MAX).is_err());
            } else {
                assert!(expansion.measure_metadata(usize::MAX, 0).is_err());
            }
            let mut comparison = owner();
            let first = context
                .check_client_lifecycle(&actual, decoder, expansion, &mut comparison)
                .err()
                .unwrap();
            if failed == 0 {
                assert!(matches!(
                    first,
                    ObservationError::Lifecycle {
                        kind: super::LifecycleFault::DecodeWork(OperandResource::ByteVisits),
                        ..
                    }
                ));
            } else {
                assert!(matches!(
                    first,
                    ObservationError::Lifecycle {
                        kind: super::LifecycleFault::Expansion(_),
                        ..
                    }
                ));
            }
            let before = (decoder.usage(), expansion.usage(), comparison.usage());
            assert_eq!(
                first,
                context
                    .check_client_lifecycle(&actual, decoder, expansion, &mut comparison)
                    .err()
                    .unwrap()
            );
            assert_eq!(
                before,
                (decoder.usage(), expansion.usage(), comparison.usage())
            );
        });
    }
}

#[test]
fn shared_lifecycle_14_same_shaped_unbound_expected_count_is_not_the_original_operand() {
    record_boundary_support::with_v3_work(|context, decoder, expansion| {
        let actual = decode(
            &observation(vec![
                pending("manifest-fetch"),
                resolved("manifest-fetch", "{}"),
            ]),
            decoder,
        );
        let source: Value = serde_json::from_str(include_str!(
            "../../source_compile/controls/bound-corpus.json"
        ))
        .unwrap();
        let check = source["cases"][0]["expected"]["checks"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["kind"] == "port-counts")
            .unwrap();
        let unbound: domain::ExpectedClientCheck = decoder.decode(&check.to_string()).unwrap();
        let checked = context
            .check_client_lifecycle(&actual, decoder, expansion, &mut owner())
            .unwrap();
        assert!(matches!(
            checked.check_port_counts(&unbound, &mut owner()),
            Err(ObservationError::Lifecycle {
                kind: super::LifecycleFault::Source,
                ..
            })
        ));
    });
}

#[test]
fn shared_lifecycle_15_original_observer_credit_boundary_and_overflow_keep_lifecycle() {
    use crate::workbench::model_originals::{
        EffectEvent, EffectKind, EffectLedger, EffectLedgerError, EffectLedgerLimits,
        EffectLedgerResource, EffectPort, EffectRef,
    };
    let effect = EffectRef::new("actual-port", EffectKind::ManifestFetch, 0).unwrap();
    let mut ledger = EffectLedger::new(EffectLedgerLimits::new(4, 8, 16, 16, 6).unwrap());
    ledger
        .record(&effect, EffectEvent::Pending(EffectPort::Promise))
        .unwrap();
    ledger.preflight_payload_comparison(3, 3).unwrap();
    assert_eq!(ledger.observer_bytes(), 6);
    assert_eq!(
        ledger.preflight_payload_comparison(0, 1),
        Err(EffectLedgerError::Resource(
            EffectLedgerResource::ObserverBytes
        ))
    );
    assert_eq!(
        ledger.preflight_payload_comparison(usize::MAX, 1),
        Err(EffectLedgerError::Resource(
            EffectLedgerResource::ObserverBytes
        ))
    );
    assert_eq!(ledger.observer_bytes(), 6);
    assert_eq!(ledger.event_count(), 1);
    assert_eq!(ledger.pending_effects().count(), 1);
    ledger
        .record(&effect, EffectEvent::PromiseResolvedWithoutCoreResult)
        .unwrap();
    ledger.finish().unwrap();
    assert_eq!(ledger.observer_bytes(), 6);
}

#[test]
fn shared_lifecycle_16_mismatching_core_payload_still_spends_same_observer_credit() {
    use crate::workbench::model_originals::{
        EffectEvent, EffectKind, EffectLedger, EffectLedgerError, EffectLedgerLimits,
        EffectLedgerResource, EffectPort, EffectRef, FixtureAlias, WorkOwner,
    };
    let work = FixtureAlias::new("actual-work").unwrap();
    let effect = EffectRef::new("actual-port", EffectKind::Inspection, 0).unwrap();
    let mut ledger = EffectLedger::new(EffectLedgerLimits::new(4, 8, 16, 16, 4).unwrap());
    ledger
        .record(&effect, EffectEvent::Pending(EffectPort::Promise))
        .unwrap();
    ledger
        .record(
            &effect,
            EffectEvent::WorkStarted {
                work: &work,
                owner: WorkOwner::Inline,
            },
        )
        .unwrap();
    ledger
        .record(
            &effect,
            EffectEvent::ResultPrepared {
                work: &work,
                raw_reply: "aa",
            },
        )
        .unwrap();
    assert_eq!(
        ledger.record(&effect, EffectEvent::PromiseResolved { actual_reply: "bb" }),
        Err(EffectLedgerError::ResultMismatch)
    );
    assert_eq!(ledger.observer_bytes(), 4);
    assert_eq!(
        ledger.preflight_payload_comparison(0, 1),
        Err(EffectLedgerError::Resource(
            EffectLedgerResource::ObserverBytes
        ))
    );
    assert_eq!(ledger.event_count(), 3);
    assert_eq!(ledger.pending_effects().count(), 1);
    assert_eq!(ledger.held_result_bytes(), 2);
}

#[test]
fn shared_lifecycle_17_publication_owner_claims_require_the_unimplemented_source_join() {
    for actual_owner in [json!("attempt-A"), Value::Null, json!("unbound-owner")] {
        record_boundary_support::with_v3_work(|context, decoder, expansion| {
            let actual = decode(
                &observation(vec![
                    pending("manifest-fetch"),
                    resolved("manifest-fetch", "{}"),
                    json!({"kind":"publication-disposition","effect":effect("manifest-fetch"),
                        "actualOpeningOwner":actual_owner,"disposition":"forwarded-by-currentness-guard"}),
                ]),
                decoder,
            );
            let mut comparison = owner();
            let refusal = context
                .check_client_lifecycle(&actual, decoder, expansion, &mut comparison)
                .err();
            assert_eq!(
                refusal,
                Some(ObservationError::Lifecycle {
                    event: 2,
                    kind: super::LifecycleFault::UnjoinedPublication,
                })
            );
            assert!(matches!(
                comparison.ready(),
                Err(ObservationError::Lifecycle {
                    event: 2,
                    kind: super::LifecycleFault::UnjoinedPublication,
                })
            ));
        });
    }
}

#[test]
fn shared_lifecycle_22_final_scans_require_the_same_remaining_structural_work() {
    use super::super::CompareResource;
    use crate::workbench::model_originals::{
        EffectEvent, EffectKind, EffectLedger, EffectLedgerLimits, EffectPort, EffectRef,
    };
    for allowance in [0, 2, 3] {
        record_boundary_support::with_v3_work(|_, decoder, expansion| {
            let mut ledger = EffectLedger::new(EffectLedgerLimits::new(1, 4, 16, 16, 16).unwrap());
            let effect = EffectRef::new("actual-port", EffectKind::ManifestFetch, 0).unwrap();
            let mut comparison = owner();
            let mut metadata = super::LifecycleMetadata {
                limit: 1_048_576,
                used: 0,
            };
            ledger
                .prepare_funded_storage(1, 0, |cost| {
                    metadata.charge(cost, decoder, expansion, &mut comparison)
                })
                .unwrap();
            for event in [
                EffectEvent::Pending(EffectPort::Promise),
                EffectEvent::PromiseRejected,
            ] {
                ledger
                    .record_funded(&effect, event, |cost| {
                        metadata.charge(cost, decoder, expansion, &mut comparison)
                    })
                    .unwrap();
            }
            let remaining = 1_000_000 - comparison.usage().visits;
            comparison
                .charge(CompareResource::StructuralVisits, remaining - allowance)
                .unwrap();
            assert!(
                matches!(
                    ledger.finish(),
                    Err(crate::workbench::model_originals::EffectLedgerError::Storage)
                ),
                "ordinary finish cannot bypass the funded boundary"
            );
            let finished = ledger
                .finish_funded(|cost| metadata.charge(cost, decoder, expansion, &mut comparison));
            let finished = super::funded(finished, &mut comparison, 2);
            assert_eq!(
                finished.is_ok(),
                allowance == 3,
                "three separate complete port scans need their own structural credit"
            );
            if allowance < 3 {
                assert_eq!(
                    finished,
                    Err(ObservationError::Resource(
                        CompareResource::StructuralVisits
                    ))
                );
                assert!(comparison.ready().is_err());
            }
            assert_eq!(ledger.event_count(), 2);
            assert_eq!(ledger.port_count(), 1);
            assert_eq!(ledger.pending_effects().count(), 0);
            assert_eq!(ledger.held_result_bytes(), 0);
        });
    }
}

#[test]
fn shared_lifecycle_23_funded_finish_preserves_lifecycle_error_precedence() {
    use crate::workbench::model_originals::{
        EffectEvent, EffectKind, EffectLedger, EffectLedgerError, EffectLedgerLimits, EffectPort,
        EffectRef, FixtureAlias, ResultRetirement, WorkOwner,
    };
    for phase in 0..3 {
        record_boundary_support::with_v3_work(|_, decoder, expansion| {
            let work = FixtureAlias::new("actual-work").unwrap();
            let effect = EffectRef::new("actual-port", EffectKind::Inspection, 0).unwrap();
            let mut ledger = EffectLedger::new(EffectLedgerLimits::new(1, 8, 16, 16, 16).unwrap());
            let mut comparison = owner();
            let mut metadata = super::LifecycleMetadata {
                limit: 1_048_576,
                used: 0,
            };
            ledger
                .prepare_funded_storage(1, 1, |cost| {
                    metadata.charge(cost, decoder, expansion, &mut comparison)
                })
                .unwrap();
            let mut events = vec![
                EffectEvent::Pending(EffectPort::Promise),
                EffectEvent::WorkStarted {
                    work: &work,
                    owner: WorkOwner::Inline,
                },
                EffectEvent::ResultPrepared {
                    work: &work,
                    raw_reply: "{}",
                },
            ];
            if phase >= 1 {
                events.push(EffectEvent::PromiseRejected);
            }
            if phase == 2 {
                events.push(EffectEvent::ResultRetired(
                    ResultRetirement::DiscardedOnTeardown,
                ));
            }
            for event in events {
                ledger
                    .record_funded(&effect, event, |cost| {
                        metadata.charge(cost, decoder, expansion, &mut comparison)
                    })
                    .unwrap();
            }
            let before = ledger.event_count();
            let visits = comparison.usage().visits;
            let finished = ledger
                .finish_funded(|cost| metadata.charge(cost, decoder, expansion, &mut comparison));
            let expected = match phase {
                0 => EffectLedgerError::PendingPorts,
                1 => EffectLedgerError::HeldResults,
                _ => EffectLedgerError::RunningWork,
            };
            assert_eq!(
                finished,
                Err(
                    crate::workbench::model_originals::effects::FundedEffectLedgerError::Ledger(
                        expected
                    )
                )
            );
            assert_eq!(comparison.usage().visits - visits, 3);
            assert_eq!(ledger.event_count(), before);
            assert_eq!(ledger.port_count(), 1);
        });
    }
}

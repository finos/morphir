//! Literal private-protocol vectors, NOT positive business/report evidence.
//! Every codec exercise borrows the genuine full24 Run and funded endpoints.
//! The partial-I/O control uses actual owned sockets, not a Node event loop.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::installed::adapter::processes::consumer::wire::{
    ConsumerAckProgress, ConsumerCodecError, ConsumerEnvelopeKind, ConsumerReceiveProgress,
};
mod stateful_tests;

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct Vector {
    name: String,
    role: String,
    direction: String,
    kind: String,
    payload: String,
    #[serde(rename = "wireHex")]
    wire_hex: String,
}
fn vectors() -> Vec<Vector> {
    serde_json::from_str(include_str!("encoded-vectors.json")).unwrap()
}
fn unhex(text: &str) -> Vec<u8> {
    assert_eq!(text.len() % 2, 0);
    text.as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| {
            let digit = |b| match b {
                b'0'..=b'9' => b - b'0',
                b'a'..=b'f' => b - b'a' + 10,
                _ => panic!("literal lowercase hex"),
            };
            digit(pair[0]) * 16 + digit(pair[1])
        })
        .collect()
}
fn framed(payload: &[u8]) -> Vec<u8> {
    let mut out = u32::try_from(payload.len()).unwrap().to_be_bytes().to_vec();
    out.extend_from_slice(payload);
    out
}
#[derive(Clone, Copy)]
enum Exercise {
    Vectors,
    ShapeRefusals,
    FramingRefusals,
    RoleAndDirection,
    PriorFault,
    PartialCacheAck,
    ReadOutcomeShapes,
    StorageRefusal,
    EmptyStorageRefusal,
}
struct Probe {
    exercise: Exercise,
    entered: bool,
    owner: std::sync::Arc<TestGateOwner>,
}
impl InstalledClientAdapter for Probe {
    fn observe(
        &mut self,
        mut run: InstalledClientRun<'_>,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        assert!(!self.entered);
        self.entered = true;
        let projection: std::sync::Arc<dyn InvocationGateSource> = self.owner.clone();
        let _token = run
            .issue_host_observation(std::sync::Arc::downgrade(&projection))
            .unwrap();
        let end = Instant::now() + Duration::from_secs(10);
        run.bind_consumer_window(end).unwrap();
        let program = std::env::current_exe().unwrap().canonicalize().unwrap();
        let directory = tempfile::tempdir().unwrap();
        let (prepared, mut ports) = if matches!(self.exercise, Exercise::PartialCacheAck) {
            stateful_tests::prepare_unit_ports(
                &mut run,
                &program,
                directory.path(),
                end,
                stateful_tests::FixtureStrategy::NodePackage,
            )
        } else {
            run.prepare_consumer_process(
                ConsumerProcessCommand {
                    purpose: InstalledProcessPurpose::Canonical {
                        action_index: 8,
                        command: InstalledCommand::Publish,
                    },
                    program: &program,
                    arguments: &[],
                    directory: directory.path(),
                    environment: &[],
                    limits: Limits {
                        max_frame: 131072,
                        stderr_capture: 128,
                        ..Limits::DEFAULT
                    },
                },
                end,
            )
            .unwrap()
        };
        let all = vectors();
        let open = all.iter().find(|v| v.name == "open").unwrap();
        match self.exercise {
            Exercise::Vectors => {
                for vector in &all {
                    let wire = unhex(&vector.wire_hex);
                    assert_eq!(
                        &wire[..4],
                        u32::try_from(vector.payload.len()).unwrap().to_be_bytes()
                    );
                    assert_eq!(&wire[4..], vector.payload.as_bytes());
                    let role = match vector.role.as_str() {
                        "outer" => ConsumerProducerRole::Outer,
                        "helper" => ConsumerProducerRole::TransferHelper,
                        _ => panic!("test vector role"),
                    };
                    if vector.direction == "ack" {
                        let ack = run
                            .decode_consumer_ack_literal(&ports, role, &wire)
                            .unwrap();
                        assert_eq!(ack.sequence(), 1);
                        assert_eq!(ack.literal_utf8(), vector.payload);
                    } else {
                        let decoded = run
                            .decode_consumer_frame_literal(&ports, role, &wire)
                            .unwrap();
                        let kind = match vector.kind.as_str() {
                            "open" => ConsumerEnvelopeKind::Open,
                            "fact" => ConsumerEnvelopeKind::Fact,
                            "helper-started" => ConsumerEnvelopeKind::HelperStarted,
                            "close" => ConsumerEnvelopeKind::Close,
                            _ => panic!("literal envelope kind"),
                        };
                        assert_eq!(decoded.kind(), kind, "{}", vector.name);
                        assert_eq!(decoded.literal_utf8(), vector.payload);
                    }
                }
            }
            Exercise::ShapeRefusals => {
                // Each is otherwise valid JSON. Duplicate members are the
                // existing strict reader's JSON fault, never last-key-wins.
                let cases: &[(&[u8],ConsumerCodecError)] = &[
                    (br#"{"kind":"open","version":"0.1.0-draft.1","sequence":0,"sequence":0}"#,ConsumerCodecError::Json),
                    (br#"{"kind":"open","version":"0.1.0-draft.1","sequence":0,"role":"outer"}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"open","version":"0.1.0-draft.1","sequence":0,"pid":1}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"open","version":"v0.1.0-draft.1","sequence":0}"#,ConsumerCodecError::Revision),
                    (br#"{"kind":"open","version":"0.1.0-draft.2","sequence":0}"#,ConsumerCodecError::Revision),
                    (br#"{"kind":"open","version":"0.1.0-draft.1","sequence":0.0}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"open","version":"0.1.0-draft.1","sequence":0e0}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"open","version":"0.1.0-draft.1","sequence":-0}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"open","version":"0.1.0-draft.1","sequence":"0"}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"faulted-close","version":"0.1.0-draft.1","sequence":1}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"close","version":"0.1.0-draft.1","sequence":1,"attemptedHooks":0,"startedFactFrames":0,"retainedBusinessFacts":0,"helper":{"kind":"not-attempted"},"delivery":"faulted"}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"fact","version":"0.1.0-draft.1","sequence":1,"fact":{"kind":"checked","verdict":true}}"#,ConsumerCodecError::Shape),
                    (br#"{"kind":"fact","version":"0.1.0-draft.1","sequence":1,"fact":{"kind":"destination-commit-finished","path":{"kind":"unix-bytes","bytes":{"kind":"repeat-u8","byte":47,"length":10}},"policy":"create","outcome":"returned"}}"#,ConsumerCodecError::Shape),
                ];
                for (payload, expected) in cases {
                    let result = run.decode_consumer_frame_literal(
                        &ports,
                        ConsumerProducerRole::Outer,
                        &framed(payload),
                    );
                    assert_eq!(result.err(), Some(*expected));
                    // Codec-only literal refusal is DATA validation. It must
                    // not create ACK authority or pretend a physical receive.
                }
            }
            Exercise::FramingRefusals => {
                let valid = unhex(&open.wire_hex);
                let mut trailing = valid.clone();
                trailing.push(0);
                for bad in [&valid[..3], &valid[..valid.len() - 1], trailing.as_slice()] {
                    assert_eq!(
                        run.decode_consumer_frame_literal(&ports, ConsumerProducerRole::Outer, bad)
                            .err(),
                        Some(ConsumerCodecError::Framing)
                    );
                }
                assert_eq!(
                    run.decode_consumer_frame_literal(
                        &ports,
                        ConsumerProducerRole::Outer,
                        &framed(&[255])
                    )
                    .err(),
                    Some(ConsumerCodecError::Utf8)
                );
                assert_eq!(
                    run.decode_consumer_frame_literal(
                        &ports,
                        ConsumerProducerRole::Outer,
                        &framed(b"{} {}")
                    )
                    .err(),
                    Some(ConsumerCodecError::Json)
                );
                assert_eq!(
                    run.decode_consumer_frame_literal(
                        &ports,
                        ConsumerProducerRole::Outer,
                        &131073u32.to_be_bytes()
                    )
                    .err(),
                    Some(ConsumerCodecError::FrameTooLarge)
                );
            }
            Exercise::RoleAndDirection => {
                for (name, wrong) in [
                    ("release", ConsumerProducerRole::Outer),
                    ("commit-returned", ConsumerProducerRole::TransferHelper),
                    ("helper-started", ConsumerProducerRole::TransferHelper),
                ] {
                    let wire = unhex(&all.iter().find(|v| v.name == name).unwrap().wire_hex);
                    assert_eq!(
                        run.decode_consumer_frame_literal(&ports, wrong, &wire)
                            .err(),
                        Some(ConsumerCodecError::Role)
                    );
                }
                let ack = unhex(&all.iter().find(|v| v.name == "retained").unwrap().wire_hex);
                assert_eq!(
                    run.decode_consumer_frame_literal(&ports, ConsumerProducerRole::Outer, &ack)
                        .err(),
                    Some(ConsumerCodecError::Direction)
                );
                assert_eq!(
                    run.decode_consumer_ack_literal(
                        &ports,
                        ConsumerProducerRole::Outer,
                        &unhex(&open.wire_hex)
                    )
                    .err(),
                    Some(ConsumerCodecError::Direction)
                );
            }
            Exercise::PriorFault => {
                let refused = *run
                    .prepare_snapshot_read(16777217)
                    .err()
                    .expect("real receiving snapshot refusal");
                let before = run.installed_observation_usage();
                assert_eq!(
                    run.decode_consumer_frame_literal(
                        &ports,
                        ConsumerProducerRole::Outer,
                        &unhex(&open.wire_hex)
                    )
                    .err(),
                    Some(ConsumerCodecError::PriorFault)
                );
                assert_eq!(run.installed_observation_usage(), before);
                assert_eq!(run.receiving.ready().err(), Some(&refused));
            }
            Exercise::StorageRefusal | Exercise::EmptyStorageRefusal => {
                let limit = 16_777_216u64;
                let remaining = limit
                    .checked_sub(run.installed_observation_usage().retained_bytes())
                    .unwrap();
                run.reserve_storage(usize::try_from(remaining - 1).unwrap())
                    .unwrap();
                let reader_before = run.decode.usage();
                let wire = if matches!(self.exercise, Exercise::EmptyStorageRefusal) {
                    framed(&[])
                } else {
                    unhex(&open.wire_hex)
                };
                let result =
                    run.decode_consumer_frame_literal(&ports, ConsumerProducerRole::Outer, &wire);
                assert!(matches!(
                    result,
                    Err(ConsumerCodecError::Resource(
                        InstalledObservationError::Resource {
                            kind: InstalledObservationResource::RetainedBytes,
                            limit: 16_777_216,
                            used: 16_777_215,
                            requested: 2..,
                        }
                    ))
                ));
                let decoder_after = run.decode.usage();
                assert_eq!(decoder_after.literal, reader_before.literal);
                assert_eq!(decoder_after.slots, reader_before.slots);
                assert_eq!(
                    decoder_after.byte_visits - reader_before.byte_visits,
                    wire.len()
                );
                let receiving_after = run.installed_observation_usage();
                assert_eq!(
                    run.decode_consumer_frame_literal(&ports, ConsumerProducerRole::Outer, &wire,)
                        .err(),
                    Some(ConsumerCodecError::PriorFault)
                );
                assert_eq!(run.installed_observation_usage(), receiving_after);
                assert_eq!(run.decode.usage(), decoder_after);
            }
            Exercise::PartialCacheAck => {
                let wire = unhex(&open.wire_hex);
                let child = prepared.test_child_handle(ConsumerProducerRole::Outer);
                assert_eq!(rustix::io::write(child, &wire[..2]).unwrap(), 2);
                assert!(matches!(
                    run.poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                        .unwrap(),
                    ConsumerReceiveProgress::Pending
                ));
                assert!(matches!(
                    rustix::io::read(child, &mut [0u8; 1]),
                    Err(rustix::io::Errno::AGAIN)
                ));
                assert_eq!(
                    rustix::io::write(child, &wire[2..]).unwrap(),
                    wire.len() - 2
                );
                let mut pending = match run
                    .poll_consumer_frame(&mut ports, ConsumerProducerRole::Outer)
                    .unwrap()
                {
                    ConsumerReceiveProgress::Retained(pending) => pending,
                    ConsumerReceiveProgress::Pending => {
                        panic!("complete tiny actual socket frame must be available")
                    }
                    ConsumerReceiveProgress::AwaitingAssociation => {
                        panic!("Outer Open cannot await helper association")
                    }
                    ConsumerReceiveProgress::Unused => {
                        panic!("Outer Open cannot be an unused helper endpoint")
                    }
                };
                assert_eq!(
                    run.test_consumer_cache(ConsumerProducerRole::Outer)
                        .last()
                        .unwrap()
                        .literal_utf8(),
                    open.payload
                );
                assert!(
                    matches!(
                        rustix::io::read(child, &mut [0u8; 1]),
                        Err(rustix::io::Errno::AGAIN)
                    ),
                    "cache precedes ANY ACK byte"
                );
                assert!(matches!(
                    run.write_consumer_ack(&mut ports, &mut pending).unwrap(),
                    ConsumerAckProgress::Complete
                ));
                let mut actual = [0u8; 256];
                let count = rustix::io::read(child, &mut actual).unwrap();
                assert_eq!(
                    &actual[..count],
                    framed(br#"{"kind":"retained","version":"0.1.0-draft.1","sequence":0}"#)
                );
            }
            Exercise::ReadOutcomeShapes => {
                let eof = &all
                    .iter()
                    .find(|v| v.name == "helper-short-read-eof")
                    .unwrap()
                    .payload;
                let failure = &all
                    .iter()
                    .find(|v| v.name == "started-helper-close")
                    .unwrap()
                    .payload;
                let unavailable = &all
                    .iter()
                    .find(|v| v.name == "helper-partial-read-error-unavailable")
                    .unwrap()
                    .payload;
                let bad = [
                    eof.replace(",\"byteLength\":\"3\"", ""),
                    eof.replace("\"byteLength\":\"3\"", "\"byteLength\":\"03\""),
                    eof.replace("\"byteLength\":\"3\"", "\"byteLength\":3"),
                    eof.replace("\"short-read\"", "\"eof\""),
                    eof.replace("\"short-read\",", "\"short-read\",\"errorCode\":\"5\","),
                    failure.replace("\"code\":\"5\"", "\"code\":\"0\""),
                    failure.replace("\"operation\":\"read\"", "\"operation\":\"seek\""),
                    failure.replace("\"operation\":\"read\"", "\"operation\":\"size\""),
                    unavailable.replace(
                        "\"kind\":\"unavailable\"",
                        "\"kind\":\"unavailable\",\"code\":\"5\"",
                    ),
                ];
                for payload in bad {
                    assert!(matches!(
                        run.decode_consumer_frame_literal(
                            &ports,
                            ConsumerProducerRole::Outer,
                            &framed(payload.as_bytes())
                        ),
                        Err(ConsumerCodecError::Shape)
                    ));
                }
            }
        }
        drop(prepared);
        drop(ports);
        Err(InstalledAdapterError::ObservationIncomplete)
    }
}
fn exercise(which: Exercise) {
    let kit = tempfile::tempdir().unwrap();
    std::fs::write(kit.path().join("cases.json"), CASES).unwrap();
    let mut policy = foundation_policy();
    policy["consumerObservation"] =
        serde_json::json!({"mode":"operation-port","version":"0.1.0-draft.1"});
    let mut probe = Probe {
        exercise: which,
        entered: false,
        owner: std::sync::Arc::new(TestGateOwner {
            gate: InvocationGate::dormant(),
        }),
    };
    let report = run_configured_with_installed_client_adapter(
        kit.path(),
        &RunConfiguration::from_json(&policy.to_string()).unwrap(),
        &mut probe,
    )
    .unwrap();
    assert!(probe.entered, "genuine complete24 callback required");
    assert!(!report.qualified());
}
#[test]
fn encoded_literals_cover_all_closed_envelopes_without_issuing_ack_authority() {
    exercise(Exercise::Vectors)
}
#[test]
fn encoded_literals_reject_unknown_duplicate_revision_and_noncanonical_members() {
    exercise(Exercise::ShapeRefusals)
}
#[test]
fn encoded_literals_require_strict_utf8_exact_big_endian_lengths_and_no_trailing_bytes() {
    exercise(Exercise::FramingRefusals)
}
#[test]
fn endpoint_roles_and_ack_direction_cannot_be_selected_by_payload() {
    exercise(Exercise::RoleAndDirection)
}
#[test]
fn real_prior_owner_refusal_prevents_decode_and_retry_spend() {
    exercise(Exercise::PriorFault)
}
#[test]
fn same_owner_storage_refusal_precedes_strict_reader_and_retry_spend() {
    exercise(Exercise::StorageRefusal)
}
#[test]
fn empty_body_diagnostic_storage_refusal_precedes_strict_reader_and_retry_spend() {
    exercise(Exercise::EmptyStorageRefusal)
}
#[test]
fn actual_partial_socket_frame_is_cached_before_any_retained_ack_byte() {
    exercise(Exercise::PartialCacheAck)
}
#[test]
fn reader_outcomes_preserve_partial_eof_and_genuine_or_unavailable_error_without_inventing_errno() {
    exercise(Exercise::ReadOutcomeShapes)
}

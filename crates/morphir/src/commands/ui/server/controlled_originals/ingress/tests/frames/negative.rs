//! Proposed child of ingress::tests::frames. Literal hostile codec DATA only.
//! Reuses the unchanged real source, bootstrap, raw cache and frame helpers.
use super::super::super::DocumentIngressFault;
use super::*;
use morphir_mck::workbench::{
    BrowserActionKind, BrowserInputError, BrowserLoans, ControlledHostStimulus, RunConfiguration,
    load, with_prepared_browser_clients,
};

// A refusal intentionally latches the same owners. Finish the genuine full
// client visit before invoking it; an ensuing visit must not obscure that
// original typed refusal with the old helper's post-action unwrap.
fn with_negative_stimulus<R>(
    run: impl FnOnce(ControlledHostStimulus, &mut BrowserLoans<'_, '_>) -> R,
) -> (R, BrowserSourceTerminal) {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(
        root.path().join("cases.json"),
        include_str!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker: serde_json::Value = serde_json::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"),
        "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
    let configuration = RunConfiguration::from_json(
        &serde_json::json!({
            "kind":"model-originals-browser", "browser":"chromium", "checker":checker,
            "receiving": { "retainedBytes":8388608, "stdoutPrefixBytes":0,
                "stderrPrefixBytes":0, "snapshotReadBytes":0, "byteVisits":8388608, "records":0 }
        })
        .to_string(),
    )
    .unwrap();
    let corpus = load(root.path()).unwrap();
    let outcome = with_prepared_browser_clients(&corpus, &configuration, |clients, loans| {
        let mut selected = None;
        clients.visit(loans, |client, loans| {
            if selected.is_none() {
                let opening = client.actions(loans)?.find(|action| {
                    matches!(
                        action.kind(),
                        BrowserActionKind::BeginConnectedOpening { .. }
                    )
                });
                if let Some(opening) = opening {
                    selected = Some(client.prepare_controlled_host(loans, opening.position())?);
                }
            }
            Ok::<_, BrowserInputError>(())
        })?;
        let stimulus = selected.expect("one actual full-corpus controlled opening is required");
        Ok::<_, BrowserInputError>(run(stimulus, loans))
    })
    .unwrap();
    let (result, terminal) = outcome.into_parts();
    (result.unwrap(), terminal)
}

#[derive(Clone, Copy)]
enum Scenario {
    SequenceBodyMismatch,
    UnknownField,
    ByteAfterEnd,
    DuplicateStop,
}
struct StopObservation {
    first: Result<(), DocumentIngressFault>,
    wire: Result<Vec<u8>, Error>,
    second: Result<(), DocumentIngressFault>,
}
struct NegativeObservation {
    upgrade: (u16, Option<String>),
    first_ack: Option<Vec<u8>>,
    second_ack: Option<Vec<u8>>,
    invalid_not_acked: bool,
    cache: (bool, usize, usize),
}
struct Run {
    observed: Result<NegativeObservation, Error>,
    collected: Option<Result<DocumentCollectOutcome, tokio::time::error::Elapsed>>,
    stop: Option<StopObservation>,
    close_attempts: Vec<Result<Result<(), WsError>, tokio::time::error::Elapsed>>,
    joined: ControlledHostShutdown,
    unresolved: Option<std::mem::ManuallyDrop<BoundControlledUiHost>>,
    source: BrowserSourceTerminal,
}

async fn reject_literal(
    scenario: Scenario,
    peers: &mut [Peer],
    state: &Arc<HostState>,
    frames: (&[u8], &[u8], &[u8]),
    upgraded: (u16, Option<String>),
    end: Instant,
) -> Result<NegativeObservation, Error> {
    let (fact, end_frame, invalid) = frames;
    let peer = peers
        .first_mut()
        .ok_or_else(|| failure("actual document upgrade missing"))?;
    let mut first_ack = None;
    let mut second_ack = None;
    if !matches!(scenario, Scenario::DuplicateStop) {
        tokio::time::timeout_at(
            end.into(),
            peer.send(PeerMessage::Binary(fact.to_vec().into())),
        )
        .await??;
        first_ack = Some(binary_reply(peer, end).await?);
        if matches!(scenario, Scenario::ByteAfterEnd) {
            tokio::time::timeout_at(
                end.into(),
                peer.send(PeerMessage::Binary(end_frame.to_vec().into())),
            )
            .await??;
            second_ack = Some(binary_reply(peer, end).await?);
        }
        tokio::time::timeout_at(
            end.into(),
            peer.send(PeerMessage::Binary(invalid.to_vec().into())),
        )
        .await??;
    }
    // A collector refusal closes the real channel. A timeout is a test failure,
    // never an inference that the invalid input was not acknowledged.
    let reply = tokio::time::timeout_at(end.into(), peer.next()).await?;
    let invalid_not_acked = matches!(reply, None | Some(Ok(PeerMessage::Close(_))) | Some(Err(_)));
    let cache = if matches!(scenario, Scenario::DuplicateStop) {
        match state
            .document
            .as_ref()
            .and_then(|document| document.state.lock().ok())
        {
            Some(inner) => (
                inner.retention.bytes() == 0 && inner.retention.records() == 0,
                inner.retention.bytes(),
                inner.retention.records(),
            ),
            None => (false, usize::MAX, usize::MAX),
        }
    } else {
        retained_at_ack(
            state,
            fact,
            matches!(scenario, Scenario::ByteAfterEnd).then_some(end_frame),
        )
    };
    Ok(NegativeObservation {
        upgrade: upgraded,
        first_ack,
        second_ack,
        invalid_not_acked,
        cache,
    })
}

fn run_negative(scenario: Scenario) -> Run {
    let fact = literal_frame(1, 1, FACT_BODY);
    let end_frame = literal_frame(2, 2, END_BODY);
    let invalid = match scenario {
        // The frame header is monotone sequence2. Its body disagrees; this is
        // transport order validation, not an invented domain uniqueness rule.
        Scenario::SequenceBodyMismatch => literal_frame(1, 2,
            br#"{"sequence":3,"kind":"model-closed","actual":{"workspace":"unit","opening":0}}"#),
        Scenario::UnknownField => literal_frame(1, 2,
            br#"{"sequence":2,"kind":"model-closed","actual":{"workspace":"unit","opening":0},"unexpected":true}"#),
        Scenario::ByteAfterEnd => vec![0],
        Scenario::DuplicateStop => Vec::new(),
    };
    let runtime = runtime();
    let ((observed, collected, stop, close_attempts, joined, unresolved), source) =
        with_negative_stimulus(|stimulus, loans| {
            runtime.block_on(async {
                let end = Instant::now() + Duration::from_secs(20);
                let limits = DocumentIngressLimits {
                    observation_owners: OWNERS,
                    observation_events: EVENTS,
                    records: RECORDS,
                    journal_bytes: JOURNAL,
                    frame_bytes: FRAME,
                    socket_tasks: 6,
                    request_tickets: 16,
                    request_header_fields: 32,
                    request_header_bytes: 1024,
                };
                let mut host =
                    BoundControlledUiHost::bind_with_document_ingress(stimulus, loans, limits, end)
                        .await
                        .unwrap();
                let mut peers = Vec::new();
                let actual_state = Arc::clone(&host.state);
                let setup = match host.start() {
                    Ok(()) => open_literal_channel(&host, &mut peers, end).await,
                    Err(_) => Err(failure("actual host start failed")),
                };
                // STOP has no business fact. Observe its exact native wire before
                // requesting another one; otherwise the first refusal could stop
                // the writer before its first control frame was actually sent.
                let stop = if setup.is_ok() && matches!(scenario, Scenario::DuplicateStop) {
                    let first = host.request_document_stop();
                    let wire = match peers.first_mut() {
                        Some(peer) => binary_reply(peer, end).await,
                        None => Err(failure("actual STOP peer missing")),
                    };
                    let second = host.request_document_stop();
                    Some(StopObservation {
                        first,
                        wire,
                        second,
                    })
                } else {
                    None
                };
                let (observed, collected) = match setup {
                    Ok(upgraded) => {
                        let (observed, collected) = tokio::join!(
                            reject_literal(
                                scenario,
                                &mut peers,
                                &actual_state,
                                (&fact, &end_frame, &invalid),
                                upgraded,
                                end
                            ),
                            tokio::time::timeout_at(end.into(), host.collect_document(loans)),
                        );
                        (observed, Some(collected))
                    }
                    Err(cause) => (Err(cause), None),
                };
                drop(actual_state);
                let mut close_attempts = Vec::new();
                for mut peer in peers {
                    close_attempts
                        .push(tokio::time::timeout_at(end.into(), peer.close(None)).await);
                    drop(peer);
                }
                let mut joined = host.shutdown().await;
                for _ in 0..8 {
                    if !matches!(joined, ControlledHostShutdown::Pending { .. }) {
                        break;
                    }
                    tokio::task::yield_now().await;
                    joined = host.shutdown().await;
                }
                let unresolved = if matches!(joined, ControlledHostShutdown::Pending { .. }) {
                    Some(host)
                } else {
                    drop(host);
                    None
                };
                (
                    observed,
                    collected,
                    stop,
                    close_attempts,
                    joined,
                    unresolved,
                )
            })
        });
    Run {
        observed,
        collected,
        stop,
        close_attempts,
        joined,
        unresolved: unresolved.map(std::mem::ManuallyDrop::new),
        source,
    }
}

// All checks occur after the actual peer and host owners joined/dropped, or
// after an unresolved host was explicitly retained for failure reporting.
fn assert_negative(
    run: Run,
    expected: DocumentIngressFault,
    expected_records: usize,
) -> (NegativeObservation, Option<StopObservation>) {
    assert!(
        run.unresolved.is_none(),
        "same pending host retained after bounded cleanup retries"
    );
    assert!(matches!(
        run.joined,
        ControlledHostShutdown::Joined | ControlledHostShutdown::JoinedWithFault(_)
    ));
    // Refused channels may already have closed/reset their actual peer. Keep
    // inner close errors as evidence; no close result substitutes for joins.
    for actual in &run.close_attempts {
        assert!(
            actual.is_ok(),
            "actual refusal peer cleanup exceeded original end: {actual:?}"
        );
    }
    match run.collected {
        Some(Ok(DocumentCollectOutcome::Incomplete(actual))) => assert_eq!(actual, expected),
        Some(Err(cause)) => panic!("borrowed document collector exceeded original end: {cause}"),
        _ => panic!("invalid transport did not retain an incomplete collector outcome"),
    }
    let observed = run.observed.unwrap();
    assert_eq!(
        observed.upgrade,
        (101, Some("morphir-document-v1".to_owned()))
    );
    assert!(
        observed.invalid_not_acked,
        "refused frame must not produce an ACK/data response"
    );
    let raw = match expected_records {
        0 => 0,
        1 => literal_frame(1, 1, FACT_BODY).len(),
        2 => literal_frame(1, 1, FACT_BODY).len() + literal_frame(2, 2, END_BODY).len(),
        _ => unreachable!(),
    };
    assert_eq!(
        observed.cache,
        (true, raw, expected_records),
        "already retained bytes survive refusal unchanged"
    );
    assert!(matches!(
        run.source,
        BrowserSourceTerminal::Incomplete { .. }
    ));
    (observed, run.stop)
}

#[test]
fn browser_document_ingress_negative_01_retained_fact_then_header_body_sequence_disagreement_no_ack()
 {
    let (observed, _) = assert_negative(
        run_negative(Scenario::SequenceBodyMismatch),
        DocumentIngressFault::Order,
        1,
    );
    assert_eq!(observed.first_ack, Some(literal_frame(3, 1, &[])));
    assert!(observed.second_ack.is_none());
}

#[test]
fn browser_document_ingress_negative_02_retained_fact_then_unknown_body_field_no_ack() {
    let (observed, _) = assert_negative(
        run_negative(Scenario::UnknownField),
        DocumentIngressFault::Shape,
        1,
    );
    assert_eq!(observed.first_ack, Some(literal_frame(3, 1, &[])));
    assert!(observed.second_ack.is_none());
}

#[test]
fn browser_document_ingress_negative_03_end_ack_then_trailing_actual_byte_is_incomplete() {
    let (observed, _) = assert_negative(
        run_negative(Scenario::ByteAfterEnd),
        DocumentIngressFault::Framing,
        2,
    );
    assert_eq!(observed.first_ack, Some(literal_frame(3, 1, &[])));
    assert_eq!(observed.second_ack, Some(literal_frame(3, 2, &[])));
}

#[test]
fn browser_document_ingress_negative_04_exact_stop_zero_before_fact_then_second_request_refuses() {
    let (observed, stop) = assert_negative(
        run_negative(Scenario::DuplicateStop),
        DocumentIngressFault::Order,
        0,
    );
    let stop = stop.unwrap();
    assert_eq!(stop.first, Ok(()));
    assert_eq!(stop.wire.unwrap(), literal_frame(4, 0, &[]));
    assert_eq!(stop.second, Err(DocumentIngressFault::Order));
    assert!(observed.first_ack.is_none());
    assert!(observed.second_ack.is_none());
}

#[path = "negative/preparation.rs"]
mod preparation;

#[path = "negative/lifecycle.rs"]
mod lifecycle;

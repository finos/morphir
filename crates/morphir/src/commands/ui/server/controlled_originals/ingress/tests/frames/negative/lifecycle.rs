//! Proposed child of ingress::tests::frames::negative. W-only test input.
//! Literal codec transport and actual owners, no product/browser authority.
use super::*;
use crate::commands::ui::server::controlled_originals::{ActualPeerFault, ingress::Incoming};
use std::task::Poll;

const UTF16_FACT: &[u8] =
    br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"\ud800","opening":0}}"#;
type CloseResults = Vec<Result<Result<(), WsError>, tokio::time::error::Elapsed>>;

#[derive(Debug, PartialEq, Eq)]
struct OwnerSnapshot {
    task: Option<tokio::task::Id>,
    retained: usize,
    raw: Option<usize>,
    decoder: Option<usize>,
}
fn owner_snapshot(host: &BoundControlledUiHost) -> OwnerSnapshot {
    let raw = host
        .state
        .document
        .as_ref()
        .and_then(|document| document.state.lock().ok())
        .and_then(|inner| match &inner.retention {
            super::super::super::super::Retention::Local { raw, .. } => Some(raw.as_ptr() as usize),
            super::super::super::super::Retention::Engine { .. } => None,
        });
    OwnerSnapshot {
        task: host.cleanup.actual_task_id(),
        retained: host.cleanup.retained_tasks(),
        raw,
        decoder: host
            .document_decoder
            .as_ref()
            .map(|permission| permission as *const _ as usize),
    }
}
async fn finish_actual(
    mut host: BoundControlledUiHost,
    peers: Vec<Peer>,
    end: Instant,
) -> (
    CloseResults,
    ControlledHostShutdown,
    Option<BoundControlledUiHost>,
) {
    let mut closes = Vec::new();
    for mut peer in peers {
        closes.push(tokio::time::timeout_at(end.into(), peer.close(None)).await);
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
    (closes, joined, unresolved)
}
fn limits() -> DocumentIngressLimits {
    DocumentIngressLimits {
        observation_owners: OWNERS,
        observation_events: EVENTS,
        records: RECORDS,
        journal_bytes: JOURNAL,
        frame_bytes: FRAME,
        socket_tasks: 6,
        request_tickets: 16,
        request_header_fields: 32,
        request_header_bytes: 1024,
    }
}

#[test]
fn browser_document_ingress_lifecycle_01_pending_borrow_drop_retains_actual_owners_then_same_stream_resumes_losslessly()
 {
    let fact = literal_frame(1, 1, UTF16_FACT);
    let terminal_frame = literal_frame(2, 2, END_BODY);
    let runtime = runtime();
    let ((pending, before, after, observed, collected, closes, joined, unresolved), source) =
        with_negative_stimulus(|stimulus, loans| {
            runtime.block_on(async {
                let end = Instant::now() + Duration::from_secs(20);
                let mut host = BoundControlledUiHost::bind_with_document_ingress(
                    stimulus,
                    loans,
                    limits(),
                    end,
                )
                .await
                .unwrap();
                let mut peers = Vec::new();
                let actual_state = Arc::clone(&host.state);
                let setup = match host.start() {
                    Ok(()) => open_literal_channel(&host, &mut peers, end).await,
                    Err(_) => Err(failure("actual host start failed")),
                };
                let before = owner_snapshot(&host);
                // Poll the real borrowed collector exactly once, then cancel only
                // that future. There are no frames yet and no invented task/owner.
                let pending = {
                    let mut borrowed = Box::pin(tokio::time::timeout_at(
                        end.into(),
                        host.collect_document(loans),
                    ));
                    let pending = matches!(futures_util::poll!(borrowed.as_mut()), Poll::Pending);
                    drop(borrowed);
                    pending
                };
                let after = owner_snapshot(&host);
                let (observed, collected) = match setup {
                    Ok(upgraded) => {
                        let (observed, collected) = tokio::join!(
                            send_literals_with_tokens(
                                &mut peers,
                                &actual_state,
                                &fact,
                                &terminal_frame,
                                br#""\ud800""#,
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
                let (closes, joined, unresolved) = finish_actual(host, peers, end).await;
                (
                    pending, before, after, observed, collected, closes, joined, unresolved,
                )
            })
        });
    let unresolved = unresolved.map(std::mem::ManuallyDrop::new);
    assert!(
        unresolved.is_none(),
        "actual same host retained after bounded Pending cleanup"
    );
    assert_eq!(joined, ControlledHostShutdown::Joined);
    for close in closes {
        match close {
            Ok(Ok(())) | Ok(Err(WsError::ConnectionClosed | WsError::AlreadyClosed)) => {}
            actual => panic!("actual peer cleanup failed: {actual:?}"),
        }
    }
    assert!(
        pending,
        "the real collector was Pending before its borrow was dropped"
    );
    assert!(before.task.is_some() && before.retained > 0);
    assert!(before.raw.is_some_and(|pointer| pointer != 0));
    assert!(before.decoder.is_some_and(|pointer| pointer != 0));
    assert_eq!(
        before, after,
        "same actual cleanup handle, count, raw backing and decoder object survived cancellation"
    );
    let observed = observed.unwrap();
    assert_eq!(
        observed.upgrade,
        (101, Some("morphir-document-v1".to_owned()))
    );
    assert_eq!(observed.first_ack, literal_frame(3, 1, &[]));
    assert_eq!(observed.second_ack, literal_frame(3, 2, &[]));
    assert_eq!(observed.first_cache, (true, fact.len(), 1));
    assert_eq!(
        observed.second_cache,
        (true, fact.len() + terminal_frame.len(), 2)
    );
    assert!(matches!(
        observed.peer_close,
        Ok(()) | Err(WsError::ConnectionClosed | WsError::AlreadyClosed)
    ));
    assert!(observed.channel_eof);
    match collected {
        Some(Ok(DocumentCollectOutcome::Drained)) => {}
        Some(Err(cause)) => panic!("resumed collector exceeded original end: {cause}"),
        _ => panic!("same resumed collector did not drain"),
    }
    assert!(matches!(source, BrowserSourceTerminal::Incomplete { .. }));
}

async fn wait_actual_staged(
    state: &Arc<HostState>,
    expected: &[u8],
    end: Instant,
) -> Result<(), Error> {
    let document = state
        .document
        .as_ref()
        .ok_or_else(|| failure("actual document missing"))?;
    tokio::time::timeout_at(end.into(), async {
        loop {
            let changed = document.changed.notified();
            {
                let inner = document
                    .state
                    .lock()
                    .map_err(|_| failure("actual state poisoned"))?;
                if inner.first.is_some() {
                    return Err(failure("actual stream refused before staging"));
                }
                if matches!(&inner.incoming, Incoming::Staged(bytes) if bytes == expected) {
                    return Ok(());
                }
            }
            changed.await;
        }
    })
    .await?
}
async fn stage_then_reset(
    peers: &mut Vec<Peer>,
    state: &Arc<HostState>,
    fact: &[u8],
    end: Instant,
) -> Result<(), Error> {
    let peer = peers
        .first_mut()
        .ok_or_else(|| failure("actual document peer missing"))?;
    tokio::time::timeout_at(
        end.into(),
        peer.send(PeerMessage::Binary(fact.to_vec().into())),
    )
    .await??;
    // Observe real native staging before collection. No hook or artificial
    // collector barrier changes when the production handler receives a frame.
    wait_actual_staged(state, fact, end).await?;
    let peer = peers
        .pop()
        .ok_or_else(|| failure("actual staged peer missing"))?;
    match peer.get_ref() {
        MaybeTlsStream::Plain(actual_tcp) => {
            socket2::SockRef::from(actual_tcp).set_linger(Some(Duration::ZERO))?
        }
        _ => {
            return Err(failure(
                "this component fixture requires the actual plain TCP peer",
            ));
        }
    }
    // SO_LINGER=0 + disposal requests a genuine TCP reset. Kernel arrival vs
    // ACK write completion is not a deterministic LostAck proof seam.
    drop(peer);
    Ok(())
}
#[derive(Debug, PartialEq, Eq)]
enum ActualIo {
    None,
    Read,
    Write,
}
fn retained_io(state: &Arc<HostState>) -> Option<ActualIo> {
    let document = state.document.as_ref()?;
    let inner = document.state.lock().ok()?;
    Some(match &inner.actual_io {
        None => ActualIo::None,
        Some(ActualPeerFault::Read(_)) => ActualIo::Read,
        Some(ActualPeerFault::Write(_)) => ActualIo::Write,
    })
}

#[test]
fn browser_document_ingress_lifecycle_02_actual_staged_fact_survives_tcp_reset_and_sticky_collector_retry()
 {
    let fact = literal_frame(1, 1, FACT_BODY);
    let runtime = runtime();
    let (
        (setup, reset, first, retry, cache_before, cache_after, io, closes, joined, unresolved),
        source,
    ) = with_negative_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(20);
            let mut host =
                BoundControlledUiHost::bind_with_document_ingress(stimulus, loans, limits(), end)
                    .await
                    .unwrap();
            let mut peers = Vec::new();
            let actual_state = Arc::clone(&host.state);
            let setup = match host.start() {
                Ok(()) => open_literal_channel(&host, &mut peers, end).await,
                Err(_) => Err(failure("actual host start failed")),
            };
            let reset = match &setup {
                Ok(_) => stage_then_reset(&mut peers, &actual_state, &fact, end).await,
                Err(_) => Err(failure("actual bootstrap failed before reset")),
            };
            let first = tokio::time::timeout_at(end.into(), host.collect_document(loans)).await;
            let cache_before = retained_at_ack(&actual_state, &fact, None);
            let retry = tokio::time::timeout_at(end.into(), host.collect_document(loans)).await;
            let cache_after = retained_at_ack(&actual_state, &fact, None);
            let io = retained_io(&actual_state);
            drop(actual_state);
            let (closes, joined, unresolved) = finish_actual(host, peers, end).await;
            (
                setup,
                reset,
                first,
                retry,
                cache_before,
                cache_after,
                io,
                closes,
                joined,
                unresolved,
            )
        })
    });
    let unresolved = unresolved.map(std::mem::ManuallyDrop::new);
    assert!(
        unresolved.is_none(),
        "actual same reset host retained after bounded Pending cleanup"
    );
    assert!(matches!(
        joined,
        ControlledHostShutdown::Joined | ControlledHostShutdown::JoinedWithFault(_)
    ));
    for close in &closes {
        assert!(
            close.is_ok(),
            "remaining actual peer cleanup exceeded original end: {close:?}"
        );
    }
    assert_eq!(
        setup.unwrap(),
        (101, Some("morphir-document-v1".to_owned()))
    );
    reset.unwrap();
    let first = match first {
        Ok(DocumentCollectOutcome::Incomplete(cause)) => cause,
        Err(cause) => panic!("actual reset collector exceeded original end: {cause}"),
        _ => panic!("actual reset must not drain without END"),
    };
    match first {
        DocumentIngressFault::LostAck => assert_eq!(io, Some(ActualIo::Write)),
        DocumentIngressFault::PeerRead => assert_eq!(io, Some(ActualIo::Read)),
        DocumentIngressFault::ProducerIncomplete => assert_eq!(io, Some(ActualIo::None)),
        actual => panic!("unexpected actual reset refusal: {actual:?}"),
    }
    assert!(
        matches!(retry, Ok(DocumentCollectOutcome::Incomplete(cause)) if cause == first),
        "same collector retry preserves its actual earliest fault"
    );
    assert_eq!(cache_before, (true, fact.len(), 1));
    assert_eq!(cache_after, cache_before);
    assert!(matches!(source, BrowserSourceTerminal::Incomplete { .. }));
}

#[path = "lifecycle/shape.rs"]
mod shape;

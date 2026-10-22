//! Literal actual transport controls, not product/browser/source0 qualification.
use super::*;
use crate::commands::ui::server::controlled_originals::ingress::{
    DocumentCollectStep, await_staged_frame_for_test,
};
use std::task::Poll;

#[derive(Clone, Copy)]
enum Journey {
    End,
    SocketDrop,
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
fn journey(kind: Journey) {
    let runtime = runtime();
    let (actual, source) = with_negative_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(20);
            let mut host =
                BoundControlledUiHost::bind_with_document_ingress(stimulus, loans, limits(), end)
                    .await
                    .unwrap();
            let mut peers = Vec::new();
            let result: Result<_, Error> = async {
                host.start().map_err(|_| failure("actual host start"))?;
                let upgrade = open_literal_channel(&host, &mut peers, end).await?;
                if upgrade.0 != 101 {
                    return Err(failure("actual upgrade"));
                }
                if !matches!(
                    host.collect_document_step(loans),
                    DocumentCollectStep::AwaitingChange
                ) {
                    return Err(failure("empty stream was not waiting"));
                }
                // Cancel only a real pending notification wait. No host, frame,
                // decoder or cumulative loan owner is moved into that future.
                let pending = {
                    let mut waiting = std::pin::pin!(host.wait_document_change());
                    matches!(futures_util::poll!(waiting.as_mut()), Poll::Pending)
                };
                if !pending {
                    return Err(failure("initial actual wait not Pending"));
                }
                loans
                    .validate_controlled_source(&host.state.source)
                    .map_err(|_| failure("same loans unavailable after cancellation"))?;
                let fact = literal_frame(1, 1, FACT_BODY);
                let terminal = literal_frame(2, 2, END_BODY);
                let peer = peers.first_mut().ok_or_else(|| failure("actual peer"))?;
                peer.send(PeerMessage::Binary(fact.clone().into())).await?;
                await_staged_frame_for_test(&host, &fact, end)
                    .await
                    .map_err(|_| failure("actual frame not staged"))?;
                // Consume a stale single permit, then exercise notify_waiters
                // before a new wait exists. The actual staged bytes must make
                // the wait return even though that notification is not queued.
                {
                    let document = host.state.document.as_ref().unwrap();
                    let mut stale = std::pin::pin!(document.changed.notified());
                    let _ = futures_util::poll!(stale.as_mut());
                }
                host.state
                    .document
                    .as_ref()
                    .unwrap()
                    .changed
                    .notify_waiters();
                tokio::time::timeout(Duration::from_millis(250), host.wait_document_change())
                    .await
                    .map_err(|_| failure("staged state lost between step and wait"))?;
                let retained = host.collect_document_step(loans);
                if !matches!(retained, DocumentCollectStep::FrameRetained) {
                    return Err(failure("actual FACT not retained in one step"));
                }
                // The step returned both mutable borrows before this separate
                // SAME-owner validation and before the real ACK was read.
                loans
                    .validate_controlled_source(&host.state.source)
                    .map_err(|_| failure("same loans unavailable after step"))?;
                if retained_at_ack(&host.state, &fact, None) != (true, fact.len(), 1) {
                    return Err(failure("actual bytes absent before ACK"));
                }
                if binary_reply(peer, end).await? != literal_frame(3, 1, &[]) {
                    return Err(failure("actual FACT ACK differs"));
                }
                match kind {
                    Journey::SocketDrop => {
                        drop(peers.pop());
                        let terminal = loop {
                            let next = host.collect_document_step(loans);
                            if !matches!(next, DocumentCollectStep::AwaitingChange) {
                                break next;
                            }
                            host.wait_document_change().await;
                        };
                        if !matches!(
                            terminal,
                            DocumentCollectStep::Terminal(DocumentCollectOutcome::Incomplete(_))
                        ) {
                            return Err(failure("actual socket drop must remain incomplete"));
                        }
                        if retained_at_ack(&host.state, &fact, None) != (true, fact.len(), 1) {
                            return Err(failure("socket drop lost retained FACT"));
                        }
                    }
                    Journey::End => {
                        peer.send(PeerMessage::Binary(terminal.clone().into()))
                            .await?;
                        await_staged_frame_for_test(&host, &terminal, end)
                            .await
                            .map_err(|_| failure("actual END not staged"))?;
                        host.wait_document_change().await;
                        if !matches!(
                            host.collect_document_step(loans),
                            DocumentCollectStep::FrameRetained
                        ) {
                            return Err(failure("actual END not retained in one step"));
                        }
                        if binary_reply(peer, end).await? != literal_frame(3, 2, &[]) {
                            return Err(failure("actual END ACK differs"));
                        }
                        let (closed, collected) = tokio::join!(
                            async {
                                peer.close(None).await?;
                                while let Some(message) =
                                    tokio::time::timeout_at(end.into(), peer.next()).await?
                                {
                                    match message {
                                        Ok(_) => (),
                                        Err(WsError::ConnectionClosed | WsError::AlreadyClosed) => {
                                            break;
                                        }
                                        Err(error) => return Err::<(), Error>(error.into()),
                                    }
                                }
                                Ok(())
                            },
                            async {
                                loop {
                                    match host.collect_document_step(loans) {
                                        DocumentCollectStep::FrameRetained => (),
                                        DocumentCollectStep::AwaitingChange => {
                                            host.wait_document_change().await
                                        }
                                        DocumentCollectStep::Terminal(result) => break result,
                                    }
                                }
                            }
                        );
                        closed?;
                        if !matches!(collected, DocumentCollectOutcome::Drained) {
                            return Err(failure("actual stream did not physically drain"));
                        }
                    }
                }
                Ok(())
            }
            .await;
            // All assertion/error branches retain and clean the SAME owners.
            for mut peer in peers {
                let _ = tokio::time::timeout_at(end.into(), peer.close(None)).await;
            }
            let joined = host.finish_joined().await;
            (result, joined)
        })
    });
    use crate::commands::ui::server::controlled_originals::{
        ControlledHostFinish, ControlledHostJoined,
    };
    let joined = match actual.1 {
        ControlledHostFinish::Joined(joined) => joined,
        retained @ ControlledHostFinish::Retained { .. } => {
            let _retained = std::mem::ManuallyDrop::new(retained);
            panic!("actual host cleanup retained its physical owner");
        }
    };
    actual.0.unwrap();
    if matches!(kind, Journey::End) {
        assert_eq!(joined, ControlledHostJoined::Clean);
    }
    // Consuming finish_joined retires this exact native source binding after
    // actual socket/listener joins, including a truthfully faulted document.
    // Physical quiescence does not change that document's incomplete outcome.
    assert!(matches!(source, BrowserSourceTerminal::Quiescent));
}

#[test]
fn browser_document_collection_steps_01_actual_frames_ack_and_cancelled_wait_resume() {
    journey(Journey::End);
}
#[test]
fn browser_document_collection_steps_02_actual_socket_drop_preserves_partial_cache() {
    journey(Journey::SocketDrop);
}

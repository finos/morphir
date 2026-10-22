//! Proposed child of ingress::tests. Literal codec DATA, not actual product facts.
use super::super::DocumentCollectOutcome;
use super::*;
use crate::commands::ui::server::controlled_originals::HostState;
use futures_util::{SinkExt as _, StreamExt as _};
use std::sync::Arc;
use tokio_tungstenite::tungstenite::Message as PeerMessage;

const FACT_BODY: &[u8] =
    br#"{"sequence":1,"kind":"model-closed","actual":{"workspace":"unit","opening":0}}"#;
const END_BODY: &[u8] = br#"{"lastSequence":1,"observer":{"kind":"closed"}}"#;

fn literal_frame(kind: u8, sequence: u64, body: &[u8]) -> Vec<u8> {
    let mut bytes = vec![0; 16];
    bytes[0] = 1;
    bytes[1] = kind;
    bytes[4..12].copy_from_slice(&sequence.to_be_bytes());
    bytes[12..16].copy_from_slice(&u32::try_from(body.len()).unwrap().to_be_bytes());
    bytes.extend_from_slice(body);
    bytes
}

// Observe actual retained native state without a new getter or an allocating
// callback. A record includes its complete fixed header and JSON body.
fn retained_at_ack(
    state: &Arc<HostState>,
    fact: &[u8],
    end: Option<&[u8]>,
) -> (bool, usize, usize) {
    retained_tokens_at_ack(state, fact, end, br#""unit""#)
}
fn retained_tokens_at_ack(
    state: &Arc<HostState>,
    fact: &[u8],
    end: Option<&[u8]>,
    workspace_token: &[u8],
) -> (bool, usize, usize) {
    let Some(document) = state.document.as_ref() else {
        return (false, 0, 0);
    };
    let Ok(inner) = document.state.lock() else {
        return (false, 0, 0);
    };
    let super::super::Retention::Local { raw, records } = &inner.retention else {
        return (false, 0, 0);
    };
    let Some(first) = records.first() else {
        return (false, raw.len(), 0);
    };
    let typed_fact = match first.data.content() {
        morphir_mck::workbench::BrowserDocumentContent::Fact(
            morphir_mck::workbench::BrowserDocumentFactData::ModelClosed(actual),
        ) => {
            let payload = raw.get(first.bytes.start + 16..first.bytes.end);
            actual.opening().get() == 0
                && payload.and_then(|bytes| bytes.get(actual.workspace().range()))
                    == Some(workspace_token)
        }
        _ => false,
    };
    let first_ok = typed_fact
        && first.data.kind() == 1
        && first.data.sequence().get() == 1
        && first.bytes == (0..fact.len())
        && raw.get(first.bytes.clone()) == Some(fact);
    match end {
        None => (
            first_ok && records.len() == 1 && raw.len() == fact.len(),
            raw.len(),
            records.len(),
        ),
        Some(end) => {
            let Some(second) = records.get(1) else {
                return (false, raw.len(), records.len());
            };
            let finish = fact.len() + end.len();
            let typed_end = matches!(second.data.content(),
                morphir_mck::workbench::BrowserDocumentContent::End { last_sequence } if last_sequence.get()==1);
            let second_ok = typed_end
                && second.data.kind() == 2
                && second.data.sequence().get() == 2
                && second.bytes == (fact.len()..finish)
                && raw.get(second.bytes.clone()) == Some(end);
            (
                first_ok && second_ok && records.len() == 2 && raw.len() == finish,
                raw.len(),
                records.len(),
            )
        }
    }
}

async fn open_literal_channel(
    host: &BoundControlledUiHost,
    peers: &mut Vec<Peer>,
    end: Instant,
) -> Result<(u16, Option<String>), Error> {
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let launch = tokio::time::timeout_at(
        end.into(),
        client
            .get(host.launch_url())
            .header("Connection", "close")
            .send(),
    )
    .await??;
    if launch.status() != reqwest::StatusCode::SEE_OTHER {
        return Err(failure("launch exchange failed"));
    }
    let cookie = launch
        .headers()
        .get(reqwest::header::SET_COOKIE)
        .ok_or_else(|| failure("actual launch cookie missing"))?
        .to_str()?
        .split(';')
        .next()
        .ok_or_else(|| failure("actual launch cookie empty"))?
        .to_owned();
    drop(launch);
    let (status, bytes) = post(
        &client,
        host,
        Some(&cookie),
        host.base_url(),
        &host.address().to_string(),
        end,
    )
    .await?;
    if status != 200 {
        return Err(failure("actual bootstrap was not successful"));
    }
    let bootstrap: serde_json::Value = serde_json::from_slice(&bytes)?;
    let credential = bootstrap["credential"]
        .as_str()
        .ok_or_else(|| failure("actual credential missing"))?;
    let upgraded = upgrade(host, &cookie, host.base_url(), credential, end, peers).await?;
    drop(client);
    Ok(upgraded)
}

struct FrameObservation {
    upgrade: (u16, Option<String>),
    first_ack: Vec<u8>,
    first_cache: (bool, usize, usize),
    second_ack: Vec<u8>,
    second_cache: (bool, usize, usize),
    peer_close: Result<(), WsError>,
    channel_eof: bool,
}
async fn binary_reply(peer: &mut Peer, end: Instant) -> Result<Vec<u8>, Error> {
    match tokio::time::timeout_at(end.into(), peer.next()).await? {
        Some(Ok(PeerMessage::Binary(bytes))) => Ok(bytes.to_vec()),
        Some(Err(cause)) => Err(cause.into()),
        _ => Err(failure("actual retained record ACK was not binary")),
    }
}
async fn send_literals(
    peers: &mut [Peer],
    state: &Arc<HostState>,
    fact: &[u8],
    terminal: &[u8],
    upgraded: (u16, Option<String>),
    end: Instant,
) -> Result<FrameObservation, Error> {
    send_literals_with_tokens(peers, state, fact, terminal, br#""unit""#, upgraded, end).await
}
async fn send_literals_with_tokens(
    peers: &mut [Peer],
    state: &Arc<HostState>,
    fact: &[u8],
    terminal: &[u8],
    workspace_token: &[u8],
    upgraded: (u16, Option<String>),
    end: Instant,
) -> Result<FrameObservation, Error> {
    let peer = peers
        .first_mut()
        .ok_or_else(|| failure("actual document upgrade missing"))?;
    tokio::time::timeout_at(
        end.into(),
        peer.send(PeerMessage::Binary(fact.to_vec().into())),
    )
    .await??;
    let first_ack = binary_reply(peer, end).await?;
    let first_cache = retained_tokens_at_ack(state, fact, None, workspace_token);
    tokio::time::timeout_at(
        end.into(),
        peer.send(PeerMessage::Binary(terminal.to_vec().into())),
    )
    .await??;
    let second_ack = binary_reply(peer, end).await?;
    let second_cache = retained_tokens_at_ack(state, fact, Some(terminal), workspace_token);
    // A healthy END is still not physical channel EOF. Exercise the actual
    // close handshake and stream exhaustion while the collector is borrowed.
    let peer_close = tokio::time::timeout_at(end.into(), peer.close(None)).await?;
    let channel_eof = loop {
        match tokio::time::timeout_at(end.into(), peer.next()).await? {
            None => break true,
            Some(Ok(PeerMessage::Close(_))) => continue,
            Some(Err(WsError::ConnectionClosed | WsError::AlreadyClosed)) => break true,
            Some(Err(cause)) => return Err(cause.into()),
            Some(Ok(_)) => break false,
        }
    };
    Ok(FrameObservation {
        upgrade: upgraded,
        first_ack,
        first_cache,
        second_ack,
        second_cache,
        peer_close,
        channel_eof,
    })
}

#[test]
fn browser_document_ingress_02_literal_fact_and_end_retained_before_exact_ack_then_channel_drain() {
    assert_literal_journey(FACT_BODY, br#""unit""#);
}

#[test]
fn browser_document_ingress_typed_utf16_token_and_whitespace_survive_actual_journal_before_ack() {
    assert_literal_journey(b" \r\n {\"sequence\":1,\"kind\":\"model-closed\",\"actual\":{\"workspace\":\"w\\ud800\",\"opening\":0}} ", br#""w\ud800""#);
}

fn assert_literal_journey(body: &[u8], workspace_token: &[u8]) {
    // Literal source-free inputs test the codec/transport only. "unit" is not
    // a source observation or evidence that a physical product model closed.
    let fact = literal_frame(1, 1, body);
    let terminal_frame = literal_frame(2, 2, END_BODY);
    let expected_first_ack = literal_frame(3, 1, &[]);
    let expected_second_ack = literal_frame(3, 2, &[]);
    let runtime = runtime();
    let ((observed, collected, close_attempts, joined, unresolved), source_terminal) =
        with_stimulus(|stimulus, loans| {
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
                // Clone the actual state before borrowing the host/Decoder into
                // collection. The peer never receives a second owner or ledger.
                let actual_state = Arc::clone(&host.state);
                let setup = match host.start() {
                    Ok(()) => open_literal_channel(&host, &mut peers, end).await,
                    Err(_) => Err(failure("actual host start failed")),
                };
                let (observed, collected) = match setup {
                    Ok(upgraded) => {
                        let (observed, collected) = tokio::join!(
                            send_literals_with_tokens(
                                &mut peers,
                                &actual_state,
                                &fact,
                                &terminal_frame,
                                workspace_token,
                                upgraded,
                                end
                            ),
                            // Bound only this borrowed future by the SAME original
                            // end so a stalled collector cannot bypass cleanup.
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
                (observed, collected, close_attempts, joined, unresolved)
            })
        });
    let unresolved = unresolved.map(std::mem::ManuallyDrop::new);
    assert!(
        unresolved.is_none(),
        "same pending host retained after bounded cleanup retries"
    );
    assert_eq!(joined, ControlledHostShutdown::Joined);
    for actual in close_attempts {
        match actual {
            Ok(Ok(())) | Ok(Err(WsError::ConnectionClosed | WsError::AlreadyClosed)) => {}
            actual => panic!("actual peer cleanup failed: {actual:?}"),
        }
    }
    let observed = observed.unwrap();
    assert_eq!(
        observed.upgrade,
        (101, Some("morphir-document-v1".to_owned()))
    );
    assert_eq!(observed.first_ack, expected_first_ack);
    assert_eq!(observed.first_ack.len(), 16);
    assert_eq!(observed.first_cache, (true, fact.len(), 1));
    assert_eq!(observed.second_ack, expected_second_ack);
    assert_eq!(observed.second_ack.len(), 16);
    assert_eq!(
        observed.second_cache,
        (true, fact.len() + terminal_frame.len(), 2)
    );
    assert!(matches!(
        observed.peer_close,
        Ok(()) | Err(WsError::ConnectionClosed | WsError::AlreadyClosed)
    ));
    assert!(
        observed.channel_eof,
        "actual peer stream exhausted after the close handshake"
    );
    match collected {
        Some(Ok(DocumentCollectOutcome::Drained)) => {}
        Some(Err(cause)) => {
            panic!("borrowed document collector exceeded the original end: {cause}")
        }
        _ => panic!("borrowed document collector did not drain"),
    }
    assert!(
        matches!(source_terminal, BrowserSourceTerminal::Incomplete { .. }),
        "transport drain never fabricates logical source completion"
    );
}

#[path = "frames/negative.rs"]
mod negative;

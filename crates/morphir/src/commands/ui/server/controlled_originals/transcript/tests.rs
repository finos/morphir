//! Actual authenticated TCP journeys over genuine reviewed engine input.
//! Scripted clients test retained transport facts, not Workbench qualification.
use super::super::{
    BoundControlledUiHost, ControlledHostFinish, ControlledHostJoined,
    ingress::DocumentIngressLimits,
};
use crate::commands::ui::server::controlled_originals_tests::runtime;
use futures_util::{SinkExt as _, StreamExt as _};
use morphir_mck::workbench::{
    BrowserAdapterCompletion, BrowserDocumentBounds, BrowserHostFact, BrowserHostPeerFinish,
    BrowserHostSendOutcome, BrowserRowAttempt, BrowserSourceTerminal, RunConfiguration, load,
    with_executed_browser_originals,
};
use std::{
    cell::RefCell,
    time::{Duration, Instant},
};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};
type Error = Box<dyn std::error::Error + Send + Sync>;
type Peer = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;
#[derive(Clone, Copy, PartialEq, Eq)]
enum Journey {
    Complete,
    Mismatch,
    ResetAfterFirstReply,
}
struct Expected {
    status: u16,
    manifest: Vec<u8>,
    requests: Vec<String>,
    replies: Vec<String>,
}
struct Observed {
    status: u16,
    manifest: Vec<u8>,
    requests: Vec<String>,
    replies: Vec<String>,
    reset: bool,
}
fn failure(message: &str) -> Error {
    std::io::Error::other(message).into()
}
fn limits() -> DocumentIngressLimits {
    DocumentIngressLimits {
        observation_owners: 4,
        observation_events: 8,
        records: 2,
        journal_bytes: 4096,
        frame_bytes: 1024,
        socket_tasks: 6,
        request_tickets: 16,
        request_header_fields: 32,
        request_header_bytes: 1024,
    }
}
async fn peer_terminal(peer: &mut Peer, end: Instant) -> Result<(), Error> {
    loop {
        match tokio::time::timeout_at(end.into(), peer.next()).await? {
            None | Some(Err(_)) => return Ok(()),
            Some(Ok(Message::Close(_))) => continue,
            Some(Ok(_)) => {
                return Err(failure("unexpected reply after actual scripted peer ended"));
            }
        }
    }
}
async fn read_reply(peer: &mut Peer, end: Instant) -> Result<String, Error> {
    match tokio::time::timeout_at(end.into(), peer.next()).await? {
        Some(Ok(Message::Text(text))) => Ok(text.to_string()),
        Some(Err(cause)) => Err(cause.into()),
        _ => Err(failure("actual scripted reply was not text")),
    }
}
async fn client(
    host: &BoundControlledUiHost,
    expected: &Expected,
    journey: Journey,
    end: Instant,
) -> Result<Observed, Error> {
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()?;
    let response = tokio::time::timeout_at(
        end.into(),
        client
            .get(host.launch_url())
            .header("Connection", "close")
            .send(),
    )
    .await??;
    if response.status() != reqwest::StatusCode::SEE_OTHER {
        return Err(failure("actual launch refused"));
    }
    let cookie = response
        .headers()
        .get(reqwest::header::SET_COOKIE)
        .ok_or_else(|| failure("actual cookie missing"))?
        .to_str()?
        .split(';')
        .next()
        .ok_or_else(|| failure("actual cookie empty"))?
        .to_owned();
    drop(response);
    let manifest = tokio::time::timeout_at(
        end.into(),
        client
            .get(format!("{}/api/session", host.base_url()))
            .header("Cookie", &cookie)
            .header("Connection", "close")
            .send(),
    )
    .await??;
    let status = manifest.status().as_u16();
    let manifest = tokio::time::timeout_at(end.into(), manifest.bytes())
        .await??
        .to_vec();
    let mut request = format!("ws://{}/rpc", host.address()).into_client_request()?;
    request.headers_mut().insert("Cookie", cookie.parse()?);
    request
        .headers_mut()
        .insert("Origin", host.base_url().parse()?);
    request
        .headers_mut()
        .insert("Host", host.address().to_string().parse()?);
    let (mut peer, response) =
        tokio::time::timeout_at(end.into(), connect_async(request)).await??;
    if response.status().as_u16() != 101 {
        return Err(failure("actual RPC upgrade refused"));
    }
    let mut observed = Observed {
        status,
        manifest,
        requests: Vec::new(),
        replies: Vec::new(),
        reset: false,
    };
    for (index, source_request) in expected.requests.iter().enumerate() {
        let actual = if journey == Journey::Mismatch {
            let mut bytes = source_request.as_bytes().to_vec();
            if bytes.is_empty() {
                return Err(failure("reviewed request must be nonempty"));
            }
            bytes[0] = if bytes[0] == b'!' { b'?' } else { b'!' };
            String::from_utf8(bytes)?
        } else {
            source_request.clone()
        };
        tokio::time::timeout_at(end.into(), peer.send(Message::Text(actual.clone().into())))
            .await??;
        observed.requests.push(actual);
        if journey == Journey::Mismatch {
            peer_terminal(&mut peer, end).await?;
            return Ok(observed);
        }
        observed.replies.push(read_reply(&mut peer, end).await?);
        if journey == Journey::ResetAfterFirstReply {
            if index != 0 {
                return Err(failure(
                    "reset control changed its actual first-reply boundary",
                ));
            }
            match peer.get_ref() {
                MaybeTlsStream::Plain(tcp) => {
                    socket2::SockRef::from(tcp).set_linger(Some(Duration::ZERO))?
                }
                _ => return Err(failure("actual plain TCP required")),
            }
            drop(peer);
            observed.reset = true;
            return Ok(observed);
        }
    }
    // The peer's actual terminal read follows the native loop's completion.
    // It does not infer that a returned send meant client business acceptance.
    peer_terminal(&mut peer, end).await?;
    Ok(observed)
}
async fn finish(mut host: BoundControlledUiHost) -> ControlledHostFinish {
    for _ in 0..8 {
        match host.finish_joined().await {
            ControlledHostFinish::Retained { host: actual, .. } => {
                host = actual;
                tokio::task::yield_now().await;
            }
            actual => return actual,
        }
    }
    host.finish_joined().await
}
fn with_transcript(
    journey: Journey,
    inspect: impl FnOnce(&BrowserRowAttempt<&'static str>, &Expected, &Observed),
) {
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(
        directory.path().join("cases.json"),
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker:serde_json::Value=serde_json::from_slice(include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"),"/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
    let configuration=RunConfiguration::from_json(&serde_json::json!({"kind":"model-originals-browser","browser":"chromium","checker":checker,"receiving":{"retainedBytes":16777216,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":16777216,"records":1024}}).to_string()).unwrap();
    let corpus = load(directory.path()).unwrap();
    let runtime = runtime();
    let expected = RefCell::new(None);
    let observed = RefCell::new(None);
    let mut callbacks = 0;
    with_executed_browser_originals(
        &corpus,
        &configuration,
        BrowserDocumentBounds::new(2, 4096, 1024).unwrap(),
        |run, loans, producer| {
            callbacks += 1;
            let opening = run.openings(loans).unwrap().next().unwrap();
            let endpoint = producer.issue(run, &opening, loans).unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            let source = Expected {
                status: u16::try_from(stimulus.manifest_status()).unwrap(),
                manifest: stimulus.manifest_body().as_bytes().to_vec(),
                requests: stimulus.requests().unwrap().to_vec(),
                replies: stimulus.frames().to_vec(),
            };
            assert!(source.requests.len() > 1);
            assert_eq!(source.requests.len(), source.replies.len());
            let (actual, joined) = runtime.block_on(async {
                let end = Instant::now() + Duration::from_secs(20);
                let mut host = BoundControlledUiHost::bind_engine_document(
                    stimulus,
                    None,
                    loans,
                    limits(),
                    endpoint,
                    end,
                )
                .await
                .unwrap();
                let actual = match host.start() {
                    Ok(()) => client(&host, &source, journey, end).await,
                    Err(_) => Err(failure("actual host start failed")),
                };
                (actual, finish(host).await)
            });
            assert!(
                matches!(joined, ControlledHostFinish::Joined(_)),
                "actual host joins remain required before callback return"
            );
            if journey == Journey::Complete {
                assert!(matches!(
                    joined,
                    ControlledHostFinish::Joined(ControlledHostJoined::Clean)
                ));
            }
            expected.replace(Some(source));
            observed.replace(Some(actual.unwrap()));
            Err("actual adapter refusal after native transcript journey")
        },
        |inventory| {
            assert_eq!(inventory.rows().len(), 23);
            assert_eq!(inventory.first_failed_row(), Some(0));
            let attempt = inventory.rows()[0].attempt().unwrap();
            assert!(matches!(
                attempt.callback(),
                BrowserAdapterCompletion::Returned(Err(
                    "actual adapter refusal after native transcript journey"
                ))
            ));
            assert_eq!(attempt.child_terminal(), BrowserSourceTerminal::Quiescent);
            for row in &inventory.rows()[1..] {
                assert_eq!(row.not_attempted_after(), Some(0));
            }
            inspect(
                attempt,
                expected.borrow().as_ref().unwrap(),
                observed.borrow().as_ref().unwrap(),
            );
        },
    )
    .unwrap();
    assert_eq!(callbacks, 1);
}

#[test]
fn browser_host_transcript_native_01_actual_complete_transport_survives_callback_error() {
    with_transcript(Journey::Complete, |attempt, expected, observed| {
        assert_eq!(observed.status, expected.status);
        assert_eq!(observed.manifest, expected.manifest);
        assert_eq!(observed.requests, expected.requests);
        assert_eq!(observed.replies, expected.replies);
        assert!(!observed.reset);
        let document = attempt.collection().document(0).unwrap();
        let transcript = document
            .host_transcript()
            .expect("engine retains native transcript after callback Err");
        assert_eq!(transcript.pending(), 0);
        assert_eq!(transcript.first(), None);
        assert_eq!(transcript.event_count(), 4 + 3 * expected.requests.len());
        assert!(matches!(
            transcript.event(0).unwrap().fact(),
            BrowserHostFact::ManifestRequestReceived
        ));
        let manifest = transcript.event(1).unwrap();
        assert!(
            matches!(manifest.fact(),BrowserHostFact::ManifestResponsePrepared{status} if *status==expected.status)
        );
        assert_eq!(manifest.bytes(), Some(expected.manifest.as_slice()));
        assert!(matches!(
            transcript.event(2).unwrap().fact(),
            BrowserHostFact::AuthenticatedPeerOpened
        ));
        for index in 0..expected.requests.len() {
            let received = transcript.event(3 + 3 * index).unwrap();
            assert!(matches!(
                received.fact(),
                BrowserHostFact::TextRequestReceived
            ));
            assert_eq!(received.bytes(), Some(expected.requests[index].as_bytes()));
            let attempted = transcript.event(4 + 3 * index).unwrap();
            assert!(matches!(
                attempted.fact(),
                BrowserHostFact::ReplySendAttempted
            ));
            assert_eq!(attempted.bytes(), Some(expected.replies[index].as_bytes()));
            assert!(matches!(
                transcript.event(5 + 3 * index).unwrap().fact(),
                BrowserHostFact::ReplySendReturned {
                    outcome: BrowserHostSendOutcome::Returned
                }
            ));
        }
        assert!(matches!(
            transcript
                .event(transcript.event_count() - 1)
                .unwrap()
                .fact(),
            BrowserHostFact::PeerFinished {
                outcome: BrowserHostPeerFinish::ScriptFinished
            }
        ));
        assert_eq!(
            document.record_count(),
            0,
            "transport history must not manufacture product FACT/END frames"
        );
    });
}
#[test]
fn browser_host_transcript_native_02_actual_mismatched_text_is_retained_before_comparison() {
    with_transcript(Journey::Mismatch, |attempt, expected, observed| {
        assert_eq!(observed.status, expected.status);
        assert_eq!(observed.manifest, expected.manifest);
        assert_eq!(observed.requests.len(), 1);
        assert!(observed.replies.is_empty());
        assert_ne!(observed.requests[0], expected.requests[0]);
        assert_eq!(observed.requests[0].len(), expected.requests[0].len());
        let document = attempt.collection().document(0).unwrap();
        let transcript = document.host_transcript().unwrap();
        let actual = transcript.event(3).unwrap();
        assert!(matches!(
            actual.fact(),
            BrowserHostFact::TextRequestReceived
        ));
        assert_eq!(actual.bytes(), Some(observed.requests[0].as_bytes()));
        assert_eq!(transcript.pending(), 0);
        for index in 0..transcript.event_count() {
            assert!(!matches!(
                transcript.event(index).unwrap().fact(),
                BrowserHostFact::ReplySendAttempted | BrowserHostFact::ReplySendReturned { .. }
            ));
        }
        assert!(matches!(
            transcript
                .event(transcript.event_count() - 1)
                .unwrap()
                .fact(),
            BrowserHostFact::PeerFinished {
                outcome: BrowserHostPeerFinish::Failed
            }
        ));
    });
}
#[test]
fn browser_host_transcript_native_03_actual_socket_loss_preserves_partial_source_associated_history()
 {
    with_transcript(
        Journey::ResetAfterFirstReply,
        |attempt, expected, observed| {
            assert!(observed.reset);
            assert_eq!(observed.requests, expected.requests[..1]);
            assert_eq!(observed.replies, expected.replies[..1]);
            let document = attempt.collection().document(0).unwrap();
            let transcript = document.host_transcript().unwrap();
            assert!(transcript.event_count() >= 5);
            assert_eq!(transcript.pending(), 0);
            let mut received = 0;
            let mut attempted = 0;
            for index in 0..transcript.event_count() {
                let event = transcript.event(index).unwrap();
                match event.fact() {
                    BrowserHostFact::TextRequestReceived => {
                        received += 1;
                        assert_eq!(event.bytes(), Some(expected.requests[0].as_bytes()));
                    }
                    BrowserHostFact::ReplySendAttempted => {
                        attempted += 1;
                        assert_eq!(event.bytes(), Some(expected.replies[0].as_bytes()));
                    }
                    _ => {}
                }
            }
            assert_eq!(received, 1);
            assert_eq!(attempted, 1);
            // Receiving bytes at this client does not prove the native send future
            // returned before cancellation. Preserve its actual terminal outcome.
            assert!(!matches!(
                transcript
                    .event(transcript.event_count() - 1)
                    .unwrap()
                    .fact(),
                BrowserHostFact::PeerFinished {
                    outcome: BrowserHostPeerFinish::ScriptFinished
                }
            ));
            assert_eq!(document.record_count(), 0);
        },
    );
}

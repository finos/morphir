//! Genuine compiled engine rows and actual authenticated TCP transport.
//! Literal frames are DATA, not Workbench actions or Download qualification.
use super::{
    BoundControlledUiHost, ControlledHostFinish, ControlledHostJoined,
    ingress::{self, DocumentCollectOutcome, DocumentIngressFault, DocumentIngressLimits},
};
use crate::commands::ui::server::controlled_originals_tests::runtime;
use futures_util::{SinkExt as _, StreamExt as _};
use morphir_mck::workbench::{
    BrowserAdapterCompletion, BrowserDocumentBounds, BrowserDocumentContent,
    BrowserDocumentFactData, BrowserLoans, BrowserRowAttempt, BrowserSourceFault,
    BrowserSourceTerminal, Corpus, RunConfiguration, load, with_executed_browser_originals,
};
use std::{
    cell::RefCell,
    time::{Duration, Instant},
};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{Error as WsError, Message, client::IntoClientRequest as _},
};

type Error = Box<dyn std::error::Error + Send + Sync>;
type Peer = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;
type Collected = Result<DocumentCollectOutcome, tokio::time::error::Elapsed>;
const FACT_BODY: &[u8] = b" \r\n {\"sequence\":1,\"kind\":\"model-closed\",\"actual\":{\"workspace\":\"literal-\\ud800\",\"opening\":0}} ";
const END_BODY: &[u8] = br#"{"lastSequence":1,"observer":{"kind":"closed"}}"#;

fn failure(message: &str) -> Error {
    std::io::Error::other(message).into()
}
fn fixture() -> (tempfile::TempDir, Corpus, RunConfiguration) {
    let directory = tempfile::tempdir().unwrap();
    std::fs::write(
        directory.path().join("cases.json"),
        include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
        )),
    )
    .unwrap();
    let checker: serde_json::Value = serde_json::from_slice(include_bytes!(concat!(
        env!("CARGO_MANIFEST_DIR"), "/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
    ))).unwrap();
    // Exactly the existing canonical-engine fixture policy, not new defaults.
    let configuration = RunConfiguration::from_json(
        &serde_json::json!({
            "kind":"model-originals-browser", "browser":"chromium", "checker":checker,
            "receiving":{"retainedBytes":16777216,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,
            "snapshotReadBytes":0,"byteVisits":16777216,"records":1024}
        })
        .to_string(),
    )
    .unwrap();
    let corpus = load(directory.path()).unwrap();
    (directory, corpus, configuration)
}
fn bounds() -> BrowserDocumentBounds {
    BrowserDocumentBounds::new(2, 4096, 1024).unwrap()
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
fn frame(kind: u8, sequence: u64, body: &[u8]) -> Vec<u8> {
    let mut bytes = vec![0; 16];
    bytes[0] = 1;
    bytes[1] = kind;
    bytes[4..12].copy_from_slice(&sequence.to_be_bytes());
    bytes[12..16].copy_from_slice(&u32::try_from(body.len()).unwrap().to_be_bytes());
    bytes.extend_from_slice(body);
    bytes
}
async fn authenticated_peer(host: &BoundControlledUiHost, end: Instant) -> Result<Peer, Error> {
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
        return Err(failure("actual launch refused"));
    }
    let cookie = launch
        .headers()
        .get(reqwest::header::SET_COOKIE)
        .ok_or_else(|| failure("actual cookie missing"))?
        .to_str()?
        .split(';')
        .next()
        .ok_or_else(|| failure("actual cookie empty"))?
        .to_owned();
    drop(launch);
    let bootstrap = tokio::time::timeout_at(
        end.into(),
        client
            .post(format!("{}/_mck/document", host.base_url()))
            .header("Host", host.address().to_string())
            .header("Origin", host.base_url())
            .header("Cookie", &cookie)
            .header("Connection", "close")
            .body(Vec::<u8>::new())
            .send(),
    )
    .await??;
    if bootstrap.status() != reqwest::StatusCode::OK {
        return Err(failure("actual bootstrap refused"));
    }
    let bootstrap: serde_json::Value =
        serde_json::from_slice(&tokio::time::timeout_at(end.into(), bootstrap.bytes()).await??)?;
    let credential = bootstrap
        .get("credential")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| failure("actual document credential missing"))?;
    let mut request = format!("ws://{}/_mck/document", host.address()).into_client_request()?;
    request
        .headers_mut()
        .insert("Host", host.address().to_string().parse()?);
    request
        .headers_mut()
        .insert("Origin", host.base_url().parse()?);
    request.headers_mut().insert("Cookie", cookie.parse()?);
    request.headers_mut().insert(
        "Sec-WebSocket-Protocol",
        format!("morphir-document-v1, morphir-document-key.{credential}").parse()?,
    );
    let (peer, response) = tokio::time::timeout_at(end.into(), connect_async(request)).await??;
    if response.status().as_u16() != 101
        || response
            .headers()
            .get("Sec-WebSocket-Protocol")
            .and_then(|value| value.to_str().ok())
            != Some("morphir-document-v1")
    {
        drop(peer);
        return Err(failure("actual document upgrade differed"));
    }
    Ok(peer)
}
async fn binary(peer: &mut Peer, end: Instant) -> Result<Vec<u8>, Error> {
    match tokio::time::timeout_at(end.into(), peer.next()).await? {
        Some(Ok(Message::Binary(bytes))) => Ok(bytes.to_vec()),
        Some(Err(cause)) => Err(cause.into()),
        _ => Err(failure("actual binary ACK missing")),
    }
}
#[derive(Debug)]
struct PeerObservation {
    fact_ack: Option<Vec<u8>>,
    end_ack: Option<Vec<u8>>,
    drained: bool,
    reset_requested: bool,
}
async fn healthy_peer(mut peer: Peer, end: Instant) -> Result<PeerObservation, Error> {
    tokio::time::timeout_at(
        end.into(),
        peer.send(Message::Binary(frame(1, 1, FACT_BODY).into())),
    )
    .await??;
    let fact_ack = binary(&mut peer, end).await?;
    tokio::time::timeout_at(
        end.into(),
        peer.send(Message::Binary(frame(2, 2, END_BODY).into())),
    )
    .await??;
    let end_ack = binary(&mut peer, end).await?;
    match tokio::time::timeout_at(end.into(), peer.close(None)).await? {
        Ok(()) | Err(WsError::ConnectionClosed | WsError::AlreadyClosed) => {}
        Err(cause) => return Err(cause.into()),
    }
    let drained = loop {
        match tokio::time::timeout_at(end.into(), peer.next()).await? {
            None | Some(Err(WsError::ConnectionClosed | WsError::AlreadyClosed)) => break true,
            Some(Ok(Message::Close(_))) => continue,
            Some(Err(cause)) => return Err(cause.into()),
            Some(Ok(_)) => break false,
        }
    };
    Ok(PeerObservation {
        fact_ack: Some(fact_ack),
        end_ack: Some(end_ack),
        drained,
        reset_requested: false,
    })
}
async fn reset_after_actual_stage(
    mut peer: Peer,
    host: &BoundControlledUiHost,
    end: Instant,
) -> Result<PeerObservation, Error> {
    let actual = frame(1, 1, FACT_BODY);
    tokio::time::timeout_at(
        end.into(),
        peer.send(Message::Binary(actual.clone().into())),
    )
    .await??;
    ingress::await_staged_frame_for_test(host, &actual, end)
        .await
        .map_err(|_| failure("actual literal frame was not staged before reset"))?;
    match peer.get_ref() {
        MaybeTlsStream::Plain(tcp) => {
            socket2::SockRef::from(tcp).set_linger(Some(Duration::ZERO))?
        }
        _ => return Err(failure("literal control requires actual plain TCP")),
    }
    // No peer read occurs: no received ACK is fabricated. Actual reset/ACK
    // write ordering is left to the kernel and measured as a closed outcome.
    drop(peer);
    Ok(PeerObservation {
        fact_ack: None,
        end_ack: None,
        drained: false,
        reset_requested: true,
    })
}
async fn finish_native(mut host: BoundControlledUiHost) -> ControlledHostFinish {
    for _ in 0..8 {
        match host.finish_joined().await {
            ControlledHostFinish::Retained { host: actual, .. } => {
                host = actual;
                tokio::task::yield_now().await;
            }
            joined => return joined,
        }
    }
    host.finish_joined().await
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Scenario {
    Joined,
    Reset,
    HoldUntilInspection,
}
struct Observation {
    peer: Result<PeerObservation, Error>,
    collected: Option<Collected>,
    retry: Option<Collected>,
    finish: Option<ControlledHostFinish>,
    held: Option<BoundControlledUiHost>,
}
async fn exercise(
    mut host: BoundControlledUiHost,
    loans: &mut BrowserLoans<'_, '_>,
    end: Instant,
    scenario: Scenario,
) -> Observation {
    let setup = match host.start() {
        Ok(()) => authenticated_peer(&host, end).await,
        Err(_) => Err(failure("actual host start failed")),
    };
    let (peer, collected, retry) = match setup {
        Ok(actual) if scenario == Scenario::Reset => {
            let peer = reset_after_actual_stage(actual, &host, end).await;
            let first = tokio::time::timeout_at(end.into(), host.collect_document(loans)).await;
            let retry = tokio::time::timeout_at(end.into(), host.collect_document(loans)).await;
            (peer, Some(first), Some(retry))
        }
        Ok(actual) => {
            let (peer, collected) = tokio::join!(
                healthy_peer(actual, end),
                tokio::time::timeout_at(end.into(), host.collect_document(loans))
            );
            (peer, Some(collected), None)
        }
        Err(cause) => (Err(cause), None, None),
    };
    let (finish, held) = if scenario == Scenario::HoldUntilInspection {
        (None, Some(host))
    } else {
        (Some(finish_native(host).await), None)
    };
    Observation {
        peer,
        collected,
        retry,
        finish,
        held,
    }
}
fn assert_core_records(attempt: &BrowserRowAttempt<&'static str>, count: usize) {
    let document = attempt
        .collection()
        .document(0)
        .expect("engine retains its issued document after callback");
    assert_eq!(document.record_count(), count);
    let actual = document.record(0).unwrap();
    assert_eq!(actual.frame(), frame(1, 1, FACT_BODY));
    assert_eq!(actual.data().sequence().get(), 1);
    match actual.data().content() {
        BrowserDocumentContent::Fact(BrowserDocumentFactData::ModelClosed(owner)) => {
            assert_eq!(owner.opening().get(), 0);
            assert_eq!(
                actual.payload().get(owner.workspace().range()),
                Some(br#""literal-\ud800""#.as_slice())
            );
        }
        _ => panic!("retained actual literal FACT lost its closed typed content"),
    }
    if count == 2 {
        let terminal = document.record(1).unwrap();
        assert_eq!(terminal.frame(), frame(2, 2, END_BODY));
        assert_eq!(terminal.data().sequence().get(), 2);
        assert!(
            matches!(terminal.data().content(),BrowserDocumentContent::End{last_sequence} if last_sequence.get()==1)
        );
    }
}

#[test]
fn browser_engine_native_01_actual_authenticated_drain_and_join_preserve_core_records_after_callback_error()
 {
    let (_directory, corpus, configuration) = fixture();
    let runtime = runtime();
    let observation = RefCell::new(None);
    let mut callbacks = 0;
    with_executed_browser_originals(
        &corpus,
        &configuration,
        bounds(),
        |run, loans, producer| {
            callbacks += 1;
            let opening = run.openings(loans).unwrap().next().unwrap();
            let endpoint = producer.issue(run, &opening, loans).unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            observation.replace(Some(runtime.block_on(async {
                let end = Instant::now() + Duration::from_secs(20);
                let host = BoundControlledUiHost::bind_engine_document(
                    stimulus,
                    None,
                    loans,
                    limits(),
                    endpoint,
                    end,
                )
                .await
                .unwrap();
                exercise(host, loans, end, Scenario::Joined).await
            })));
            // Explicit refusal stops the remaining22 genuine rows, without claiming
            // any literal model-closed token satisfied the product's predicates.
            Err("actual callback refusal after native joins")
        },
        |inventory| {
            assert_eq!(inventory.rows().len(), 23);
            assert_eq!(inventory.first_failed_row(), Some(0));
            assert_eq!(
                inventory.rows()[0].case_id(),
                "connected-inventory-single-file-json-v3"
            );
            let attempt = inventory.rows()[0].attempt().unwrap();
            assert!(matches!(
                attempt.callback(),
                BrowserAdapterCompletion::Returned(Err(
                    "actual callback refusal after native joins"
                ))
            ));
            assert_eq!(attempt.child_terminal(), BrowserSourceTerminal::Quiescent);
            assert_eq!(
                inventory.source_terminal(),
                BrowserSourceTerminal::Quiescent
            );
            assert!(attempt.collection_complete());
            assert_core_records(attempt, 2);
            for row in &inventory.rows()[1..] {
                assert_eq!(row.not_attempted_after(), Some(0));
            }
        },
    )
    .unwrap();
    assert_eq!(callbacks, 1);
    let actual = observation.into_inner().unwrap();
    let peer = actual.peer.unwrap();
    assert_eq!(peer.fact_ack, Some(frame(3, 1, &[])));
    assert_eq!(peer.end_ack, Some(frame(3, 2, &[])));
    assert!(peer.drained && !peer.reset_requested);
    assert!(matches!(
        actual.collected,
        Some(Ok(DocumentCollectOutcome::Drained))
    ));
    assert!(matches!(
        actual.finish,
        Some(ControlledHostFinish::Joined(ControlledHostJoined::Clean))
    ));
    assert!(actual.held.is_none());
}

#[test]
fn browser_engine_native_02_actual_reset_before_ack_read_preserves_core_fact_and_first_fault() {
    let (_directory, corpus, configuration) = fixture();
    let runtime = runtime();
    let observation = RefCell::new(None);
    with_executed_browser_originals(
        &corpus,
        &configuration,
        bounds(),
        |run, loans, producer| {
            let opening = run.openings(loans).unwrap().next().unwrap();
            let endpoint = producer.issue(run, &opening, loans).unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            observation.replace(Some(runtime.block_on(async {
                let end = Instant::now() + Duration::from_secs(20);
                let host = BoundControlledUiHost::bind_engine_document(
                    stimulus,
                    None,
                    loans,
                    limits(),
                    endpoint,
                    end,
                )
                .await
                .unwrap();
                exercise(host, loans, end, Scenario::Reset).await
            })));
            Err("actual callback refusal after socket loss")
        },
        |inventory| {
            assert_eq!(inventory.rows().len(), 23);
            assert_eq!(inventory.first_failed_row(), Some(0));
            let attempt = inventory.rows()[0].attempt().unwrap();
            assert_core_records(attempt, 1);
            assert!(!attempt.collection_complete());
            assert_eq!(attempt.child_terminal(), BrowserSourceTerminal::Quiescent);
            assert!(matches!(
                attempt.callback(),
                BrowserAdapterCompletion::Returned(Err(
                    "actual callback refusal after socket loss"
                ))
            ));
            for row in &inventory.rows()[1..] {
                assert_eq!(row.not_attempted_after(), Some(0));
            }
        },
    )
    .unwrap();
    let actual = observation.into_inner().unwrap();
    let peer = actual.peer.unwrap();
    assert!(peer.reset_requested && !peer.drained);
    assert_eq!(peer.fact_ack, None);
    assert_eq!(peer.end_ack, None);
    let first = match actual.collected {
        Some(Ok(DocumentCollectOutcome::Incomplete(cause))) => cause,
        _ => panic!("actual reset must not become successful END/drain"),
    };
    // Same actual kernel-dependent family as the existing staged-reset control.
    assert!(matches!(
        first,
        DocumentIngressFault::LostAck
            | DocumentIngressFault::PeerRead
            | DocumentIngressFault::ProducerIncomplete
    ));
    assert!(
        matches!(actual.retry,Some(Ok(DocumentCollectOutcome::Incomplete(cause))) if cause==first)
    );
    assert!(matches!(
        actual.finish,
        Some(ControlledHostFinish::Joined(_))
    ));
    assert!(actual.held.is_none());
}

#[test]
fn browser_engine_native_03_callback_error_retains_actual_debt_until_consuming_join_without_rewriting_inventory()
 {
    let (_directory, corpus, configuration) = fixture();
    let runtime = runtime();
    let observation = RefCell::new(None);
    with_executed_browser_originals(
        &corpus,
        &configuration,
        bounds(),
        |run, loans, producer| {
            let opening = run.openings(loans).unwrap().next().unwrap();
            let endpoint = producer.issue(run, &opening, loans).unwrap();
            let stimulus = run.prepare_controlled_host(&opening, loans).unwrap();
            observation.replace(Some(runtime.block_on(async {
                let end = Instant::now() + Duration::from_secs(20);
                let host = BoundControlledUiHost::bind_engine_document(
                    stimulus,
                    None,
                    loans,
                    limits(),
                    endpoint,
                    end,
                )
                .await
                .unwrap();
                exercise(host, loans, end, Scenario::HoldUntilInspection).await
            })));
            Err("actual callback refusal before listener join")
        },
        |inventory| {
            assert_eq!(inventory.rows().len(), 23);
            assert_eq!(inventory.first_failed_row(), Some(0));
            let attempt = inventory.rows()[0].attempt().unwrap();
            assert_core_records(attempt, 2);
            assert!(attempt.collection_complete());
            assert!(matches!(
                attempt.callback(),
                BrowserAdapterCompletion::Returned(Err(
                    "actual callback refusal before listener join"
                ))
            ));
            assert_eq!(
                attempt.child_terminal(),
                BrowserSourceTerminal::Unfinished { bindings: 1 }
            );
            assert_eq!(
                inventory.source_terminal(),
                BrowserSourceTerminal::Unfinished { bindings: 1 }
            );
            let mut observation = observation.borrow_mut();
            let actual = observation.as_mut().unwrap();
            assert!(actual.peer.as_ref().unwrap().drained);
            assert!(matches!(
                actual.collected,
                Some(Ok(DocumentCollectOutcome::Drained))
            ));
            let host = actual
                .held
                .take()
                .expect("same actual host retained past callback Err");
            assert_eq!(host.state.source.admit(), Err(BrowserSourceFault::Revoked));
            actual.finish = Some(runtime.block_on(finish_native(host)));
            assert!(matches!(
                actual.finish,
                Some(ControlledHostFinish::Joined(_))
            ));
            // Later actual cleanup does not retroactively erase the captured debt
            // or the original adapter error, and it must not erase the raw cache.
            assert_eq!(
                attempt.child_terminal(),
                BrowserSourceTerminal::Unfinished { bindings: 1 }
            );
            assert_eq!(
                inventory.source_terminal(),
                BrowserSourceTerminal::Unfinished { bindings: 1 }
            );
            assert_core_records(attempt, 2);
            for row in &inventory.rows()[1..] {
                assert_eq!(row.not_attempted_after(), Some(0));
            }
        },
    )
    .unwrap();
    assert!(observation.into_inner().unwrap().held.is_none());
}

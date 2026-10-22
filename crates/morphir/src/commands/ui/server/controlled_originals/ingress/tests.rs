//! Proposed child of controlled_originals::ingress. Actual transport only.
//! No browser/Page, producer fact, ACK, Download or qualification evidence.
use super::DocumentIngressLimits;
use crate::commands::ui::server::{
    controlled_originals::{BoundControlledUiHost, ControlledHostShutdown},
    controlled_originals_tests::{runtime, with_stimulus},
};
use morphir_mck::workbench::BrowserSourceTerminal;
use std::time::{Duration, Instant};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{Error as WsError, client::IntoClientRequest as _},
};

type Error = Box<dyn std::error::Error + Send + Sync>;
type Peer = WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>;
const OWNERS: usize = 4;
const EVENTS: usize = 8;
const RECORDS: usize = 4; // Total FACT + END descriptors. No hidden +1.
const JOURNAL: usize = 8192;
const FRAME: usize = 1024;

fn failure(message: &str) -> Error {
    std::io::Error::other(message).into()
}

async fn post(
    client: &reqwest::Client,
    host: &BoundControlledUiHost,
    cookie: Option<&str>,
    origin: &str,
    authority: &str,
    end: Instant,
) -> Result<(u16, Vec<u8>), Error> {
    let mut request = client
        .post(format!("{}/_mck/document", host.base_url()))
        .header("Host", authority)
        .header("Origin", origin)
        .header("Connection", "close")
        .body(Vec::<u8>::new());
    if let Some(cookie) = cookie {
        request = request.header("Cookie", cookie);
    }
    let response = tokio::time::timeout_at(end.into(), request.send()).await??;
    let status = response.status().as_u16();
    let bytes = tokio::time::timeout_at(end.into(), response.bytes()).await??;
    Ok((status, bytes.to_vec()))
}

async fn upgrade(
    host: &BoundControlledUiHost,
    cookie: &str,
    origin: &str,
    credential: &str,
    end: Instant,
    peers: &mut Vec<Peer>,
) -> Result<(u16, Option<String>), Error> {
    let mut request = format!("ws://{}/_mck/document", host.address()).into_client_request()?;
    request
        .headers_mut()
        .insert("Host", host.address().to_string().parse()?);
    request.headers_mut().insert("Cookie", cookie.parse()?);
    request.headers_mut().insert("Origin", origin.parse()?);
    request.headers_mut().insert(
        "Sec-WebSocket-Protocol",
        format!("morphir-document-v1, morphir-document-key.{credential}").parse()?,
    );
    match tokio::time::timeout_at(end.into(), connect_async(request)).await? {
        Ok((peer, response)) => {
            // Retain even an unexpectedly accepted peer for actual cleanup.
            peers.push(peer);
            let protocol = response
                .headers()
                .get("Sec-WebSocket-Protocol")
                .map(|value| value.to_str().map(str::to_owned))
                .transpose()?;
            Ok((response.status().as_u16(), protocol))
        }
        Err(WsError::Http(response)) => Ok((response.status().as_u16(), None)),
        Err(cause) => Err(cause.into()),
    }
}

struct Observed {
    unauthenticated: u16,
    foreign_origin: u16,
    foreign_host: u16,
    bootstrap_status: u16,
    bootstrap: serde_json::Value,
    duplicate_bootstrap: u16,
    wrong_cookie: u16,
    wrong_origin: u16,
    wrong_credential: u16,
    accepted: (u16, Option<String>),
    duplicate_upgrade: u16,
    template: u16,
}

// Any ? here returns only an observation error to the test's cleanup block.
// Actual accepted peers stay in the caller's Vec through every error branch.
async fn observe(
    host: &BoundControlledUiHost,
    peers: &mut Vec<Peer>,
    end: Instant,
) -> Result<Observed, Error> {
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
    if launch
        .headers()
        .get(reqwest::header::LOCATION)
        .and_then(|v| v.to_str().ok())
        != Some("/")
    {
        return Err(failure("document-only launch destination changed"));
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
    let authority = host.address().to_string();
    let unauthenticated = post(&client, host, None, host.base_url(), &authority, end)
        .await?
        .0;
    let foreign_origin = post(
        &client,
        host,
        Some(&cookie),
        "http://foreign.invalid",
        &authority,
        end,
    )
    .await?
    .0;
    let foreign_host = post(
        &client,
        host,
        Some(&cookie),
        host.base_url(),
        "foreign.invalid",
        end,
    )
    .await?
    .0;
    let (bootstrap_status, bytes) = post(
        &client,
        host,
        Some(&cookie),
        host.base_url(),
        &authority,
        end,
    )
    .await?;
    let bootstrap: serde_json::Value = serde_json::from_slice(&bytes)?;
    let credential = bootstrap
        .get("credential")
        .and_then(serde_json::Value::as_str)
        .ok_or_else(|| failure("actual bootstrap credential missing"))?;
    let duplicate_bootstrap = post(
        &client,
        host,
        Some(&cookie),
        host.base_url(),
        &authority,
        end,
    )
    .await?
    .0;
    let wrong_cookie = upgrade(
        host,
        "foreign-session=invalid",
        host.base_url(),
        credential,
        end,
        peers,
    )
    .await?
    .0;
    let wrong_origin = upgrade(
        host,
        &cookie,
        "http://foreign.invalid",
        credential,
        end,
        peers,
    )
    .await?
    .0;
    let mut wrong_credential = credential.as_bytes().to_vec();
    let first = wrong_credential
        .first_mut()
        .ok_or_else(|| failure("actual credential empty"))?;
    *first = if *first == b'A' { b'B' } else { b'A' };
    let wrong_credential = std::str::from_utf8(&wrong_credential)?;
    let wrong_credential = upgrade(host, &cookie, host.base_url(), wrong_credential, end, peers)
        .await?
        .0;
    let accepted = upgrade(host, &cookie, host.base_url(), credential, end, peers).await?;
    let duplicate_upgrade = upgrade(host, &cookie, host.base_url(), credential, end, peers)
        .await?
        .0;
    let template = tokio::time::timeout_at(
        end.into(),
        client
            .get(format!("{}/observed/index.html", host.base_url()))
            .header("Cookie", &cookie)
            .header("Connection", "close")
            .send(),
    )
    .await??;
    let template_status = template.status().as_u16();
    let _body = tokio::time::timeout_at(end.into(), template.bytes()).await??;
    drop(client);
    Ok(Observed {
        unauthenticated,
        foreign_origin,
        foreign_host,
        bootstrap_status,
        bootstrap,
        duplicate_bootstrap,
        wrong_cookie,
        wrong_origin,
        wrong_credential,
        accepted,
        duplicate_upgrade,
        template: template_status,
    })
}

#[test]
fn browser_document_ingress_01_actual_authenticated_bootstrap_and_upgrade_are_one_use() {
    let runtime = runtime();
    let ((observed, close_attempts, joined, unresolved), terminal) =
        with_stimulus(|stimulus, loans| {
            runtime.block_on(async {
                let end = Instant::now() + Duration::from_secs(20);
                let limits = DocumentIngressLimits {
                    observation_owners: OWNERS,
                    observation_events: EVENTS,
                    records: RECORDS,
                    journal_bytes: JOURNAL,
                    frame_bytes: FRAME,
                    // Explicit component test INPUT for a retained channel and
                    // subsequent refusal driver. Ordinary bind's two is unchanged.
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
                // No assertion or escaping ?/unwrap after the actual host exists.
                let started = host.start();
                let observed = match started {
                    Ok(()) => observe(&host, &mut peers, end).await,
                    Err(_) => Err(failure("actual host start failed")),
                };
                let mut close_attempts = Vec::new();
                for mut peer in peers {
                    // Retain the actual peer close result, including inner IO
                    // failure. Finishing the timeout is not successful close.
                    close_attempts
                        .push(tokio::time::timeout_at(end.into(), peer.close(None)).await);
                    drop(peer);
                }
                let mut joined = host.shutdown().await;
                // Observe the SAME concrete owner's cleanup after bounded executor
                // progress. Keep the original end; no new business/cleanup window.
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
                (observed, close_attempts, joined, unresolved)
            })
        });
    // Failure-only retention of the actual unresolved host. Never substitute
    // Drop/abort for a join or release this owner while reporting Pending.
    let unresolved = unresolved.map(std::mem::ManuallyDrop::new);
    assert!(
        unresolved.is_none(),
        "same host cleanup stayed Pending after eight bounded yields; actual owner retained"
    );
    assert!(
        matches!(
            joined,
            ControlledHostShutdown::Joined | ControlledHostShutdown::JoinedWithFault(_)
        ),
        "actual listener/driver/upgrade owners must finish; no END means no healthy transport claim"
    );
    for actual in close_attempts {
        match actual {
            Ok(Ok(())) | Ok(Err(WsError::ConnectionClosed | WsError::AlreadyClosed)) => {}
            actual => panic!("actual peer close failed: {actual:?}"),
        }
    }
    let observed = observed.unwrap();
    assert_eq!(observed.unauthenticated, 401);
    assert_eq!(observed.foreign_origin, 403);
    assert_eq!(observed.foreign_host, 403);
    assert_eq!(observed.bootstrap_status, 200);
    let bootstrap = &observed.bootstrap;
    assert_eq!(
        bootstrap["observation"]["owners"].as_u64(),
        Some(OWNERS as u64)
    );
    assert_eq!(
        bootstrap["observation"]["events"].as_u64(),
        Some(EVENTS as u64)
    );
    assert_eq!(bootstrap["records"].as_u64(), Some(RECORDS as u64));
    assert_eq!(bootstrap["journalBytes"].as_u64(), Some(JOURNAL as u64));
    assert_eq!(bootstrap["frameBytes"].as_u64(), Some(FRAME as u64));
    // Exact charge values are a separate layout gate. Here require the named
    // unsigned fields and no underclaim of the declared journal/descriptors.
    let charge = &bootstrap["journalCharge"];
    assert!(
        charge["retainedBytes"]
            .as_u64()
            .is_some_and(|n| n >= JOURNAL as u64)
    );
    assert!(
        charge["slots"]
            .as_u64()
            .is_some_and(|n| n >= RECORDS as u64)
    );
    assert!(
        charge["byteVisits"]
            .as_u64()
            .is_some_and(|n| n >= JOURNAL as u64)
    );
    let credential = bootstrap["credential"].as_str().unwrap();
    assert_eq!(credential.len(), 43);
    assert!(
        credential
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
    );
    assert_eq!(observed.duplicate_bootstrap, 409);
    assert_eq!(observed.wrong_cookie, 401);
    assert_eq!(observed.wrong_origin, 403);
    assert_eq!(observed.wrong_credential, 403);
    assert_eq!(
        observed.accepted,
        (101, Some("morphir-document-v1".to_owned()))
    );
    assert_eq!(observed.duplicate_upgrade, 409);
    assert_eq!(observed.template, 503);
    assert!(
        matches!(terminal, BrowserSourceTerminal::Incomplete { .. }),
        "raw source debt is not retired by peer close or physical component joins"
    );
}

#[path = "tests/frames.rs"]
mod frames;

#[path = "tests/limits.rs"]
mod limits;

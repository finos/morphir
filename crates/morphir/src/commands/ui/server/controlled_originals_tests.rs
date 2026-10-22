//! Genuine HTTP/auth/upgrade/script IO and real owner joins. Scripted bytes
//! are compiled fixture INPUT, not a server implementation or browser verdict.
use super::controlled_originals::{
    BoundControlledUiHost, ControlledHostFault, ControlledHostShutdown,
};
use super::*;
use futures_util::{SinkExt as _, StreamExt as _};
use morphir_mck::workbench::{
    BrowserActionKind, BrowserInputError, BrowserLoans, BrowserSourceTerminal,
    ControlledHostStimulus, RunConfiguration, load, with_prepared_browser_clients,
};
use std::time::{Duration, Instant};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};
type Error = Box<dyn std::error::Error + Send + Sync>;

pub(super) fn with_stimulus<R>(
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
    let checker:serde_json::Value=serde_json::from_str(include_str!(concat!(env!("CARGO_MANIFEST_DIR"),"/../morphir-mck/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"))).unwrap();
    let configuration=RunConfiguration::from_json(&serde_json::json!({"kind":"model-originals-browser","browser":"chromium","checker":checker,"receiving":{"retainedBytes":8388608,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,"snapshotReadBytes":0,"byteVisits":8388608,"records":0}}).to_string()).unwrap();
    let source = load(root.path()).unwrap();
    let mut run = Some(run);
    let mut actual = None;
    let outcome = with_prepared_browser_clients(&source, &configuration, |clients, loans| {
        clients.visit(loans, |client, loans| {
            if run.is_none() {
                return Ok(());
            }
            let opening = client.actions(loans)?.find(|action| {
                matches!(
                    action.kind(),
                    BrowserActionKind::BeginConnectedOpening { .. }
                )
            });
            if let Some(opening) = opening {
                let stimulus = client.prepare_controlled_host(loans, opening.position())?;
                actual = Some(run.take().unwrap()(stimulus, loans));
            }
            Ok::<_, BrowserInputError>(())
        })?;
        Ok::<_, BrowserInputError>(())
    })
    .unwrap();
    let (result, terminal) = outcome.into_parts();
    result.unwrap();
    (
        actual.expect("one real compiled controlled opening is required"),
        terminal,
    )
}
pub(super) fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .unwrap()
}
async fn cookie(
    client: &reqwest::Client,
    host: &BoundControlledUiHost,
    end: Instant,
) -> Result<String, Error> {
    let response = tokio::time::timeout_at(
        end.into(),
        client
            .get(host.launch_url())
            .header("Connection", "close")
            .send(),
    )
    .await??;
    if response.status() != reqwest::StatusCode::SEE_OTHER {
        return Err(std::io::Error::other("actual launch exchange failed").into());
    }
    Ok(response
        .headers()
        .get(reqwest::header::SET_COOKIE)
        .ok_or_else(|| std::io::Error::other("actual cookie missing"))?
        .to_str()?
        .split(';')
        .next()
        .unwrap()
        .to_owned())
}
async fn socket(
    host: &BoundControlledUiHost,
    cookie: &str,
    end: Instant,
) -> Result<
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
    Error,
> {
    let mut request = format!("ws://{}/rpc", host.address()).into_client_request()?;
    request.headers_mut().insert("Cookie", cookie.parse()?);
    request
        .headers_mut()
        .insert("Origin", host.base_url().parse()?);
    Ok(tokio::time::timeout_at(end.into(), connect_async(request))
        .await??
        .0)
}

#[test]
fn browser_controlled_host_01_actual_auth_manifest_origin_and_selected_literal_peer() {
    let runtime = runtime();
    let ((observed, joined), terminal) = with_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(10);
            let expected_status = stimulus.manifest_status();
            let expected_body = stimulus.manifest_body().to_owned();
            let requests = stimulus
                .requests()
                .expect("actual source has request table")
                .to_vec();
            let replies = stimulus.frames().to_vec();
            let mut host = BoundControlledUiHost::bind(stimulus, loans, end)
                .await
                .unwrap();
            let started = host.start();
            let observed = async {
                started.map_err(|_| std::io::Error::other("actual host start failed"))?;
                let client = reqwest::Client::builder()
                    .redirect(reqwest::redirect::Policy::none())
                    .build()?;
                let unauthorized = tokio::time::timeout_at(
                    end.into(),
                    client
                        .get(format!("{}/api/session", host.base_url()))
                        .header("Connection", "close")
                        .send(),
                )
                .await??
                .status();
                let cookie = cookie(&client, &host, end).await?;
                let manifest = tokio::time::timeout_at(
                    end.into(),
                    client
                        .get(format!("{}/api/session", host.base_url()))
                        .header("Cookie", &cookie)
                        .header("Connection", "close")
                        .send(),
                )
                .await??;
                let status = manifest.status();
                let body = tokio::time::timeout_at(end.into(), manifest.text()).await??;
                let mut wrong = format!("ws://{}/rpc", host.address()).into_client_request()?;
                wrong.headers_mut().insert("Cookie", cookie.parse()?);
                wrong
                    .headers_mut()
                    .insert("Origin", "http://foreign.invalid".parse()?);
                let wrong = tokio::time::timeout_at(end.into(), connect_async(wrong)).await?;
                let wrong_status = match wrong {
                    Err(tokio_tungstenite::tungstenite::Error::Http(response)) => {
                        Some(response.status().as_u16())
                    }
                    _ => None,
                };
                let mut actual = socket(&host, &cookie, end).await?;
                let mut frames = Vec::new();
                for request in requests {
                    tokio::time::timeout_at(end.into(), actual.send(Message::Text(request.into())))
                        .await??;
                    let reply = tokio::time::timeout_at(end.into(), actual.next())
                        .await?
                        .ok_or_else(|| std::io::Error::other("actual peer ended before reply"))??;
                    let Message::Text(text) = reply else {
                        return Err::<_, Error>(
                            std::io::Error::other("actual reply was not text").into(),
                        );
                    };
                    frames.push(text.to_string());
                }
                drop(actual);
                Ok::<_, Error>((unauthorized, status, body, wrong_status, frames))
            }
            .await;
            let joined = host.shutdown().await;
            drop(host);
            ((observed, expected_status, expected_body, replies), joined)
        })
    });
    let (observed, expected_status, expected_body, replies) = observed;
    assert_eq!(joined, ControlledHostShutdown::Joined);
    let (unauthorized, status, body, wrong_origin, frames) = observed.unwrap();
    assert_eq!(unauthorized, reqwest::StatusCode::UNAUTHORIZED);
    assert_eq!(u64::from(status.as_u16()), expected_status);
    assert_eq!(body, expected_body);
    assert_eq!(wrong_origin, Some(403));
    assert_eq!(frames, replies);
    assert!(
        matches!(terminal, BrowserSourceTerminal::Incomplete { .. }),
        "raw binding Drop is not a fabricated source cleanup receipt"
    );
}

#[test]
fn browser_controlled_host_02_callback_return_revokes_actual_host_admission_and_retains_owner() {
    let runtime = runtime();
    let ((mut host, connection, end), terminal) = with_stimulus(|stimulus, loans| {
        runtime.block_on(async {
            let end = Instant::now() + Duration::from_secs(10);
            let mut host = BoundControlledUiHost::bind(stimulus, loans, end)
                .await
                .unwrap();
            let started = host.start();
            let connection = async {
                started.map_err(|_| std::io::Error::other("actual host start failed"))?;
                let client = reqwest::Client::builder()
                    .redirect(reqwest::redirect::Policy::none())
                    .build()?;
                let cookie = cookie(&client, &host, end).await?;
                let mut actual = tokio::time::timeout_at(
                    end.into(),
                    tokio::net::TcpStream::connect(host.address()),
                )
                .await??;
                let identity = (actual.local_addr()?, actual.peer_addr()?);
                let status = retained_http(&mut actual, host.address(), &cookie, end).await?;
                Ok::<_, Error>((actual, identity, cookie, status))
            }
            .await;
            (host, connection, end)
        })
    });
    let actual = runtime.block_on(async {
        let observed = async {
            let (mut connection, identity, cookie, prior) = connection?;
            let status = retained_http(&mut connection, host.address(), &cookie, end).await?;
            let after = (connection.local_addr()?, connection.peer_addr()?);
            drop(connection);
            let new = tokio::time::timeout_at(
                end.into(),
                reqwest::Client::new()
                    .get(format!("{}/api/session", host.base_url()))
                    .header("Cookie", cookie)
                    .header("Connection", "close")
                    .send(),
            )
            .await?;
            Ok::<_, Error>((prior, status, identity, after, new.is_err()))
        }
        .await;
        let joined = host.shutdown().await;
        (observed, joined)
    });
    drop(host);
    assert!(Instant::now() < end);
    assert!(matches!(
        terminal,
        BrowserSourceTerminal::Unfinished { bindings: 1 }
    ));
    assert_eq!(actual.1, ControlledHostShutdown::Joined);
    let (prior, status, before, after, new_refused) = actual.0.unwrap();
    assert_eq!(prior, 200);
    assert_eq!(status, 503);
    assert_eq!(
        before, after,
        "the exact retained TCP connection was reused, not pooled-client inference"
    );
    assert!(
        new_refused,
        "a new source-revoked driver must not be admitted"
    );
}

async fn retained_http(
    actual: &mut tokio::net::TcpStream,
    address: SocketAddr,
    cookie: &str,
    end: Instant,
) -> Result<u16, Error> {
    use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};
    let request =
        format!("GET /api/session HTTP/1.1\r\nHost: {address}\r\nCookie: {cookie}\r\n\r\n");
    tokio::time::timeout_at(end.into(), actual.write_all(request.as_bytes())).await??;
    let mut header = Vec::new();
    while !header.ends_with(b"\r\n\r\n") {
        if header.len() >= 8192 {
            return Err(std::io::Error::other("bounded actual HTTP header exceeded").into());
        }
        let byte = tokio::time::timeout_at(end.into(), actual.read_u8()).await??;
        header.push(byte);
    }
    let header = std::str::from_utf8(&header)?;
    let status = header
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .ok_or_else(|| std::io::Error::other("actual status missing"))?
        .parse()?;
    let length = header
        .lines()
        .find_map(|line| {
            line.split_once(':')
                .filter(|(name, _)| name.eq_ignore_ascii_case("content-length"))
                .map(|(_, value)| value.trim().parse::<usize>())
        })
        .transpose()?
        .ok_or_else(|| std::io::Error::other("actual finite response size missing"))?;
    if length > 1024 * 1024 {
        return Err(std::io::Error::other("bounded actual response exceeded").into());
    }
    let mut body = vec![0; length];
    tokio::time::timeout_at(end.into(), actual.read_exact(&mut body)).await??;
    Ok(status)
}

#[test]
fn browser_controlled_host_03_foreign_session_source_and_project_actual_requests_refuse() {
    let runtime = runtime();
    for (method, path) in [
        ("morphir.session.initialize", "/params/sessionId"),
        ("morphir.model-originals.capture", "/params/source/locator"),
        ("morphir.model-originals.capture", "/params/projectId"),
    ] {
        let ((observed, joined), terminal) = with_stimulus(|stimulus, loans| {
            runtime.block_on(async {
                let end = Instant::now() + Duration::from_secs(10);
                let requests = stimulus.requests().unwrap().to_vec();
                let (index, old) = requests
                    .iter()
                    .enumerate()
                    .find_map(|(index, request)| {
                        let parsed: serde_json::Value = serde_json::from_str(request).unwrap();
                        (parsed["method"] == method).then(|| {
                            (
                                index,
                                parsed.pointer(path).unwrap().as_str().unwrap().to_owned(),
                            )
                        })
                    })
                    .expect("the exact source request/field is required");
                let old_token = serde_json::to_string(&old).unwrap();
                let new_token = serde_json::to_string(&(old.clone() + "-foreign")).unwrap();
                assert_eq!(
                    requests[index].matches(&old_token).count(),
                    1,
                    "mutation must isolate one actual source field"
                );
                let changed = requests[index].replacen(&old_token, &new_token, 1);
                let mut before: serde_json::Value = serde_json::from_str(&requests[index]).unwrap();
                let after: serde_json::Value = serde_json::from_str(&changed).unwrap();
                *before.pointer_mut(path).unwrap() = (old + "-foreign").into();
                assert_eq!(
                    before, after,
                    "all unrelated request nodes preserved before effects"
                );
                let mut host = BoundControlledUiHost::bind(stimulus, loans, end)
                    .await
                    .unwrap();
                let started = host.start();
                let observed = async {
                    started.map_err(|_| std::io::Error::other("actual host start failed"))?;
                    let client = reqwest::Client::builder()
                        .redirect(reqwest::redirect::Policy::none())
                        .build()?;
                    let cookie = cookie(&client, &host, end).await?;
                    let mut actual = socket(&host, &cookie, end).await?;
                    for request in &requests[..index] {
                        tokio::time::timeout_at(
                            end.into(),
                            actual.send(Message::Text(request.clone().into())),
                        )
                        .await??;
                        let _reply = tokio::time::timeout_at(end.into(), actual.next())
                            .await?
                            .ok_or_else(|| {
                            std::io::Error::other("peer ended before selected mismatch")
                        })??;
                    }
                    tokio::time::timeout_at(end.into(), actual.send(Message::Text(changed.into())))
                        .await??;
                    let next = tokio::time::timeout_at(end.into(), actual.next()).await?;
                    let refused = !matches!(next, Some(Ok(Message::Text(_))));
                    drop(actual);
                    Ok::<_, Error>(refused)
                }
                .await;
                let joined = host.shutdown().await;
                drop(host);
                (observed, joined)
            })
        });
        assert_eq!(
            joined,
            ControlledHostShutdown::JoinedWithFault(ControlledHostFault::PeerRequest)
        );
        assert!(observed.unwrap());
        assert!(matches!(terminal, BrowserSourceTerminal::Incomplete { .. }));
    }
}

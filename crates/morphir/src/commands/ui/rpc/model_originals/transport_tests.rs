//! Real loopback socket boundaries, not full producer/platform qualification.
//! The native provider resolves an independently authored compile fixture. The
//! exclusive compiler lock is real; no UI state or capture outcome is injected.

use crate::commands::ui::{
    model_originals::{ModelCaptureUsage, ModelCaptureUsageObserver},
    provider::{
        SessionCapabilities, WorkspaceCapability, WorkspaceSessionControl,
        native::NativeWorkspaceProvider, originals::OriginalsProvider,
    },
    server::BoundUiHost,
};
use futures_util::{SinkExt as _, StreamExt as _};
use morphir_devkit::ConfigLoadOptions;
use serde_json::{Value, json};
use std::{
    fs,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::net::{TcpSocket, TcpStream};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};

const VERSION: &str = "0.1.0-draft.1";
const WAIT: Duration = Duration::from_secs(10);
type Socket = WebSocketStream<MaybeTlsStream<TcpStream>>;

struct Fixture {
    _directory: tempfile::TempDir,
    worker: Option<tokio::task::JoinHandle<Result<(), crate::error::CliError>>>,
    socket_cleanup: crate::commands::ui::socket_tasks::SocketCleanup,
    observer: ModelCaptureUsageObserver,
    workspace: WorkspaceSessionControl,
    lock: fs::File,
    source: Value,
    project: String,
    base: String,
    cookie: String,
    send_buffer: Option<usize>,
}
impl Fixture {
    fn released(&self, usage: ModelCaptureUsage) -> bool {
        usage.source_bytes() == 0
            && usage.captures() == 0
            && usage.active_workers() == 0
            && usage.metadata_bytes() == self.socket_cleanup.retained_metadata_bytes()
    }
    async fn stop(mut self) {
        self.socket_cleanup.stop_accepting_upgrades();
        let worker = self.worker.take().unwrap();
        worker.abort();
        assert!(worker.await.unwrap_err().is_cancelled());
        assert_eq!(
            self.socket_cleanup
                .drain(tokio::time::Instant::now() + WAIT)
                .await,
            crate::commands::ui::socket_tasks::SocketDrainOutcome::Joined
        );
        usage_is(&self.observer, |usage| {
            usage == ModelCaptureUsage::default()
        })
        .await;
        assert_eq!(self.observer.usage(), ModelCaptureUsage::default());
    }
    async fn connect(&self) -> Socket {
        let mut request = format!("{}/rpc", self.base.replace("http://", "ws://"))
            .into_client_request()
            .unwrap();
        request
            .headers_mut()
            .insert("origin", self.base.parse().unwrap());
        request
            .headers_mut()
            .insert("cookie", self.cookie.parse().unwrap());
        let (mut socket, _) = connect_async(request).await.unwrap();
        send(
            &mut socket,
            1,
            "morphir.session.initialize",
            json!({"protocolVersion":1,"sessionId":"socket-originals-session"}),
        )
        .await;
        assert_eq!(reply(&mut socket, 1).await["result"]["protocolVersion"], 1);
        send(
            &mut socket,
            2,
            "morphir.workspace.open",
            json!({"source":self.source}),
        )
        .await;
        let opened = reply(&mut socket, 2).await;
        assert!(
            opened["result"]["snapshot"]["projects"]
                .as_array()
                .unwrap()
                .iter()
                .any(|project| project["id"] == self.project)
        );
        socket
    }
    fn capture_params(&self) -> Value {
        json!({"contractVersion":VERSION,"source":{"providerId":self.source["providerId"],"locator":self.source["locator"]},"projectId":self.project,"scope":"complete","semantic":"none"})
    }
}
impl Fixture {
    async fn connect_small_receive_buffer(&self) -> (Socket, usize) {
        let tcp = TcpSocket::new_v4().unwrap();
        tcp.set_recv_buffer_size(1024).unwrap();
        let before_connect = tcp.recv_buffer_size().unwrap();
        let address = self.base.strip_prefix("http://").unwrap().parse().unwrap();
        let stream = tcp.connect(address).await.unwrap();
        let connected = socket2::SockRef::from(&stream);
        let after_connect = connected.recv_buffer_size().unwrap();
        // The current native OS can retune the buffer during TCP connect.
        // Set and verify the actual connected socket before the WS handshake.
        connected.set_recv_buffer_size(1024).unwrap();
        let receive_buffer = connected.recv_buffer_size().unwrap();
        eprintln!(
            "actual client SO_RCVBUF: before TCP connect={before_connect}, after TCP connect={after_connect}, before WS handshake={receive_buffer}"
        );
        assert!(
            receive_buffer < 65536,
            "OS receive buffer cannot force the selected read to stall: {receive_buffer}"
        );
        let mut request = format!("{}/rpc", self.base.replace("http://", "ws://"))
            .into_client_request()
            .unwrap();
        request
            .headers_mut()
            .insert("origin", self.base.parse().unwrap());
        request
            .headers_mut()
            .insert("cookie", self.cookie.parse().unwrap());
        let (mut socket, _) =
            tokio_tungstenite::client_async(request, MaybeTlsStream::Plain(stream))
                .await
                .unwrap();
        send(
            &mut socket,
            1,
            "morphir.session.initialize",
            json!({"protocolVersion":1,"sessionId":"socket-originals-session"}),
        )
        .await;
        assert_eq!(reply(&mut socket, 1).await["result"]["protocolVersion"], 1);
        send(
            &mut socket,
            2,
            "morphir.workspace.open",
            json!({"source":self.source}),
        )
        .await;
        let opened = reply(&mut socket, 2).await;
        assert!(
            opened["result"]["snapshot"]["projects"]
                .as_array()
                .unwrap()
                .iter()
                .any(|project| project["id"] == self.project)
        );
        (socket, receive_buffer)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        // Test listener teardown is separate from release/cancellation assertions.
        if let Some(worker) = &self.worker {
            worker.abort();
        }
        let _ = fs2::FileExt::unlock(&self.lock);
    }
}

async fn send(socket: &mut Socket, id: u64, method: &str, params: Value) {
    socket
        .send(Message::Text(
            json!({"jsonrpc":"2.0","id":id,"method":method,"params":params})
                .to_string()
                .into(),
        ))
        .await
        .unwrap();
}
async fn reply(socket: &mut Socket, id: u64) -> Value {
    tokio::time::timeout(WAIT, async {
        loop {
            match socket
                .next()
                .await
                .expect("socket stays connected")
                .unwrap()
            {
                Message::Text(text) => {
                    let value: Value = serde_json::from_str(&text).unwrap();
                    assert_eq!(value["jsonrpc"], "2.0");
                    assert_eq!(value["id"], id, "ordered response correlation");
                    return value;
                }
                Message::Ping(_) | Message::Pong(_) => {}
                other => panic!("unexpected socket frame: {other:?}"),
            }
        }
    })
    .await
    .expect("bounded actual socket reply")
}
async fn usage_is(
    observer: &ModelCaptureUsageObserver,
    predicate: impl Fn(ModelCaptureUsage) -> bool,
) {
    tokio::time::timeout(WAIT, async {
        loop {
            if predicate(observer.usage()) {
                return;
            }
            // Read the genuine counter on every iteration; elapsed time never
            // supplies an event, owner transition or worker-exit assertion.
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("bounded actual shared resource transition");
}

enum SocketBuffers {
    Ordinary,
    SmallSend,
}

async fn fixture() -> (Fixture, Socket) {
    fixture_with(
        br#"{"formatVersion":4,"opaque":"socket fixture"}"#,
        SocketBuffers::Ordinary,
    )
    .await
}

async fn fixture_with(primary: &[u8], buffers: SocketBuffers) -> (Fixture, Socket) {
    let directory = tempfile::tempdir().unwrap();
    fs::write(
        directory.path().join("morphir.toml"),
        "[project]\nname='acme/socket-originals'\nversion='1.0.0'\n",
    )
    .unwrap();
    let output = directory.path().join(".morphir/out");
    fs::create_dir_all(output.join("compile.dest")).unwrap();
    fs::write(output.join("compile.dest/model.json"), primary).unwrap();
    fs::write(output.join("compile.json"), br#"{"schema":1,"task":"compile","module":"","completedAt":"now","ir":{"path":"model.json","layout":"single-file","format":"json","version":"v4"},"morphirModelOriginals":{"contractVersion":"0.1.0-draft.1","companions":[]}}"#).unwrap();
    let lock = fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(output.join("compile.lock"))
        .unwrap();
    fs2::FileExt::lock_exclusive(&lock).unwrap();
    let provider = Arc::new(
        NativeWorkspaceProvider::discover_with_options(
            directory.path(),
            "socket-originals-session",
            ConfigLoadOptions::project_only(),
        )
        .unwrap()
        .authorize_originals_lookup(cap_std::ambient_authority())
        .unwrap(),
    );
    let source = serde_json::to_value(provider.initial_sources().pop().unwrap()).unwrap();
    let host = BoundUiHost::bind_with_originals(
        "socket-originals-session".into(),
        SessionCapabilities {
            workspace: Some(provider.clone()),
            ..Default::default()
        },
        Some(OriginalsProvider::Native(provider)),
    )
    .await
    .unwrap();
    let base = host.base_url();
    let launch = host.launch_url();
    let observer = host.model_originals_observer();
    let workspace = host.workspace_control();
    let (listener, router, owner) = host.into_parts();
    let socket_cleanup = crate::commands::ui::socket_tasks::SocketCleanup::Pending(owner);
    let (worker, send_buffer) = match buffers {
        SocketBuffers::Ordinary => (
            tokio::spawn(async move {
                axum::serve(listener, router)
                    .await
                    .map_err(crate::error::CliError::from)
            }),
            None,
        ),
        SocketBuffers::SmallSend => {
            use axum::serve::ListenerExt as _;
            // Configure the actual bound listener before accept, retaining the
            // same production Router, authentication and connection owners.
            let socket = socket2::SockRef::from(&listener);
            socket.set_send_buffer_size(1024).unwrap();
            let actual = socket.send_buffer_size().unwrap();
            assert!(
                actual < 65536,
                "OS send buffer cannot force the selected read to stall"
            );
            let listener = listener.tap_io(|stream| {
                let socket = socket2::SockRef::from(&*stream);
                let inherited = socket.send_buffer_size().unwrap();
                socket.set_send_buffer_size(1024).unwrap();
                let actual = socket.send_buffer_size().unwrap();
                eprintln!(
                    "actual accepted TCP SO_SNDBUF: inherited={inherited}, before HTTP/WS={actual}"
                );
                assert!(
                    actual < 65536,
                    "actual accepted send buffer is too large: {actual}"
                );
            });
            let worker = tokio::spawn(async move {
                axum::serve(listener, router)
                    .await
                    .map_err(crate::error::CliError::from)
            });
            (worker, Some(actual))
        }
    };
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .timeout(WAIT)
        .build()
        .unwrap();
    let unauthorized = connect_async(format!("{}/rpc", base.replace("http://", "ws://"))).await;
    assert!(
        matches!(unauthorized, Err(tokio_tungstenite::tungstenite::Error::Http(ref response)) if response.status().as_u16() == 401)
    );
    let launched = client.get(launch).send().await.unwrap();
    assert!(launched.status().is_redirection());
    let cookie = launched.headers()["set-cookie"]
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap()
        .to_owned();
    let mut request = format!("{}/rpc", base.replace("http://", "ws://"))
        .into_client_request()
        .unwrap();
    request
        .headers_mut()
        .insert("origin", base.parse().unwrap());
    request
        .headers_mut()
        .insert("cookie", cookie.parse().unwrap());
    let (mut socket, _) = connect_async(request).await.unwrap();
    send(
        &mut socket,
        1,
        "morphir.session.initialize",
        json!({"protocolVersion":1,"sessionId":"socket-originals-session"}),
    )
    .await;
    assert_eq!(reply(&mut socket, 1).await["result"]["protocolVersion"], 1);
    send(
        &mut socket,
        2,
        "morphir.workspace.open",
        json!({"source":source}),
    )
    .await;
    let opened = reply(&mut socket, 2).await;
    let project = opened["result"]["snapshot"]["projects"]
        .as_array()
        .unwrap()
        .iter()
        .find(|project| project["relativePath"] == ".")
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_owned();
    (
        Fixture {
            _directory: directory,
            worker: Some(worker),
            socket_cleanup,
            observer,
            workspace,
            lock,
            source,
            project,
            base,
            cookie,
            send_buffer,
        },
        socket,
    )
}

async fn capture_while_locked(fixture: &Fixture, socket: &mut Socket) {
    let source =
        json!({"providerId":fixture.source["providerId"],"locator":fixture.source["locator"]});
    send(socket, 3, "morphir.model-originals.capture", json!({"contractVersion":VERSION,"source":source,"projectId":fixture.project,"scope":"complete","semantic":"none"})).await;
    usage_is(&fixture.observer, |usage| {
        usage.active_workers() == 1 && usage.captures() == 1
    })
    .await;
    assert_eq!(
        fixture.observer.usage().source_bytes(),
        0,
        "exclusive real compile lock prevents source capture"
    );
}

#[tokio::test]
async fn ping_and_one_pipelined_request_preserve_actual_blocked_capture() {
    let (fixture, mut socket) = fixture().await;
    capture_while_locked(&fixture, &mut socket).await;
    send(
        &mut socket,
        4,
        "morphir.workspace.open",
        json!({"source":fixture.source}),
    )
    .await;
    let ping = b"capture-still-owned";
    socket
        .send(Message::Ping(ping.as_slice().into()))
        .await
        .unwrap();
    tokio::time::timeout(WAIT, async {
        loop {
            match socket
                .next()
                .await
                .expect("pipeline must not disconnect")
                .unwrap()
            {
                Message::Pong(bytes) if bytes.as_ref() == ping => break,
                Message::Pong(_) | Message::Ping(_) => {}
                other => panic!("capture cannot settle before actual lock release: {other:?}"),
            }
        }
    })
    .await
    .expect("real Pong while lock is held");
    assert_eq!(fixture.observer.usage().active_workers(), 1);
    assert_eq!(fixture.observer.usage().captures(), 1);
    fs2::FileExt::unlock(&fixture.lock).unwrap();
    let captured = reply(&mut socket, 3).await;
    assert_eq!(captured["result"]["status"], "ready", "{captured}");
    assert_eq!(
        captured["result"]["projection"],
        json!({"status":"not-requested"})
    );
    let id = captured["result"]["captureId"].as_str().unwrap();
    let queued = reply(&mut socket, 4).await;
    assert!(
        queued["result"]["snapshot"]["projects"].is_array(),
        "{queued}"
    );
    assert_eq!(fixture.observer.usage().captures(), 1);
    send(
        &mut socket,
        5,
        "morphir.model-originals.release",
        json!({"contractVersion":VERSION,"captureId":id}),
    )
    .await;
    assert_eq!(reply(&mut socket, 5).await["result"]["status"], "released");
    usage_is(&fixture.observer, |usage| fixture.released(usage)).await;
    socket.close(None).await.unwrap();
    fixture.stop().await;
}

#[tokio::test]
async fn disconnect_cancels_actual_lock_wait_and_returns_credits_after_worker_exit() {
    let (fixture, mut socket) = fixture().await;
    capture_while_locked(&fixture, &mut socket).await;
    socket.close(None).await.unwrap();
    drop(socket);
    // The compile lock remains exclusively held. Cancellation must let the
    // real polling worker exit; a waiter drop cannot manufacture a refund.
    usage_is(&fixture.observer, |usage| fixture.released(usage)).await;
    assert!(fixture.lock.metadata().unwrap().is_file());
    fs2::FileExt::unlock(&fixture.lock).unwrap();
    fixture.stop().await;
}

#[tokio::test]
async fn actual_workspace_revocation_refuses_blocked_capture_and_later_v1_open() {
    let (fixture, mut socket) = fixture().await;
    capture_while_locked(&fixture, &mut socket).await;
    // This is the real host's issued registration-control handle. It neither
    // changes the request labels nor fabricates a provider or lifecycle state.
    fixture.workspace.revoke();
    fs2::FileExt::unlock(&fixture.lock).unwrap();
    let refused = reply(&mut socket, 3).await;
    assert!(
        refused.get("result").is_none(),
        "no Ready or partial capture: {refused}"
    );
    assert_eq!(
        refused["error"]["data"]["code"],
        "model_originals.unavailable"
    );
    usage_is(&fixture.observer, |usage| fixture.released(usage)).await;

    // Legacy opening and originals publication must consult the same current
    // host registration. Retaining an old source label cannot reopen it.
    send(
        &mut socket,
        4,
        "morphir.workspace.open",
        json!({"source":fixture.source}),
    )
    .await;
    let legacy = reply(&mut socket, 4).await;
    assert!(
        legacy.get("result").is_none(),
        "revoked v1 owner must not open: {legacy}"
    );
    assert!(legacy.get("error").is_some(), "{legacy}");
    assert!(fixture.released(fixture.observer.usage()));
    socket.close(None).await.unwrap();
    fixture.stop().await;
}

fn profile_failure(value: &Value, id: Value, code: &str) {
    assert_eq!(value.as_object().unwrap().len(), 3, "closed envelope");
    assert_eq!(value["jsonrpc"], "2.0");
    assert_eq!(value["id"], id);
    assert!(
        value.get("result").is_none(),
        "no Ready/partial result: {value}"
    );
    let error = value["error"].as_object().unwrap();
    assert_eq!(error.len(), 3, "closed error");
    assert_eq!(error["code"], -32602);
    assert!(error["message"].as_str().unwrap().encode_utf16().count() <= 512);
    assert_eq!(
        error["data"],
        json!({"profile":"morphir/workbench/model-originals","contractVersion":VERSION,"code":code})
    );
}

#[tokio::test]
async fn second_queued_text_refuses_and_closes_without_publishing_blocked_capture() {
    let (fixture, mut socket) = fixture().await;
    capture_while_locked(&fixture, &mut socket).await;
    for id in [4, 5] {
        send(
            &mut socket,
            id,
            "morphir.workspace.open",
            json!({"source":fixture.source}),
        )
        .await;
    }
    tokio::time::timeout(WAIT, async {
        let mut failure_seen = false;
        loop {
            match socket.next().await {
                Some(Ok(Message::Text(text))) => {
                    assert!(
                        !failure_seen,
                        "overflow must not deliver queued/Ready replies"
                    );
                    let value: Value = serde_json::from_str(&text).unwrap();
                    profile_failure(&value, Value::Null, "model_originals.invalid_request");
                    failure_seen = true;
                }
                Some(Ok(Message::Ping(_) | Message::Pong(_))) => {}
                Some(Ok(Message::Close(_))) | None | Some(Err(_)) => {
                    assert!(
                        failure_seen,
                        "closed profile overflow refusal precedes teardown"
                    );
                    break;
                }
                other => panic!("unexpected overflow frame: {other:?}"),
            }
        }
    })
    .await
    .expect("bounded overflow refusal and actual socket termination");
    drop(socket);
    usage_is(&fixture.observer, |usage| fixture.released(usage)).await;
    // Unlock only after the actual cancelled worker has returned its permit.
    fs2::FileExt::unlock(&fixture.lock).unwrap();
    fixture.stop().await;
}

#[tokio::test]
async fn host_slots_span_authenticated_sockets_and_release_allows_real_reuse() {
    let (fixture, mut first) = fixture().await;
    fs2::FileExt::unlock(&fixture.lock).unwrap();
    send(
        &mut first,
        3,
        "morphir.model-originals.capture",
        fixture.capture_params(),
    )
    .await;
    let first_ready = reply(&mut first, 3).await;
    assert_eq!(first_ready["result"]["status"], "ready", "{first_ready}");
    let first_id = first_ready["result"]["captureId"]
        .as_str()
        .unwrap()
        .to_owned();

    let mut captures = Vec::new();
    for _ in 1..64 {
        let mut socket = fixture.connect().await;
        send(
            &mut socket,
            3,
            "morphir.model-originals.capture",
            fixture.capture_params(),
        )
        .await;
        let ready = reply(&mut socket, 3).await;
        assert_eq!(ready["result"]["status"], "ready", "{ready}");
        let id = ready["result"]["captureId"].as_str().unwrap().to_owned();
        assert_ne!(id, first_id);
        assert!(
            captures
                .iter()
                .all(|(_, existing): &(Socket, String)| existing != &id)
        );
        captures.push((socket, id));
    }
    usage_is(&fixture.observer, |usage| {
        usage.captures() == 64 && usage.active_workers() == 0
    })
    .await;
    let full = fixture.observer.usage();
    assert_eq!(
        full.source_bytes(),
        64 * br#"{"formatVersion":4,"opaque":"socket fixture"}"#.len()
    );
    assert!(full.metadata_bytes() > 0);

    let mut extra = fixture.connect().await;
    let before_refusal = fixture.observer.usage();
    assert_eq!(before_refusal.source_bytes(), full.source_bytes());
    assert_eq!(before_refusal.captures(), full.captures());
    assert_eq!(before_refusal.active_workers(), full.active_workers());
    send(
        &mut extra,
        3,
        "morphir.model-originals.capture",
        fixture.capture_params(),
    )
    .await;
    profile_failure(
        &reply(&mut extra, 3).await,
        json!(3),
        "model_originals.capacity",
    );
    assert_eq!(
        fixture.observer.usage(),
        before_refusal,
        "refusal retains all prior owners and refunds temporary binding credit"
    );

    send(
        &mut first,
        4,
        "morphir.model-originals.release",
        json!({"contractVersion":VERSION,"captureId":first_id}),
    )
    .await;
    assert_eq!(reply(&mut first, 4).await["result"]["status"], "released");
    assert_eq!(fixture.observer.usage().captures(), 63);
    send(
        &mut extra,
        4,
        "morphir.model-originals.capture",
        fixture.capture_params(),
    )
    .await;
    let reused = reply(&mut extra, 4).await;
    assert_eq!(reused["result"]["status"], "ready", "{reused}");
    let reused_id = reused["result"]["captureId"].as_str().unwrap();
    assert_ne!(reused_id, first_id);
    assert!(captures.iter().all(|(_, id)| id != reused_id));
    assert_eq!(fixture.observer.usage().captures(), 64);
    send(
        &mut extra,
        5,
        "morphir.model-originals.release",
        json!({"contractVersion":VERSION,"captureId":reused_id}),
    )
    .await;
    assert_eq!(reply(&mut extra, 5).await["result"]["status"], "released");
    extra.close(None).await.unwrap();
    first.close(None).await.unwrap();
    for (mut socket, id) in captures {
        send(
            &mut socket,
            4,
            "morphir.model-originals.release",
            json!({"contractVersion":VERSION,"captureId":id}),
        )
        .await;
        assert_eq!(reply(&mut socket, 4).await["result"]["status"], "released");
        socket.close(None).await.unwrap();
    }
    usage_is(&fixture.observer, |usage| fixture.released(usage)).await;
    fixture.stop().await;
}

#[tokio::test]
async fn actual_stalled_reader_expires_profile_send_after_thirty_wall_clock_seconds() {
    // Independent large primary, within the real source/decode bounds. The
    // ordinary maximum read becomes an approximately87KiB base64 frame.
    let mut primary = br#"{"formatVersion":4,"opaque":""#.to_vec();
    primary.extend(std::iter::repeat_n(b'x', 131072));
    primary.extend_from_slice(br#""}"#);
    let (fixture, mut initial) = fixture_with(&primary, SocketBuffers::SmallSend).await;
    initial.close(None).await.unwrap();
    drop(initial);
    fs2::FileExt::unlock(&fixture.lock).unwrap();
    let (mut socket, receive_buffer) = fixture.connect_small_receive_buffer().await;
    send(
        &mut socket,
        3,
        "morphir.model-originals.capture",
        fixture.capture_params(),
    )
    .await;
    let captured = reply(&mut socket, 3).await;
    assert_eq!(captured["result"]["status"], "ready", "{captured}");
    let capture = captured["result"]["captureId"].as_str().unwrap();
    send(
        &mut socket,
        4,
        "morphir.model-originals.inventory",
        json!({"contractVersion":VERSION,"captureId":capture,"startIndex":0,"maxEntries":1}),
    )
    .await;
    let inventory = reply(&mut socket, 4).await;
    let entry = &inventory["result"]["entries"][0];
    assert_eq!(entry["path"], "model.json");
    assert_eq!(entry["kind"], "file");
    assert_eq!(entry["byteLength"], primary.len());
    assert_eq!(fixture.observer.usage().source_bytes(), primary.len());
    assert_eq!(fixture.observer.usage().captures(), 1);
    assert_eq!(fixture.observer.usage().active_workers(), 0);

    let MaybeTlsStream::Plain(stream) = socket.get_ref() else {
        panic!("loopback fixture is plain TCP")
    };
    let connected = socket2::SockRef::from(stream);
    let before_read = connected.recv_buffer_size().unwrap();
    connected.set_recv_buffer_size(1024).unwrap();
    let at_read = connected.recv_buffer_size().unwrap();
    eprintln!("actual client SO_RCVBUF: after WS setup={before_read}, at selected read={at_read}");
    assert!(at_read < 65536);
    use base64::Engine as _;
    // These are finite test-observer bounds, not host policy or fake IO counts.
    const MAX_READS: usize = 32;
    const MAX_PEEK: usize = 4 * 1024 * 1024;
    let expected_content = base64::engine::general_purpose::STANDARD.encode(&primary[..65536]);
    let mut peek = vec![0; MAX_PEEK];
    let mut sent = 1;
    let mut complete = 0;
    let mut previous_size = 0;
    let mut largest_peek = 0;
    let mut incomplete_observed = false;
    let mut started = Instant::now();
    send(&mut socket, 5, "morphir.model-originals.read", json!({"contractVersion":VERSION,"captureId":capture,"target":{"kind":"original","entryId":entry["entryId"]},"offset":0,"maxBytes":65536})).await;
    // No WebSocket reads or consuming TCP reads occur below. Another real read
    // is issued only after the prior complete frame and exact ID are witnessed.
    tokio::time::timeout(Duration::from_secs(60), async {
        loop {
            if fixture.released(fixture.observer.usage()) {
                assert!(complete < sent && incomplete_observed, "owner ended without an observed incomplete current frame");
                break;
            }
            let MaybeTlsStream::Plain(stream) = socket.get_ref() else { panic!("plain TCP") };
            let size = tokio::time::timeout(WAIT, stream.peek(&mut peek)).await
                .expect("real response data").unwrap();
            assert!(size > 0 && size < MAX_PEEK, "inconclusive: observer buffer exhausted or peer closed before a partial frame");
            largest_peek = largest_peek.max(size);
            if size > previous_size {
                let (observed, full_bytes) = peek_read_replies(&peek[..size], capture, &entry["entryId"], &expected_content);
                assert!(observed <= sent, "unsolicited read response");
                complete = complete.max(observed);
                if complete < sent && size > full_bytes {
                    incomplete_observed = true;
                }
                previous_size = size;
            }
            if complete == sent {
                assert!(sent < MAX_READS, "inconclusive: all32 bounded reads fit the actual OS buffers");
                eprintln!("actual complete held TCP frames={complete}, peek bytes={size}; issuing exactly one next read");
                sent += 1;
                incomplete_observed = false;
                started = Instant::now();
                send(&mut socket, 4 + sent as u64, "morphir.model-originals.read", json!({"contractVersion":VERSION,"captureId":capture,"target":{"kind":"original","entryId":entry["entryId"]},"offset":0,"maxBytes":65536})).await;
            }
            assert!(started.elapsed() < Duration::from_secs(45), "inconclusive: current held frame did not force send retirement within45s");
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    }).await.expect("finite real TCP-window probe");
    let elapsed = started.elapsed();
    assert!(
        elapsed >= Duration::from_secs(30),
        "retired before the real30second send deadline: {elapsed:?}"
    );
    assert!(
        elapsed < Duration::from_secs(45),
        "actual timeout exceeded bounded measurement: {elapsed:?}"
    );
    eprintln!(
        "actual stalled-reader measurement: listener SO_SNDBUF={}, client SO_RCVBUF={receive_buffer}, sent={sent}, complete={complete}, max peek={largest_peek}, incomplete current frame={incomplete_observed}, owner retirement={elapsed:?}",
        fixture.send_buffer.unwrap()
    );
    assert!(fixture.released(fixture.observer.usage()));
    // Dispose only after the genuine server timeout and zero-credit observation.
    drop(socket);
    fixture.stop().await;
}

fn peek_read_replies(bytes: &[u8], capture: &str, entry: &Value, content: &str) -> (usize, usize) {
    use tokio_tungstenite::tungstenite::protocol::frame::{
        FrameSocket,
        coding::{Data, OpCode},
    };
    // Reuse the maintained WebSocket frame reader over the nonconsuming peek.
    // None is its genuine incomplete-frame result; no handwritten wire parser.
    let mut reader = FrameSocket::new(std::io::Cursor::new(bytes));
    let mut count = 0;
    let mut full_bytes = 0;
    while let Some(frame) = reader.read(Some(128 * 1024)).unwrap() {
        assert!(frame.header().is_final && frame.header().mask.is_none());
        assert_eq!(frame.header().opcode, OpCode::Data(Data::Text));
        full_bytes += frame.len();
        let text = frame.into_text().unwrap();
        let value = morphir_mck::json::parse_exact_document(text.as_str()).unwrap();
        assert_eq!(value["jsonrpc"], "2.0");
        assert_eq!(value["id"], 5 + count as u64);
        assert!(value.get("error").is_none(), "{value}");
        assert_eq!(value["result"]["captureId"], capture);
        assert_eq!(
            value["result"]["target"],
            json!({"kind":"original","entryId":entry})
        );
        assert_eq!(value["result"]["offset"], 0);
        assert_eq!(value["result"]["nextOffset"], 65536);
        assert_eq!(value["result"]["content"], content);
        count += 1;
    }
    (count, full_bytes)
}

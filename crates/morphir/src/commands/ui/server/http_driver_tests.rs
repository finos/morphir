//! Child of server. Real TCP/Hyper driver destruction and stopped upgrade entry.
//! No source-complete claim: the separate authenticated SourceFixture control
//! covers the genuine source writer. These controls consume actual task joins.
use super::*;
use crate::commands::ui::{
    model_originals::{HostModelCaptureCapacity, ModelCaptureUsage},
    socket_tasks::{SocketDrainOutcome, SocketTaskRegistry},
};
use std::{
    future::Future as _,
    pin::Pin,
    sync::{Condvar, Mutex},
    task::{Context, Poll},
    time::Duration,
};
use tokio::{
    io::{AsyncRead, AsyncReadExt as _, AsyncWrite, AsyncWriteExt as _, ReadBuf},
    net::TcpStream,
    sync::oneshot,
    time::{Instant, timeout},
};

const WAIT: Duration = Duration::from_secs(5);

async fn http_reply(stream: &mut TcpStream) -> (String, Vec<u8>) {
    timeout(WAIT, async {
        let mut head = Vec::new();
        while !head.ends_with(b"\r\n\r\n") {
            assert!(head.len() < 65_536, "bounded real response headers");
            head.push(stream.read_u8().await.unwrap());
        }
        let head = String::from_utf8(head).unwrap();
        let length = head
            .lines()
            .filter_map(|line| line.split_once(':'))
            .find(|(name, _)| name.eq_ignore_ascii_case("content-length"))
            .map_or(0, |(_, value)| value.trim().parse::<usize>().unwrap());
        assert!(length <= 65_536, "bounded real response body");
        let mut body = vec![0; length];
        stream.read_exact(&mut body).await.unwrap();
        (head, body)
    })
    .await
    .unwrap()
}

#[derive(Default)]
struct DestructionGate {
    released: Mutex<bool>,
    changed: Condvar,
}
impl DestructionGate {
    fn release(&self) {
        *self.released.lock().unwrap() = true;
        self.changed.notify_all();
    }
}
struct ReleaseOnDrop(Arc<DestructionGate>);
impl Drop for ReleaseOnDrop {
    fn drop(&mut self) {
        self.0.release();
    }
}
struct ListenerTask(Option<tokio::task::JoinHandle<Result<(), CliError>>>);
impl Drop for ListenerTask {
    fn drop(&mut self) {
        if let Some(task) = &self.0 {
            task.abort();
        }
    }
}

struct TestListener {
    actual: TcpListener,
    gate: Arc<DestructionGate>,
    entered: Option<oneshot::Sender<()>>,
}
struct TestIo {
    actual: TcpStream,
    gate: Arc<DestructionGate>,
    entered: Option<oneshot::Sender<()>>,
}
impl axum::serve::Listener for TestListener {
    type Io = TestIo;
    type Addr = SocketAddr;
    async fn accept(&mut self) -> (Self::Io, Self::Addr) {
        let (actual, address) = axum::serve::Listener::accept(&mut self.actual).await;
        (
            TestIo {
                actual,
                gate: self.gate.clone(),
                entered: self.entered.take(),
            },
            address,
        )
    }
    fn local_addr(&self) -> std::io::Result<SocketAddr> {
        self.actual.local_addr()
    }
}
impl AsyncRead for TestIo {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.actual).poll_read(cx, buf)
    }
}
impl AsyncWrite for TestIo {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.actual).poll_write(cx, buf)
    }
    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.actual).poll_flush(cx)
    }
    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.actual).poll_shutdown(cx)
    }
}
impl Drop for TestIo {
    fn drop(&mut self) {
        let Some(entered) = self.entered.take() else {
            return;
        };
        let _ = entered.send(());
        // This is the actual accepted TCP stream inside Hyper's driver. A
        // replacement runtime worker keeps real timers/I/O progressing while
        // its final destruction is held. No production callback is installed.
        tokio::task::block_in_place(|| {
            let mut released = self.gate.released.lock().unwrap();
            while !*released {
                released = self.gate.changed.wait(released).unwrap();
            }
        });
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_http_driver_destructor_retains_same_join_across_cancel_and_deadline() {
    let capacity = HostModelCaptureCapacity::default();
    let (tasks, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
    let gate = Arc::new(DestructionGate::default());
    let release = ReleaseOnDrop(gate.clone());
    let (entered, destructing) = oneshot::channel();
    let actual = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = actual.local_addr().unwrap();
    let listener = TestListener {
        actual,
        gate,
        entered: Some(entered),
    };
    let router = Router::new().route("/", get(|| async { "actual-http" }));
    let mut listener = ListenerTask(Some(tokio::spawn(serve_connections(
        listener,
        router,
        tasks.clone(),
    ))));
    let mut stream = timeout(WAIT, TcpStream::connect(address))
        .await
        .unwrap()
        .unwrap();
    stream
        .write_all(
            format!("GET / HTTP/1.1\r\nHost: {address}\r\nConnection: keep-alive\r\n\r\n")
                .as_bytes(),
        )
        .await
        .unwrap();
    let response = http_reply(&mut stream).await;
    let before_id = owner.actual_task_id();
    // Listener completion does not consume the genuine connection task.
    let actual_listener = listener.0.take().unwrap();
    actual_listener.abort();
    let listener_join = timeout(WAIT, actual_listener).await;
    let cancelled_pending = {
        let drain = owner.drain(Instant::now() + WAIT);
        tokio::pin!(drain);
        std::future::poll_fn(|cx| Poll::Ready(drain.as_mut().poll(cx).is_pending())).await
        // Dropping the actual borrowed drain future restores its SAME handle.
    };
    let entered = timeout(WAIT, destructing).await;
    let after_cancel = owner.actual_task_id();
    let deadline = timeout(
        WAIT,
        owner.drain(Instant::now() + Duration::from_millis(20)),
    )
    .await;
    let after_deadline = owner.actual_task_id();
    let retained = owner.retained_tasks();
    let held_usage = capacity.usage();
    // Always release the real destructor and consume the real join before
    // evaluating any ownership/deadline assertions. ReleaseOnDrop also covers
    // earlier setup panics; raw Drop makes no cleanup certificate.
    drop(release);
    let joined = timeout(WAIT, owner.join()).await;
    let after_join = owner.retained_tasks();
    drop(stream);
    drop(owner);
    drop(tasks);
    let final_usage = capacity.usage();
    assert_eq!(response.0.split_whitespace().nth(1), Some("200"));
    assert_eq!(response.1, b"actual-http");
    assert!(matches!(listener_join, Ok(Err(error)) if error.is_cancelled()));
    assert!(cancelled_pending);
    assert!(matches!(entered, Ok(Ok(()))));
    assert!(
        before_id.is_some(),
        "actual driver JoinHandle must be installed"
    );
    assert_eq!(after_cancel, before_id);
    assert_eq!(after_deadline, before_id);
    assert!(matches!(deadline, Ok(SocketDrainOutcome::Pending { .. })));
    assert_eq!(retained, 1);
    assert!(held_usage.metadata_bytes() > 0);
    assert_eq!(joined, Ok(SocketDrainOutcome::Joined));
    assert_eq!(after_join, 0);
    assert_eq!(final_usage, ModelCaptureUsage::default());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn admitted_authenticated_http_driver_refuses_upgrade_after_stop_before_101() {
    let mut host = BoundUiHost::bind(
        "stopped-http-upgrade".into(),
        SessionCapabilities {
            workspace: Some(Arc::new(super::tests::StubWorkspace)),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let address = host.address();
    let base = host.base_url();
    let launch = host.launch_url();
    let usage = host.model_originals_observer();
    let mut sockets = host.take_socket_cleanup().unwrap();
    let mut captures = host.take_capture_cleanup().unwrap().into_pending();
    let mut listener = ListenerTask(Some(tokio::spawn(host.serve())));
    let mut stream = timeout(WAIT, TcpStream::connect(address))
        .await
        .unwrap()
        .unwrap();
    let path = launch.strip_prefix(&base).unwrap();
    stream
        .write_all(
            format!("GET {path} HTTP/1.1\r\nHost: {address}\r\nConnection: keep-alive\r\n\r\n")
                .as_bytes(),
        )
        .await
        .unwrap();
    let launch_reply = http_reply(&mut stream).await;
    let cookie = launch_reply
        .0
        .lines()
        .filter_map(|line| line.split_once(':'))
        .find(|(name, _)| name.eq_ignore_ascii_case("set-cookie"))
        .unwrap()
        .1
        .trim()
        .split(';')
        .next()
        .unwrap();
    stream.write_all(format!("GET /api/session HTTP/1.1\r\nHost: {address}\r\nOrigin: {base}\r\nCookie: {cookie}\r\nConnection: keep-alive\r\n\r\n").as_bytes()).await.unwrap();
    let session_reply = http_reply(&mut stream).await;
    let session: serde_json::Value = serde_json::from_slice(&session_reply.1).unwrap();
    let before_id = sockets.actual_task_id();
    let before = sockets.retained_tasks();
    sockets.stop_accepting_upgrades();
    // SAME already-admitted HTTP1 connection, actual valid handshake and auth.
    stream.write_all(format!("GET /rpc HTTP/1.1\r\nHost: {address}\r\nOrigin: {base}\r\nCookie: {cookie}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n").as_bytes()).await.unwrap();
    let refused = http_reply(&mut stream).await;
    let after_id = sockets.actual_task_id();
    let after = sockets.retained_tasks();
    let actual_listener = listener.0.take().unwrap();
    actual_listener.abort();
    let listener_join = timeout(WAIT, actual_listener).await;
    let joined = timeout(WAIT, sockets.join()).await;
    let captures_joined = timeout(WAIT, captures.join_retained()).await;
    drop(stream);
    drop(sockets);
    drop(captures);
    let final_usage = usage.usage();
    assert_eq!(launch_reply.0.split_whitespace().nth(1), Some("303"));
    assert_eq!(session_reply.0.split_whitespace().nth(1), Some("200"));
    assert_eq!(session["sessionId"], "stopped-http-upgrade");
    assert!(before_id.is_some());
    assert_eq!(before, 1);
    assert_eq!(refused.0.split_whitespace().nth(1), Some("503"));
    assert_eq!(after_id, before_id);
    assert_eq!(after, 1, "refusal cannot install a new upgrade task");
    assert!(matches!(listener_join, Ok(Err(error)) if error.is_cancelled()));
    assert_eq!(joined, Ok(SocketDrainOutcome::Joined));
    assert!(matches!(captures_joined, Ok(Ok(()))));
    assert_eq!(final_usage, ModelCaptureUsage::default());
}

mod closed_listener_test;
mod malformed_http_test;
mod resource_refusal_tests;

//! Production Axum patch regression controls using real HTTP/WebSocket tasks.
//! These verify the dependency seam, not full Morphir campaign qualification.
use axum::{Router, extract::WebSocketUpgrade, routing::get};
use futures_util::{SinkExt, StreamExt};
use std::sync::{Arc, Condvar, Mutex};
use tokio::{
    sync::oneshot,
    task::JoinHandle,
    time::{Duration, timeout},
};

const WAIT: Duration = Duration::from_secs(5);

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
struct HeldDestructor {
    gate: Arc<DestructionGate>,
    entered: Option<oneshot::Sender<()>>,
}
impl Drop for HeldDestructor {
    fn drop(&mut self) {
        let _ = self.entered.take().unwrap().send(());
        tokio::task::block_in_place(|| {
            let mut released = self.gate.released.lock().unwrap();
            while !*released {
                released = self.gate.changed.wait(released).unwrap();
            }
        });
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn owned_whole_upgrade_future_spans_before_callback_and_final_destruction() {
    let (start, mut before_callback) = oneshot::channel();
    let start = Arc::new(Mutex::new(Some(start)));
    let (resume, held_before_callback) = oneshot::channel();
    let held_before_callback = Arc::new(Mutex::new(Some(held_before_callback)));
    let (entered, mut callback_entered) = oneshot::channel();
    let entered = Arc::new(Mutex::new(Some(entered)));
    let (destructing, destructor_entered) = oneshot::channel();
    let destructing = Arc::new(Mutex::new(Some(destructing)));
    let destruction_gate = Arc::new(DestructionGate::default());
    let release_on_drop = ReleaseOnDrop(destruction_gate.clone());
    let join: Arc<Mutex<Option<JoinHandle<()>>>> = Arc::default();
    let app = Router::new().route(
        "/ws",
        get({
            let join = join.clone();
            let destruction_gate = destruction_gate.clone();
            move |ws: WebSocketUpgrade| {
                let start = start.lock().unwrap().take().unwrap();
                let held_before_callback = held_before_callback.lock().unwrap().take().unwrap();
                let entered = entered.lock().unwrap().take().unwrap();
                let destructing = destructing.lock().unwrap().take().unwrap();
                let destruction_gate = destruction_gate.clone();
                let (response, future) =
                    ws.protocols(["owned-v1"])
                        .into_upgrade_future(move |mut socket| async move {
                            let _destructor = HeldDestructor {
                                gate: destruction_gate,
                                entered: Some(destructing),
                            };
                            assert_eq!(socket.protocol().unwrap(), "owned-v1");
                            let _ = entered.send(());
                            let text = socket.recv().await.unwrap().unwrap();
                            assert_eq!(text.into_text().unwrap(), "actual request");
                            socket
                                .send(axum::extract::ws::Message::Text("actual reply".into()))
                                .await
                                .unwrap();
                            // The next step is real future destruction, deliberately held.
                        });
                *join.lock().unwrap() = Some(tokio::spawn(async move {
                    let _ = start.send(());
                    let _ = held_before_callback.await;
                    future.await;
                }));
                async move { response }
            }
        }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let mut request =
        tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request(format!(
            "ws://{address}/ws"
        ))
        .unwrap();
    request
        .headers_mut()
        .insert("Sec-WebSocket-Protocol", "owned-v1".parse().unwrap());
    let (mut client, response) = timeout(WAIT, tokio_tungstenite::connect_async(request))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(response.status(), 101);
    timeout(WAIT, &mut before_callback).await.unwrap().unwrap();
    assert!(matches!(
        callback_entered.try_recv(),
        Err(oneshot::error::TryRecvError::Empty)
    ));
    let mut task = join.lock().unwrap().take().unwrap();
    assert!(!task.is_finished());
    resume.send(()).unwrap();
    timeout(WAIT, &mut callback_entered).await.unwrap().unwrap();
    client
        .send(tokio_tungstenite::tungstenite::Message::Text(
            "actual request".into(),
        ))
        .await
        .unwrap();
    assert_eq!(
        timeout(WAIT, client.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap()
            .into_text()
            .unwrap(),
        "actual reply"
    );
    timeout(WAIT, destructor_entered).await.unwrap().unwrap();
    assert!(!task.is_finished());
    assert!(
        timeout(Duration::from_millis(30), &mut task).await.is_err(),
        "real join must stay pending through final destruction"
    );
    drop(release_on_drop);
    timeout(WAIT, &mut task).await.unwrap().unwrap();
    server.abort();
    assert!(server.await.unwrap_err().is_cancelled());
}

#[tokio::test(flavor = "multi_thread")]
async fn legacy_on_upgrade_keeps_http_handshake_subprotocol_and_messages() {
    let app = Router::new().route(
        "/ws",
        get(|ws: WebSocketUpgrade| async {
            ws.protocols(["legacy-v1"])
                .on_upgrade(|mut socket| async move {
                    let received = socket.recv().await.unwrap().unwrap();
                    socket.send(received).await.unwrap();
                })
        }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let mut request =
        tokio_tungstenite::tungstenite::client::IntoClientRequest::into_client_request(format!(
            "ws://{address}/ws"
        ))
        .unwrap();
    request
        .headers_mut()
        .insert("Sec-WebSocket-Protocol", "legacy-v1".parse().unwrap());
    let (mut client, response) = timeout(WAIT, tokio_tungstenite::connect_async(request))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(response.status(), 101);
    assert_eq!(response.headers()["Sec-WebSocket-Protocol"], "legacy-v1");
    let sent = tokio_tungstenite::tungstenite::Message::Binary(vec![0, 255, 13, 10].into());
    client.send(sent.clone()).await.unwrap();
    assert_eq!(
        timeout(WAIT, client.next())
            .await
            .unwrap()
            .unwrap()
            .unwrap(),
        sent
    );
    server.abort();
    assert!(server.await.unwrap_err().is_cancelled());
    // This checks legacy behavior, not ownership of the legacy detached task.
}

#[tokio::test(flavor = "multi_thread")]
async fn owned_future_preserves_configured_frame_limit() {
    let actual: Arc<Mutex<Option<JoinHandle<bool>>>> = Arc::default();
    let app = Router::new().route(
        "/ws",
        get({
            let actual = actual.clone();
            move |ws: WebSocketUpgrade| {
                let (refused, refusal) = oneshot::channel();
                let (response, future) =
                    ws.max_frame_size(4)
                        .into_upgrade_future(|mut socket| async move {
                            let _ = refused.send(matches!(socket.recv().await, Some(Err(_))));
                        });
                *actual.lock().unwrap() = Some(tokio::spawn(async move {
                    future.await;
                    refusal.await.unwrap()
                }));
                async move { response }
            }
        }),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let (mut client, _) = timeout(
        WAIT,
        tokio_tungstenite::connect_async(format!("ws://{address}/ws")),
    )
    .await
    .unwrap()
    .unwrap();
    client
        .send(tokio_tungstenite::tungstenite::Message::Text(
            "12345".into(),
        ))
        .await
        .unwrap();
    let mut task = actual.lock().unwrap().take().unwrap();
    assert!(timeout(WAIT, &mut task).await.unwrap().unwrap());
    server.abort();
    assert!(server.await.unwrap_err().is_cancelled());
}

#[tokio::test(flavor = "multi_thread")]
async fn failed_http_upgrade_runs_original_failure_callback_under_owned_join() {
    use axum::extract::FromRequestParts;
    let actual: Arc<Mutex<Option<JoinHandle<()>>>> = Arc::default();
    let (failed, failure) = oneshot::channel();
    let failed = Arc::new(Mutex::new(Some(failed)));
    let (entered, request_entered) = oneshot::channel();
    let entered = Arc::new(Mutex::new(Some(entered)));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let server = tokio::spawn({
        let actual = actual.clone();
        async move {
            let (transport, _) = listener.accept().await.unwrap();
            let service = hyper::service::service_fn(
                move |request: hyper::Request<hyper::body::Incoming>| {
                    let actual = actual.clone();
                    let failed = failed.clone();
                    let entered = entered.clone();
                    async move {
                        let (mut parts, _) = request.into_parts();
                        let ws = WebSocketUpgrade::from_request_parts(&mut parts, &())
                            .await
                            .unwrap();
                        let failed = failed.lock().unwrap().take().unwrap();
                        let (_response, future) = ws
                            .on_failed_upgrade(move |_| {
                                let _ = failed.send(());
                            })
                            .into_upgrade_future(|_| async {
                                panic!("failed upgrade cannot enter socket callback")
                            });
                        *actual.lock().unwrap() = Some(tokio::spawn(future));
                        let _ = entered.lock().unwrap().take().unwrap().send(());
                        // Real service is pending before101. Cancelling its actual
                        // connection driver destroys hyper Pending's sender.
                        let response = std::future::pending::<axum::response::Response>().await;
                        Ok::<_, std::convert::Infallible>(response)
                    }
                },
            );
            hyper::server::conn::http1::Builder::new()
                .serve_connection(hyper_util::rt::TokioIo::new(transport), service)
                .with_upgrades()
                .await
                .unwrap();
        }
    });
    let client = tokio::spawn(tokio_tungstenite::connect_async(format!(
        "ws://{address}/ws"
    )));
    timeout(WAIT, request_entered).await.unwrap().unwrap();
    server.abort();
    assert!(server.await.unwrap_err().is_cancelled());
    timeout(WAIT, failure).await.unwrap().unwrap();
    let mut task = actual.lock().unwrap().take().unwrap();
    timeout(WAIT, &mut task).await.unwrap().unwrap();
    assert!(timeout(WAIT, client).await.unwrap().unwrap().is_err());
}

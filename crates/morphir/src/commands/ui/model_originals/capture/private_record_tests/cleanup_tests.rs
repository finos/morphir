//! Child of private_record_tests. Real native provider/worker/socket controls.
//! No producer DATA, fake task, injected Reader, counter event or reaper task.
use super::*;
use crate::commands::ui::server::BoundUiHost;
use futures_util::FutureExt as _;
use futures_util::{SinkExt as _, StreamExt as _};
use serde_json::{Value, json};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};

async fn cancelled_while_held(
    actual: &Actual,
    gate: &mut Gate,
) -> super::super::super::observation::WorkerAttemptObservation {
    let pending = actual.start(CaptureControl::new(), gate.hook.clone());
    let attempt = pending.worker_observation();
    gate.entered().await;
    pending.cancel();
    // The genuine body remains held until AFTER this response. A join inside
    // wait cannot satisfy this. This is a response bound, not a grace sleep.
    let result = tokio::time::timeout(Duration::from_secs(1), pending.wait())
        .await
        .unwrap();
    assert!(matches!(
        result,
        Err(ProviderCaptureError::Capture(CaptureError::Timeout))
    ));
    let snapshot = attempt.snapshot();
    assert_eq!(snapshot.owned_handles(), 1);
    assert_eq!(snapshot.joined_ok(), 0);
    assert_eq!(snapshot.dropped_unjoined(), 0);
    assert_eq!(actual.capacity.usage().active_workers(), 1);
    assert_eq!(actual.capacity.usage().captures(), 1);
    assert!(snapshot.require_joined_cleanup().is_err());
    attempt
}
fn assert_joined_error(attempt: &super::super::super::observation::WorkerAttemptObservation) {
    let snapshot = attempt.snapshot();
    assert_eq!(snapshot.started(), 1);
    assert_eq!(snapshot.returned_error(), 1);
    assert_eq!(snapshot.joined_ok(), 1); // join Ok, business body Timeout
    assert_eq!(snapshot.owned_handles(), 0);
    assert_eq!(snapshot.dropped_unjoined(), 0);
    snapshot.require_joined_cleanup().unwrap();
}
fn offer(actual: &Actual) -> crate::commands::ui::provider::originals::SelectedOriginalsOffer {
    let source = actual
        ._startup
        .workspace_provider()
        .initial_sources()
        .pop()
        .unwrap();
    actual
        .current
        .select_originals(OriginalsSelection::parse(&source, &project_key(&source, ".")).unwrap())
        .unwrap()
}

async fn socket_poison_tail(join_poison: bool) {
    let fixture = Fixture::new(RECORD);
    let mut actual = Actual::new(&fixture);
    let registry = super::super::super::lifecycle::CleanupRegistry::new();
    actual.connection.attach_cleanup_registry(&registry);
    let mut cleanup = registry.control().into_pending();
    let mut gate = Gate::new();
    let pending = actual.start(CaptureControl::new(), gate.hook.clone());
    let attempt = pending.worker_observation();
    let disconnect = actual.connection.disconnect_control();
    gate.entered().await;
    if join_poison {
        actual.connection.poison_cleanup_join_for_test();
    } else {
        actual.connection.poison_owner_for_test();
    }
    disconnect.handoff_on_drop();
    let waiter_drop = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| drop(pending)));
    let before = attempt.snapshot();
    // Catching is TEST observation only; any panic remains a failed oracle.
    let cancelled = tokio::time::timeout(
        Duration::from_millis(20),
        std::panic::AssertUnwindSafe(cleanup.drain_retained(tokio::time::Instant::now() + WAIT))
            .catch_unwind(),
    )
    .await;
    gate.release();
    let drained =
        std::panic::AssertUnwindSafe(cleanup.drain_retained(tokio::time::Instant::now() + WAIT))
            .catch_unwind()
            .await;
    let after = attempt.snapshot();
    let connection_drop =
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| drop(actual.connection)));
    drop(cleanup);
    drop(registry);
    let usage = actual.capacity.usage();
    assert!(waiter_drop.is_ok());
    assert_eq!(before.owned_handles(), 1);
    assert_eq!(before.dropped_unjoined(), 0);
    assert!(before.require_joined_cleanup().is_err());
    assert!(
        cancelled.is_err(),
        "borrowed deadline must retain, not panic or claim completion"
    );
    assert!(
        matches!(drained, Ok(Ok(()))),
        "real join must resolve without a poisoned-lock panic"
    );
    assert!(connection_drop.is_ok());
    assert_eq!(after.joined_ok(), 1);
    assert_eq!(after.owned_handles(), 0);
    assert_eq!(after.dropped_unjoined(), 0);
    assert!(
        after.require_joined_cleanup().is_err(),
        "poison remains incomplete after genuine joins"
    );
    assert_eq!(usage, ModelCaptureUsage::default());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn socket_join_poison_retains_through_cancelled_cleanup_and_real_join() {
    socket_poison_tail(true).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn socket_owner_poison_retains_through_cancelled_cleanup_and_real_join() {
    socket_poison_tail(false).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn awaited_cancel_returns_promptly_then_same_pending_owner_drains_after_real_release() {
    let fixture = Fixture::new(RECORD);
    let actual = Actual::new(&fixture);
    let mut gate = Gate::new();
    let attempt = cancelled_while_held(&actual, &mut gate).await;
    let pending = match tokio::time::timeout(
        Duration::from_secs(1),
        actual
            .connection
            .drain_cleanup(tokio::time::Instant::now() + Duration::from_millis(50)),
    )
    .await
    .unwrap()
    {
        Err(pending) => pending,
        Ok(()) => panic!("actual held handle cannot already be joined"),
    };
    assert_eq!(pending.retained_handles(), 1);
    assert_eq!(attempt.snapshot().owned_handles(), 1);
    actual.connection.close();
    let capacity = actual.capacity.clone();
    let observer = actual.observer.clone();
    // The actual connection can disappear; SAME pending owner must retain the
    // actual join and precharged cleanup association across this drop.
    drop(actual.connection);
    assert_eq!(pending.retained_handles(), 1);
    assert_eq!(capacity.usage().active_workers(), 1);
    assert!(
        capacity.usage().metadata_bytes() > 0,
        "actual pending owner retains precharged cleanup association across connection drop"
    );
    gate.release();
    tokio::time::timeout(WAIT, async {
        while attempt.snapshot().returned_error() != 1 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(capacity.usage().active_workers(), 0);
    assert_eq!(pending.retained_handles(), 1);
    assert_eq!(attempt.snapshot().joined_ok(), 0);
    assert!(
        capacity.usage().metadata_bytes() > 0,
        "completed but unjoined pending owner still retains actual cleanup metadata charge"
    );
    assert!(
        pending
            .drain(tokio::time::Instant::now() + WAIT)
            .await
            .is_ok()
    );
    assert_joined_error(&attempt);
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
    assert_eq!(observer.snapshot().retained_bytes(), 0);
    assert_eq!(observer.snapshot().retained_capacity(), 0);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn completed_cleanup_handle_stays_owned_and_blocks_same_connection_reuse_until_drain() {
    let fixture = Fixture::new(RECORD);
    let actual = Actual::new(&fixture);
    let mut gate = Gate::new();
    let attempt = cancelled_while_held(&actual, &mut gate).await;
    gate.release();
    tokio::time::timeout(WAIT, async {
        while attempt.snapshot().returned_error() != 1 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    let snapshot = attempt.snapshot();
    assert_eq!(snapshot.owned_handles(), 1);
    assert_eq!(snapshot.joined_ok(), 0);
    assert_eq!(snapshot.dropped_unjoined(), 0);
    assert_eq!(actual.capacity.usage().active_workers(), 0);
    assert!(
        actual.capacity.usage().metadata_bytes() > 0,
        "completed retained handle still owns precharged cleanup association until actual drain"
    );
    assert_eq!(
        actual.capacity.usage().captures(),
        1,
        "the SAME captured slot bounds the still-owned cleanup attempt"
    );
    assert!(matches!(
        actual
            .connection
            .start_offered_provider(offer(&actual), CaptureScope::Complete),
        Err(CaptureError::ActiveCapture)
    ));
    assert!(
        actual
            .connection
            .drain_cleanup(tokio::time::Instant::now() + WAIT)
            .await
            .is_ok()
    );
    assert_joined_error(&attempt);
    actual.assert_zero();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn dropped_drain_future_returns_exact_handle_to_live_owner_without_detaching() {
    let fixture = Fixture::new(RECORD);
    let actual = Actual::new(&fixture);
    let mut gate = Gate::new();
    let attempt = cancelled_while_held(&actual, &mut gate).await;
    // Drop this drain future through a real caller timeout, while the actual
    // body remains held and its own drain deadline has not expired.
    assert!(
        tokio::time::timeout(
            Duration::from_millis(50),
            actual
                .connection
                .drain_cleanup(tokio::time::Instant::now() + WAIT)
        )
        .await
        .is_err()
    );
    assert_eq!(attempt.snapshot().owned_handles(), 1);
    assert_eq!(attempt.snapshot().dropped_unjoined(), 0);
    // A subsequent genuine drain must retrieve SAME retained ownership.
    let pending = match actual
        .connection
        .drain_cleanup(tokio::time::Instant::now() + Duration::from_millis(50))
        .await
    {
        Err(pending) => pending,
        Ok(()) => panic!("held body is not complete"),
    };
    assert_eq!(pending.retained_handles(), 1);
    gate.release();
    assert!(
        pending
            .drain(tokio::time::Instant::now() + WAIT)
            .await
            .is_ok()
    );
    assert_joined_error(&attempt);
    actual.assert_zero();
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn explicit_raw_drop_remains_incomplete_even_after_an_empty_owned_drain() {
    let fixture = Fixture::new(RECORD);
    let actual = Actual::new(&fixture);
    let mut gate = Gate::new();
    let pending = actual.start(CaptureControl::new(), gate.hook.clone());
    let attempt = pending.worker_observation();
    gate.entered().await;
    drop(pending); // abandonment, not the explicit awaited-cancel handoff
    assert_eq!(attempt.snapshot().dropped_unjoined(), 1);
    gate.release();
    zero_after_exit(&actual).await;
    assert!(
        actual
            .connection
            .drain_cleanup(tokio::time::Instant::now() + WAIT)
            .await
            .is_ok()
    );
    assert_eq!(attempt.snapshot().joined_ok(), 0);
    assert_eq!(attempt.snapshot().dropped_unjoined(), 1);
    assert!(attempt.snapshot().require_joined_cleanup().is_err());
    assert_eq!(actual.capacity.usage(), ModelCaptureUsage::default());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn observed_cleanup_metadata_capacity_refuses_before_real_spawn_or_content() {
    let fixture = Fixture::new(RECORD);
    let actual = Actual::new(&fixture);
    let capacity = HostModelCaptureCapacity::with_metadata_limit(0);
    let (connection, observer) =
        ModelCaptureConnection::new_record_observed(capacity.clone(), &actual.scope);
    assert!(matches!(
        connection.start_offered_provider(offer(&actual), CaptureScope::Complete),
        Err(CaptureError::Capacity)
    ));
    assert_eq!(actual.scope.snapshot().workers().scheduled(), 0);
    let reads = actual.scope.snapshot();
    assert_eq!(
        reads
            .reads()
            .counts_for(&actual.record)
            .unwrap()
            .content_attempts(),
        0
    );
    assert_eq!(
        reads
            .reads()
            .counts_for(&actual.primary)
            .unwrap()
            .content_attempts(),
        0
    );
    assert_eq!(observer.snapshot().retained_bytes(), 0);
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

struct Listener(Option<tokio::task::JoinHandle<Result<(), crate::error::CliError>>>);
impl Drop for Listener {
    fn drop(&mut self) {
        if let Some(task) = &self.0 {
            task.abort();
        }
    }
}
async fn exchange(
    socket: &mut tokio_tungstenite::WebSocketStream<
        tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
    >,
    id: u64,
    method: &str,
    params: Value,
) -> Value {
    tokio::time::timeout(WAIT, async {
        socket
            .send(Message::Text(
                json!({"jsonrpc":"2.0","id":id,"method":method,"params":params})
                    .to_string()
                    .into(),
            ))
            .await
            .unwrap();
        loop {
            match socket.next().await.unwrap().unwrap() {
                Message::Text(text) => {
                    let reply: Value = serde_json::from_str(&text).unwrap();
                    assert_eq!(reply["id"], id);
                    return reply;
                }
                Message::Ping(_) | Message::Pong(_) => {}
                message => panic!("unexpected actual frame: {message:?}"),
            }
        }
    })
    .await
    .unwrap()
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn real_authenticated_socket_disconnect_hands_off_actual_dispatch_before_future_drop() {
    let fixture = Fixture::new(RECORD);
    let actual = Actual::new(&fixture);
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(fixture.root.join(".morphir/out/compile.lock"))
        .unwrap();
    fs2::FileExt::lock_exclusive(&lock).unwrap();
    let source = actual
        ._startup
        .workspace_provider()
        .initial_sources()
        .pop()
        .unwrap();
    let project = project_key(&source, ".");
    let source: Value = serde_json::to_value(source).unwrap();
    let (mut host, _records) = BoundUiHost::bind_record_observed(
        "same-spelling-session".into(),
        actual._startup.capabilities(),
        Some(actual._startup.originals_provider()),
        &actual.scope,
    )
    .await
    .unwrap();
    let cleanup = host.take_capture_cleanup().unwrap();
    assert_eq!(cleanup.retained_handles(), 0);
    let usage = host.model_originals_observer();
    let base = host.base_url();
    let launch = host.launch_url();
    let mut listener = Listener(Some(tokio::spawn(host.serve())));
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();
    let response = tokio::time::timeout(WAIT, client.get(launch).send())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::SEE_OTHER);
    let cookie = response.headers()["set-cookie"]
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap();
    let mut request = format!("{}/rpc", base.replace("http://", "ws://"))
        .into_client_request()
        .unwrap();
    request
        .headers_mut()
        .insert("origin", base.parse().unwrap());
    request
        .headers_mut()
        .insert("cookie", cookie.parse().unwrap());
    let (mut socket, _) = tokio::time::timeout(WAIT, connect_async(request))
        .await
        .unwrap()
        .unwrap();
    assert_eq!(
        exchange(
            &mut socket,
            1,
            "morphir.session.initialize",
            json!({"protocolVersion":1,"sessionId":"same-spelling-session"})
        )
        .await["result"]["protocolVersion"],
        1
    );
    let opened = exchange(
        &mut socket,
        2,
        "morphir.workspace.open",
        json!({"source":source}),
    )
    .await;
    assert!(
        opened["result"]["snapshot"]["projects"]
            .as_array()
            .unwrap()
            .iter()
            .any(|p| p["id"] == project)
    );
    socket.send(Message::Text(json!({"jsonrpc":"2.0","id":3,"method":"morphir.model-originals.capture","params":{"contractVersion":"0.1.0-draft.1","source":{"providerId":source["providerId"],"locator":source["locator"]},"projectId":project,"scope":"complete","semantic":"none"}}).to_string().into())).await.unwrap();
    tokio::time::timeout(WAIT, async {
        while actual.scope.snapshot().workers().started() != 1 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(usage.usage().active_workers(), 1);
    assert_eq!(
        actual
            .scope
            .snapshot()
            .reads()
            .counts_for(&actual.record)
            .unwrap()
            .content_attempts(),
        0
    );
    socket.close(None).await.unwrap();
    drop(socket);
    // Only the actual completed handoff inserts a typed owned handle into this
    // opaque controller. Active/body/credit counts do not stand in for it.
    tokio::time::timeout(WAIT, async {
        while cleanup.retained_handles() != 1 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(actual.scope.snapshot().workers().owned_handles(), 1);
    assert_eq!(actual.scope.snapshot().workers().dropped_unjoined(), 0);
    assert_eq!(actual.scope.snapshot().workers().joined_ok(), 0);
    let task = listener.0.take().unwrap();
    task.abort();
    assert!(task.await.unwrap_err().is_cancelled());
    // Host control survives listener/connection shutdown with the SAME handle.
    assert_eq!(cleanup.retained_handles(), 1);
    fs2::FileExt::unlock(&lock).unwrap();
    assert!(
        cleanup
            .drain(tokio::time::Instant::now() + WAIT)
            .await
            .is_ok()
    );
    let workers = actual.scope.snapshot().workers();
    assert_eq!(workers.returned_error(), 1);
    assert_eq!(workers.joined_ok(), 1);
    assert_eq!(workers.owned_handles(), 0);
    assert_eq!(workers.dropped_unjoined(), 0);
    workers.require_joined_cleanup().unwrap();
    assert_eq!(usage.usage(), ModelCaptureUsage::default());
    assert_eq!(
        actual
            .scope
            .snapshot()
            .reads()
            .counts_for(&actual.record)
            .unwrap()
            .content_attempts(),
        0
    );
    // No Ready/captureId was issued, no raw record was read, and no synthetic
    // observer slot/controller/connection/capture identity was constructed.
}

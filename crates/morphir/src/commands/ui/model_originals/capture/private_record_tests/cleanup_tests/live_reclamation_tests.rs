//! Child of private_record_tests::cleanup_tests. Genuine host/provider effects.
//! Source-first control. No reaper, new production task, quota or issuer.
use super::*;
use crate::commands::ui::{
    model_originals::{CaptureWorkerTestHook, lifecycle::MAX_HOST_CAPTURES},
    server::HostObservationBinding,
    socket_tasks::{SocketCleanup, SocketDrainOutcome},
};
use std::sync::{Arc, Condvar};
type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;

enum GateState {
    Cycling { entered: usize, released: usize },
    Stopped,
}
struct RepeatedGate {
    state: Mutex<GateState>,
    wake: Condvar,
}
impl RepeatedGate {
    fn enter(&self) {
        let mut state = self.state.lock().unwrap();
        let generation = match &mut *state {
            GateState::Cycling { entered, .. } => {
                *entered = entered.checked_add(1).unwrap();
                *entered
            }
            GateState::Stopped => return,
        };
        let (state, timeout) = self.wake.wait_timeout_while(state, WAIT, |state| {
            matches!(state, GateState::Cycling { released, .. } if *released < generation)
        }).unwrap();
        assert!(
            !timeout.timed_out() || matches!(*state, GateState::Stopped),
            "test must release its genuine worker"
        );
    }
    async fn entered(&self, expected: usize) {
        loop {
            if matches!(*self.state.lock().unwrap(), GateState::Cycling { entered, .. } if entered >= expected)
            {
                return;
            }
            tokio::task::yield_now().await;
        }
    }
    fn release(&self, generation: usize) {
        if let GateState::Cycling { released, .. } = &mut *self.state.lock().unwrap() {
            *released = generation;
        }
        self.wake.notify_all();
    }
    fn stop(&self) {
        *self.state.lock().unwrap() = GateState::Stopped;
        self.wake.notify_all();
    }
}
struct ReleaseOnDrop(Arc<RepeatedGate>);
impl Drop for ReleaseOnDrop {
    fn drop(&mut self) {
        self.0.stop();
    }
}

async fn connected(base: &str, cookie: &str, source: &Value, project: &str) -> Socket {
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
            json!({"protocolVersion":1,"sessionId":"live-capture-reclamation"})
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
            .any(|row| row["id"] == project)
    );
    socket
}
async fn capture_response(socket: &mut Socket) -> Value {
    loop {
        match socket.next().await.unwrap().unwrap() {
            Message::Text(text) => {
                let response: Value = serde_json::from_str(&text).unwrap();
                assert_eq!(response["id"], 3);
                return response;
            }
            Message::Ping(_) | Message::Pong(_) => {}
            other => panic!("unexpected capture frame: {other:?}"),
        }
    }
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn same_running_authenticated_host_reclaims_65_cancelled_ended_provider_attempts() {
    let fixture = Fixture::new(RECORD);
    assert_eq!(
        MAX_HOST_CAPTURES, 64,
        "existing READY saturation limit stays fixed"
    );
    // Explicit observation permissions cover65 real attempts/connections. These
    // do not modify the host's default64 capture slots or one-worker limit.
    let scope = HostSourceObservationScope::bind_native_ui(
        &fixture.held(),
        &fixture.root,
        ReadLimits::new(1_000_000, 1_000_000, 134_217_728, 8).unwrap(),
        WorkerObservationLimits::new(128, 32768).unwrap(),
        HostObservationLimits::new(8192).unwrap(),
    )
    .unwrap();
    let mut files = Vec::new();
    for path in [
        ".morphir/out/compile.json",
        ".morphir/out/compile.dest/model.json",
        ".morphir/out/compile.dest/secret",
    ] {
        files.push(
            scope
                .source_scope()
                .register_file(&fixture.held(), Path::new(path))
                .unwrap(),
        );
    }
    let startup = prepare_native_ui_observed(
        fixture.held(),
        &fixture.root,
        "live-capture-reclamation",
        crate::home::MorphirHome::resolve_from(Some(fixture.root.join("home").as_os_str()), None)
            .unwrap(),
        ConfigLoadOptions::default(),
        OutOverrides::default(),
        &scope,
    )
    .unwrap();
    let selected = startup
        .workspace_provider()
        .initial_sources()
        .pop()
        .unwrap();
    let project = project_key(&selected, ".");
    let source = serde_json::to_value(selected).unwrap();
    let gate = Arc::new(RepeatedGate {
        state: Mutex::new(GateState::Cycling {
            entered: 0,
            released: 0,
        }),
        wake: Condvar::new(),
    });
    let _release = ReleaseOnDrop(gate.clone());
    let callback = gate.clone();
    let hook = CaptureWorkerTestHook::new(Arc::new(move || callback.enter()));
    let mut host = BoundUiHost::bind_ordinary_with_capture_hook(
        "live-capture-reclamation".into(),
        startup.capabilities(),
        Some(startup.originals_provider()),
        HostObservationBinding::Source(scope.lease()),
        hook,
    )
    .await
    .unwrap();
    let base = host.base_url();
    let launch = host.launch_url();
    let usage = host.model_originals_observer();
    let mut captures = host.take_capture_cleanup().unwrap().into_pending();
    let mut sockets = SocketCleanup::Pending(host.take_socket_cleanup().unwrap());
    let mut listener = Listener(Some(tokio::spawn(host.serve())));
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();
    let response = client.get(launch).send().await.unwrap();
    assert_eq!(response.status(), reqwest::StatusCode::SEE_OTHER);
    let cookie = response.headers()["set-cookie"]
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap()
        .to_owned();
    drop(response);
    drop(client);
    let mut starts = Vec::new();
    let mut refusal = None;
    let journey = tokio::time::timeout(Duration::from_secs(60), async {
        for generation in 1..=MAX_HOST_CAPTURES + 1 {
            let mut socket = connected(&base, &cookie, &source, &project).await;
            socket.send(Message::Text(json!({"jsonrpc":"2.0","id":3,"method":"morphir.model-originals.capture","params":{"contractVersion":"0.1.0-draft.1","source":{"providerId":source["providerId"],"locator":source["locator"]},"projectId":project,"scope":"complete","semantic":"none"}}).to_string().into())).await.unwrap();
            let entered = tokio::select! {
                () = gate.entered(generation) => true,
                response = capture_response(&mut socket) => { refusal = Some(response); false },
            };
            if !entered {
                let _ = socket.close(None).await;
                drop(socket);
                break;
            }
            // Body entry may race TrackedJoin installation. Wait for actual
            // scheduled/owned-or-joined accounting before closing this peer.
            tokio::time::timeout(WAIT, async {
                loop {
                    let snapshot = scope.snapshot();
                    let workers = snapshot.workers();
                    if workers.scheduled() == generation as u64
                        && workers.owned_handles().checked_add(workers.joined_ok()) == Some(generation as u64) {
                        break;
                    }
                    tokio::task::yield_now().await;
                }
            }).await.unwrap();
            let snapshot = scope.snapshot();
            let workers = snapshot.workers();
            starts.push((generation, workers.joined_ok(), workers.owned_handles(), workers.dropped_unjoined(), usage.usage().captures()));
            socket.close(None).await.unwrap();
            drop(socket);
            // This is a handoff/final-destruction premise, NOT a join proof.
            // No cleanup drain or host stop is invoked between starts.
            tokio::time::timeout(WAIT, async {
                while !sockets.owner_mut().unwrap().tasks_finished() {
                    tokio::task::yield_now().await;
                }
            }).await.unwrap();
            gate.release(generation);
            tokio::time::timeout(WAIT, async {
                while scope.snapshot().workers().returned_error() != generation as u64
                    || usage.usage().active_workers() != 0 {
                    tokio::task::yield_now().await;
                }
            }).await.unwrap();
        }
    }).await;
    let before_cleanup = scope.snapshot();
    gate.stop();
    // Intended start/reclamation assertions occur only after actual cleanup.
    sockets.stop_accepting_upgrades();
    let task = listener.0.take().unwrap();
    task.abort();
    let listener_join = task.await;
    let socket_join = sockets.drain(tokio::time::Instant::now() + WAIT).await;
    let capture_join = captures
        .drain_retained(tokio::time::Instant::now() + WAIT)
        .await;
    let after_cleanup = scope.snapshot();
    drop(captures);
    drop(sockets);
    drop(startup);
    let zero = tokio::time::timeout(WAIT, async {
        while usage.usage() != ModelCaptureUsage::default() {
            tokio::task::yield_now().await;
        }
    })
    .await;
    assert!(listener_join.unwrap_err().is_cancelled());
    assert_eq!(socket_join, SocketDrainOutcome::Joined);
    capture_join.unwrap();
    zero.unwrap();
    after_cleanup.workers().require_joined_cleanup().unwrap();
    assert_eq!(after_cleanup.workers().dropped_unjoined(), 0);
    for file in &files {
        let counts = after_cleanup.reads().counts_for(file).unwrap();
        assert_eq!(
            counts.content_attempts(),
            0,
            "cancelled before provider content effects"
        );
        assert_eq!(counts.read_calls(), 0);
        assert_eq!(counts.returned_bytes(), 0);
    }
    assert!(journey.is_ok(), "bounded real host journey");
    assert_eq!(
        starts.len(),
        MAX_HOST_CAPTURES + 1,
        "same live host must accept actual attempt65; refusal={refusal:?}"
    );
    assert!(
        refusal.is_none(),
        "no invented successful response: {refusal:?}"
    );
    for (generation, joined, owned, dropped, slots) in starts {
        assert_eq!(
            joined,
            generation as u64 - 1,
            "each prior actual join before next work"
        );
        assert_eq!(owned, 1);
        assert_eq!(dropped, 0);
        assert_eq!(
            slots, 1,
            "prior result/slot disposal precedes new reservation"
        );
    }
    assert_eq!(
        before_cleanup.workers().joined_ok(),
        MAX_HOST_CAPTURES as u64
    );
    assert_eq!(before_cleanup.workers().owned_handles(), 1);
    assert_eq!(
        after_cleanup.workers().joined_ok(),
        MAX_HOST_CAPTURES as u64 + 1
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn start_skips_actual_draining_then_cancel_restores_same_join() {
    let fixture = Fixture::new(RECORD);
    let mut actual = Actual::new(&fixture);
    let registry =
        super::super::super::super::lifecycle::CleanupRegistry::new(&actual.capacity).unwrap();
    actual.connection.attach_cleanup_registry(&registry);
    let mut cleanup = registry.control().into_pending();
    let mut gate = Gate::new();
    let attempt = cancelled_while_held(&actual, &mut gate).await;
    let original_id = cleanup.actual_task_id().unwrap();
    let refusal;
    {
        let drain = cleanup.drain_retained(tokio::time::Instant::now() + WAIT);
        tokio::pin!(drain);
        assert!(drain.as_mut().now_or_never().is_none());
        gate.release();
        tokio::time::timeout(WAIT, async {
            while attempt.snapshot().returned_error() != 1 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        // A completed body must not let start steal the actual join still
        // checked out by the borrowed drain. Scope exit cancels that drain.
        refusal = actual
            .connection
            .start_offered_provider(offer(&actual), CaptureScope::Complete);
    }
    let restored_id = cleanup.actual_task_id();
    let before = attempt.snapshot();
    let drained = cleanup
        .drain_retained(tokio::time::Instant::now() + WAIT)
        .await;
    let after = attempt.snapshot();
    drop(cleanup);
    drop(registry);
    assert!(matches!(refusal, Err(CaptureError::ActiveCapture)));
    assert_eq!(restored_id, Some(original_id));
    assert_eq!(before.owned_handles(), 1);
    assert_eq!(before.joined_ok(), 0);
    assert_eq!(before.dropped_unjoined(), 0);
    drained.unwrap();
    assert_eq!(after.joined_ok(), 1);
    assert_eq!(after.owned_handles(), 0);
    assert_eq!(after.dropped_unjoined(), 0);
    after.require_joined_cleanup().unwrap();
    actual
        .scope
        .snapshot()
        .workers()
        .require_joined_cleanup()
        .unwrap();
    let capacity = actual.capacity.clone();
    let observer = actual.observer.clone();
    drop(actual); // Release the connection's SAME registry infrastructure credit.
    let raw = observer.snapshot();
    assert_eq!(raw.retained_bytes(), 0);
    assert_eq!(raw.retained_capacity(), 0);
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn live_start_cannot_steal_completed_awaited_business_result() {
    let fixture = Fixture::new(RECORD);
    let mut actual = Actual::new(&fixture);
    let registry =
        super::super::super::super::lifecycle::CleanupRegistry::new(&actual.capacity).unwrap();
    actual.connection.attach_cleanup_registry(&registry);
    let mut cleanup = registry.control().into_pending();
    let pending = actual.start(CaptureControl::new(), Arc::new(Noop));
    let attempt = pending.worker_observation();
    finished(&pending).await; // actual is_finished premise only, never join proof
    let before_id = cleanup.actual_task_id();
    let refused = actual
        .connection
        .start_offered_provider(offer(&actual), CaptureScope::Complete);
    let before_wait = attempt.snapshot();
    let ready = pending.wait().await.unwrap().ready().unwrap();
    actual.connection.release(&ready).unwrap();
    let drained = cleanup
        .drain_retained(tokio::time::Instant::now() + WAIT)
        .await;
    drop(cleanup);
    drop(registry);
    assert!(before_id.is_some());
    assert!(matches!(refused, Err(CaptureError::ActiveCapture)));
    assert_eq!(before_wait.owned_handles(), 1);
    assert_eq!(before_wait.joined_ok(), 0);
    assert_eq!(before_wait.dropped_unjoined(), 0);
    drained.unwrap();
    assert_eq!(attempt.snapshot().joined_ok(), 1);
    actual
        .scope
        .snapshot()
        .workers()
        .require_joined_cleanup()
        .unwrap();
    let capacity = actual.capacity.clone();
    let observer = actual.observer.clone();
    drop(actual); // Release the connection's SAME registry infrastructure credit.
    let raw = observer.snapshot();
    assert_eq!(raw.retained_bytes(), 0);
    assert_eq!(raw.retained_capacity(), 0);
    assert_eq!(capacity.usage(), ModelCaptureUsage::default());
}

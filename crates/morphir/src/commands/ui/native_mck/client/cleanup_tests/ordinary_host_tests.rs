//! Host-owned cleanup does not depend on private record or worker observation.
use super::*;
use crate::commands::ui::{
    server::HostObservationBinding,
    socket_tasks::{SocketCleanup, SocketCleanupError, SocketDrainOutcome},
};

enum Lane {
    Disabled,
    Source,
}
enum Stop {
    Abort,
    Panic,
}
struct Listener(Option<tokio::task::JoinHandle<Result<(), crate::error::CliError>>>);
impl Drop for Listener {
    fn drop(&mut self) {
        if let Some(actual) = &self.0 {
            actual.abort();
        }
    }
}
pub(super) async fn exchange(socket: &mut Socket, id: u64, method: &str, params: Value) -> Value {
    socket
        .send(Message::Text(
            json!({"jsonrpc":"2.0","id":id,"method":method,"params":params})
                .to_string()
                .into(),
        ))
        .await
        .unwrap();
    tokio::time::timeout(WAIT, async {
        loop {
            match socket.next().await.unwrap().unwrap() {
                Message::Text(text) => {
                    let value: Value = serde_json::from_str(&text).unwrap();
                    assert_eq!(value["id"], id);
                    return value;
                }
                Message::Ping(_) | Message::Pong(_) => {}
                other => panic!("unexpected actual frame: {other:?}"),
            }
        }
    })
    .await
    .unwrap()
}
async fn exercise(lane: Lane, stop: Stop) {
    let fixture = Fixture::new();
    let mut gate = HeldCapture::new();
    let scope = HostSourceObservationScope::bind_native_ui(
        &fixture.held(),
        &fixture.root,
        ReadLimits::new(1_000_000, 1_000_000, 134_217_728, 8).unwrap(),
        WorkerObservationLimits::new(8, 1024).unwrap(),
        HostObservationLimits::new(1024).unwrap(),
    )
    .unwrap();
    let record = scope
        .source_scope()
        .register_file(&fixture.held(), Path::new(".morphir/out/compile.json"))
        .unwrap();
    let prepared = prepare_native_ui_observed(
        fixture.held(),
        &fixture.root,
        "ordinary-host-cleanup",
        crate::home::MorphirHome::resolve_from(Some(fixture.root.join("home").as_os_str()), None)
            .unwrap(),
        ConfigLoadOptions::default(),
        OutOverrides::default(),
        &scope,
    )
    .unwrap();
    let selected = prepared
        .workspace_provider()
        .initial_sources()
        .pop()
        .unwrap();
    let project = project_key(&selected, ".");
    let source = serde_json::to_value(selected).unwrap();
    let observation = match lane {
        Lane::Disabled => HostObservationBinding::Disabled,
        Lane::Source => HostObservationBinding::Source(scope.lease()),
    };
    let mut host = BoundUiHost::bind_ordinary_with_capture_hook(
        "ordinary-host-cleanup".into(),
        prepared.capabilities(),
        Some(prepared.originals_provider()),
        observation,
        gate.hook.clone(),
    )
    .await
    .unwrap();
    let base = host.base_url();
    let launch = host.launch_url();
    let usage = host.model_originals_observer();
    // Absence is retained as an actual API refusal in the pre-fix baseline.
    // It never manufactures an empty successful cleanup owner.
    let mut captures = host
        .take_capture_cleanup()
        .ok()
        .map(|owner| owner.into_pending());
    let mut sockets = SocketCleanup::Pending(host.take_socket_cleanup().unwrap());
    let mut listener = Listener(Some(tokio::spawn(host.serve())));
    let response = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap()
        .get(launch)
        .send()
        .await
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
    let (mut socket, _) = connect_async_with_config(request, None, false)
        .await
        .unwrap();
    assert_eq!(
        exchange(
            &mut socket,
            1,
            "morphir.session.initialize",
            json!({"protocolVersion":1,"sessionId":"ordinary-host-cleanup"})
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
            .any(|item| item["id"] == project)
    );
    socket.send(Message::Text(json!({"jsonrpc":"2.0","id":3,"method":"morphir.model-originals.capture","params":{"contractVersion":"0.1.0-draft.1","source":{"providerId":source["providerId"],"locator":source["locator"]},"projectId":project,"scope":"complete","semantic":"none"}}).to_string().into())).await.unwrap();
    tokio::time::timeout(WAIT, gate.entered.take().unwrap())
        .await
        .unwrap()
        .unwrap();
    if matches!(lane, Lane::Source) {
        tokio::time::timeout(WAIT, async {
            while scope.snapshot().workers().owned_handles() != 1 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
    }
    let before_id = if let Some(owner) = &captures {
        tokio::time::timeout(WAIT, async {
            loop {
                if let Some(id) = owner.actual_task_id() {
                    break id;
                }
                tokio::task::yield_now().await;
            }
        })
        .await
        .ok()
    } else {
        None
    };
    if matches!(stop, Stop::Panic) {
        let owner = sockets.owner_mut().unwrap();
        owner.panic_tasks();
        tokio::time::timeout(WAIT, async {
            while !owner.tasks_finished() {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
    }
    let socket_result = sockets.drain(Instant::now() + WAIT).await;
    let held = captures
        .as_ref()
        .map(PendingCaptureCleanup::retained_handles);
    let before = usage.usage();
    let source_before = scope.snapshot();
    let bounded = match &mut captures {
        Some(owner) => Some(
            owner
                .drain_retained(Instant::now() + Duration::from_millis(20))
                .await,
        ),
        None => None,
    };
    let after_timeout_id = captures
        .as_ref()
        .and_then(PendingCaptureCleanup::actual_task_id);
    // Release and join all actual owners before assertions can fail.
    gate.release();
    let drained = match &mut captures {
        Some(owner) => Some(owner.drain_retained(Instant::now() + WAIT).await),
        None => None,
    };
    let source_after = scope.snapshot();
    let actual_listener = listener.0.take().unwrap();
    actual_listener.abort();
    let listener_join = actual_listener.await;
    drop(socket);
    drop(captures);
    drop(sockets);
    drop(prepared);
    let zero = tokio::time::timeout(WAIT, async {
        while usage.usage() != ModelCaptureUsage::default() {
            tokio::task::yield_now().await;
        }
    })
    .await;
    assert_eq!(
        socket_result,
        match stop {
            Stop::Abort => SocketDrainOutcome::Joined,
            Stop::Panic => SocketDrainOutcome::JoinedWithFault(SocketCleanupError::TaskPanicked),
        }
    );
    assert!(listener_join.unwrap_err().is_cancelled());
    assert!(
        before_id.is_some(),
        "ordinary host must own the actual provider JoinHandle"
    );
    assert_eq!(
        after_timeout_id, before_id,
        "borrowed timeout retains SAME actual task"
    );
    assert_eq!(held, Some(1));
    assert_eq!(before.active_workers(), 1);
    assert_eq!(before.captures(), 1);
    assert!(before.metadata_bytes() > 0);
    assert_eq!(
        source_before
            .reads()
            .counts_for(&record)
            .unwrap()
            .content_attempts(),
        0
    );
    assert!(matches!(bounded, Some(Err(_))));
    assert!(matches!(drained, Some(Ok(()))));
    if matches!(lane, Lane::Source) {
        assert_eq!(source_before.workers().owned_handles(), 1);
        assert_eq!(source_before.workers().dropped_unjoined(), 0);
        assert_eq!(source_after.workers().joined_ok(), 1);
        assert_eq!(source_after.workers().owned_handles(), 0);
        assert_eq!(source_after.workers().dropped_unjoined(), 0);
    }
    assert!(zero.is_ok());
    assert_eq!(usage.usage(), ModelCaptureUsage::default());
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn disabled_host_abort_retains_actual_worker_until_join() {
    exercise(Lane::Disabled, Stop::Abort).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn disabled_host_panic_retains_actual_worker_until_join() {
    exercise(Lane::Disabled, Stop::Panic).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn source_only_host_abort_retains_actual_worker_until_join() {
    exercise(Lane::Source, Stop::Abort).await;
}
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn source_only_host_panic_retains_actual_worker_until_join() {
    exercise(Lane::Source, Stop::Panic).await;
}

//! The ordinary main shutdown path keeps ownership through the real body join.
use super::ordinary_host_tests::exchange;
use super::*;
use crate::commands::ui::server::HostObservationBinding;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn main_shutdown_retains_worker_and_preserves_signal_error_until_join() {
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
        "ordinary-main-shutdown",
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
    let host = BoundUiHost::bind_ordinary_with_capture_hook(
        "ordinary-main-shutdown".into(),
        prepared.capabilities(),
        Some(prepared.originals_provider()),
        HostObservationBinding::Source(scope.lease()),
        gate.hook.clone(),
    )
    .await
    .unwrap();
    let base = host.base_url();
    let launch = host.launch_url();
    let usage = host.model_originals_observer();
    let (send, receive) = tokio::sync::oneshot::channel();
    let mut serving = tokio::spawn(crate::commands::ui::serve_until_shutdown(
        host,
        async move { receive.await.unwrap() },
    ));
    let response = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap()
        .get(launch)
        .send()
        .await
        .unwrap();
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
    exchange(
        &mut socket,
        1,
        "morphir.session.initialize",
        json!({"protocolVersion":1,"sessionId":"ordinary-main-shutdown"}),
    )
    .await;
    exchange(
        &mut socket,
        2,
        "morphir.workspace.open",
        json!({"source":source}),
    )
    .await;
    socket.send(Message::Text(json!({"jsonrpc":"2.0","id":3,"method":"morphir.model-originals.capture","params":{"contractVersion":"0.1.0-draft.1","source":{"providerId":source["providerId"],"locator":source["locator"]},"projectId":project,"scope":"complete","semantic":"none"}}).to_string().into())).await.unwrap();
    gate.entered(&scope).await;
    send.send(Err(std::io::Error::other("actual-shutdown-error")))
        .unwrap();
    // Actual peer closure shows stop reached the live socket while its provider
    // body remains held; it is not used as a provider or HTTP driver join proof.
    let closed = tokio::time::timeout(WAIT, socket.next()).await;
    let pending = std::future::poll_fn(|cx| {
        std::task::Poll::Ready(std::pin::Pin::new(&mut serving).poll(cx).is_pending())
    })
    .await;
    let before = scope.snapshot();
    gate.release();
    let finished = tokio::time::timeout(WAIT, &mut serving).await;
    if finished.is_err() {
        serving.abort();
        let _ = serving.await;
    }
    let after = scope.snapshot();
    drop(socket);
    drop(prepared);
    let zero = tokio::time::timeout(WAIT, async {
        while usage.usage() != ModelCaptureUsage::default() {
            tokio::task::yield_now().await;
        }
    })
    .await;
    assert!(closed.is_ok());
    assert!(
        pending,
        "main shutdown must not return/drop its held provider join"
    );
    assert_eq!(before.workers().owned_handles(), 1);
    assert_eq!(before.workers().joined_ok(), 0);
    assert_eq!(before.workers().dropped_unjoined(), 0);
    assert_eq!(
        before
            .reads()
            .counts_for(&record)
            .unwrap()
            .content_attempts(),
        0
    );
    let error = finished.unwrap().unwrap().unwrap_err();
    match error {
        crate::error::CliError::FileSystem { error } => {
            assert_eq!(error.kind(), std::io::ErrorKind::Other);
            assert_eq!(error.to_string(), "actual-shutdown-error");
        }
        other => panic!("first actual signal error replaced during cleanup: {other:?}"),
    }
    assert_eq!(after.workers().joined_ok(), 1);
    assert_eq!(after.workers().owned_handles(), 0);
    assert_eq!(after.workers().dropped_unjoined(), 0);
    assert_eq!(
        after
            .reads()
            .counts_for(&record)
            .unwrap()
            .content_attempts(),
        0
    );
    assert!(zero.is_ok());
    assert_eq!(usage.usage(), ModelCaptureUsage::default());
}

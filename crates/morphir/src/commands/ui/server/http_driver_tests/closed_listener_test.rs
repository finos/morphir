//! Child of server::http_driver_tests. Actual stop/accept ordering.
use super::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn stopped_registry_refuses_new_http_peer_and_listener_returns_cleanly() {
    let capacity = HostModelCaptureCapacity::default();
    let (tasks, mut owner) = SocketTaskRegistry::new(&capacity).unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let address = listener.local_addr().unwrap();
    let router = Router::new().route("/", get(|| async { "actual-http" }));
    let mut listener = ListenerTask(Some(tokio::spawn(serve_connections(
        listener,
        router,
        tasks.clone(),
    ))));
    let mut first = timeout(WAIT, TcpStream::connect(address))
        .await
        .unwrap()
        .unwrap();
    first
        .write_all(
            format!("GET / HTTP/1.1\r\nHost: {address}\r\nConnection: keep-alive\r\n\r\n")
                .as_bytes(),
        )
        .await
        .unwrap();
    let response = http_reply(&mut first).await;
    let before = owner.actual_task_id();
    owner.stop_accepting_upgrades();
    let mut refused = timeout(WAIT, TcpStream::connect(address))
        .await
        .unwrap()
        .unwrap();
    let _write = refused
        .write_all(format!("GET / HTTP/1.1\r\nHost: {address}\r\n\r\n").as_bytes())
        .await;
    let refused = timeout(WAIT, refused.read_u8()).await;
    let after = owner.actual_task_id();
    let retained = owner.retained_tasks();
    let listener_join = timeout(WAIT, listener.0.as_mut().unwrap()).await;
    // A timed-out listener handle remains owned for explicit abort and join.
    // A terminal handle is retired exactly once, even on the OLD error branch.
    let cleanup_listener = if listener_join.is_err() {
        let actual = listener.0.take().unwrap();
        actual.abort();
        Some(timeout(WAIT, actual).await)
    } else {
        listener.0 = None;
        None
    };
    let joined = timeout(WAIT, owner.join()).await;
    drop(first);
    drop(owner);
    drop(tasks);
    let final_usage = capacity.usage();
    assert_eq!(response.0.split_whitespace().nth(1), Some("200"));
    assert!(before.is_some());
    assert_eq!(after, before);
    assert_eq!(
        retained, 1,
        "a stopped accept cannot install another driver"
    );
    assert!(
        matches!(refused, Ok(Err(error)) if matches!(error.kind(), std::io::ErrorKind::UnexpectedEof | std::io::ErrorKind::ConnectionReset))
    );
    assert!(
        matches!(listener_join, Ok(Ok(Ok(())))),
        "intentional stop is not a host fault"
    );
    assert!(cleanup_listener.is_none());
    assert_eq!(joined, Ok(SocketDrainOutcome::Joined));
    assert_eq!(final_usage, ModelCaptureUsage::default());
}

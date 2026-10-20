//! Actual malformed HTTP is a connection failure, not a sticky task failure.
use super::*;

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn malformed_http_peer_closes_without_poisoning_following_driver_or_join() {
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
    let mut malformed = timeout(WAIT, TcpStream::connect(address))
        .await
        .unwrap()
        .unwrap();
    malformed
        .write_all(b"not-an-http-request\r\n\r\n")
        .await
        .unwrap();
    let mut response = Vec::new();
    let malformed_read =
        timeout(WAIT, (&mut malformed).take(8192).read_to_end(&mut response)).await;
    let finished = timeout(WAIT, async {
        while !owner.tasks_finished() {
            tokio::task::yield_now().await;
        }
    })
    .await;
    let malformed_task = owner.actual_task_id();
    let retained = owner.retained_tasks();
    let listener_alive = !listener.0.as_ref().unwrap().is_finished();
    let mut legitimate = timeout(WAIT, TcpStream::connect(address))
        .await
        .unwrap()
        .unwrap();
    legitimate
        .write_all(
            format!("GET / HTTP/1.1\r\nHost: {address}\r\nConnection: keep-alive\r\n\r\n")
                .as_bytes(),
        )
        .await
        .unwrap();
    let legitimate_response = http_reply(&mut legitimate).await;
    owner.stop_accepting_upgrades();
    let actual_listener = listener.0.take().unwrap();
    actual_listener.abort();
    let listener_join = timeout(WAIT, actual_listener).await;
    let joined = timeout(WAIT, owner.join()).await;
    drop(malformed);
    drop(legitimate);
    drop(owner);
    drop(tasks);
    let final_usage = capacity.usage();
    // Retain the actual upstream response without inventing an exact 400
    // oracle. An upstream close with no response is also a valid refusal.
    eprintln!("actual malformed HTTP response bytes: {response:?}");
    let status = std::str::from_utf8(&response)
        .ok()
        .and_then(|value| value.split_whitespace().nth(1))
        .and_then(|value| value.parse::<u16>().ok());
    assert!(matches!(malformed_read, Ok(Ok(_))));
    assert!(response.len() < 8192, "actual EOF, not the test read bound");
    assert!(response.is_empty() || matches!(status, Some(400..=599)));
    assert!(finished.is_ok());
    assert!(malformed_task.is_some());
    assert_eq!(
        retained, 1,
        "the completed malformed driver still has a real join owner"
    );
    assert!(listener_alive);
    assert_eq!(legitimate_response.0.split_whitespace().nth(1), Some("200"));
    assert_eq!(legitimate_response.1, b"actual-http");
    assert!(matches!(listener_join, Ok(Err(error)) if error.is_cancelled()));
    assert_eq!(joined, Ok(SocketDrainOutcome::Joined));
    assert_eq!(final_usage, ModelCaptureUsage::default());
}

//! Child of server::http_driver_tests. Real TCP refusal/recovery, no fake task.
use super::*;

// The post-refusal probes return failures as data so that actual cleanup occurs
// before the intended policy assertions, even when the OLD listener exits.
async fn probe(stream: &mut TcpStream, address: SocketAddr) -> Result<String, String> {
    timeout(WAIT, async {
        stream
            .write_all(
                format!("GET / HTTP/1.1\r\nHost: {address}\r\nConnection: keep-alive\r\n\r\n")
                    .as_bytes(),
            )
            .await
            .map_err(|error| error.to_string())?;
        let mut head = Vec::new();
        while !head.ends_with(b"\r\n\r\n") {
            if head.len() >= 65_536 {
                return Err("response header bound".into());
            }
            head.push(stream.read_u8().await.map_err(|error| error.to_string())?);
        }
        let head = String::from_utf8(head).map_err(|error| error.to_string())?;
        let length = head
            .lines()
            .filter_map(|line| line.split_once(':'))
            .find(|(name, _)| name.eq_ignore_ascii_case("content-length"))
            .map_or(Ok(0), |(_, value)| {
                value
                    .trim()
                    .parse::<usize>()
                    .map_err(|error| error.to_string())
            })?;
        if length > 65_536 {
            return Err("response body bound".into());
        }
        let mut body = vec![0; length];
        stream
            .read_exact(&mut body)
            .await
            .map_err(|error| error.to_string())?;
        Ok(head)
    })
    .await
    .map_err(|_| "actual HTTP probe timeout".to_owned())?
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn actual_metadata_refusal_closes_only_new_peer_and_same_listener_recovers() {
    // A finite test-only existing ledger bound, not a new production default.
    let bound = 1024 * 1024;
    let capacity = HostModelCaptureCapacity::with_metadata_limit(bound);
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
    let first_response = probe(&mut first, address).await.unwrap();
    let first_id = owner.actual_task_id();
    // Fill the SAME Vec's actual capacity with real held HTTP peers. This
    // establishes that peerB needs growth without assuming allocator capacity1
    // or inventing a task-slot byte size.
    let table_capacity = owner.table_capacity();
    let mut peers = vec![first];
    while owner.retained_tasks() < table_capacity {
        let mut peer = timeout(WAIT, TcpStream::connect(address))
            .await
            .unwrap()
            .unwrap();
        let response = probe(&mut peer, address).await.unwrap();
        assert_eq!(response.split_whitespace().nth(1), Some("200"));
        peers.push(peer);
    }
    let filled = owner.retained_tasks();
    let remaining = bound
        .checked_sub(capacity.usage().metadata_bytes())
        .unwrap();
    let pressure = capacity.reserve_evidence(remaining).unwrap();
    let saturated = capacity.usage().metadata_bytes();
    let mut refused_peer = timeout(WAIT, TcpStream::connect(address))
        .await
        .unwrap()
        .unwrap();
    // Request writing can race the genuine pre-driver close. Its outcome is
    // not an oracle; an actual EOF/reset before any response byte is required.
    let _write = refused_peer
        .write_all(
            format!("GET / HTTP/1.1\r\nHost: {address}\r\nConnection: keep-alive\r\n\r\n")
                .as_bytes(),
        )
        .await;
    let refused = timeout(WAIT, refused_peer.read_u8()).await;
    let same_first = owner.actual_task_id();
    let listener_alive = !listener.0.as_ref().unwrap().is_finished();
    drop(pressure);
    // Both the previously admitted peerA and a genuinely NEW peerC must work
    // after only the externally held SAME-ledger credit is released.
    let old_peer_response = probe(&mut peers[0], address).await;
    let recovered = timeout(WAIT, TcpStream::connect(address)).await;
    let (new_peer_response, new_peer) = match recovered {
        Ok(Ok(mut peer)) => {
            let response = probe(&mut peer, address).await;
            (response, Some(peer))
        }
        Ok(Err(error)) => (Err(error.to_string()), None),
        Err(_) => (Err("new peer connect timeout".into()), None),
    };
    owner.stop_accepting_upgrades();
    let actual_listener = listener.0.take().unwrap();
    actual_listener.abort();
    let listener_join = timeout(WAIT, actual_listener).await;
    let joined = timeout(WAIT, owner.join()).await;
    drop(new_peer);
    drop(refused_peer);
    drop(peers);
    drop(owner);
    drop(tasks);
    let final_usage = capacity.usage();
    assert_eq!(first_response.split_whitespace().nth(1), Some("200"));
    assert!(first_id.is_some());
    assert!(table_capacity > 0);
    assert_eq!(filled, table_capacity);
    assert_eq!(saturated, bound);
    assert!(
        matches!(refused, Ok(Err(error)) if matches!(error.kind(), std::io::ErrorKind::UnexpectedEof | std::io::ErrorKind::ConnectionReset))
    );
    assert_eq!(same_first, first_id);
    assert!(
        listener_alive,
        "one new connection's capacity refusal cannot terminate the listener"
    );
    assert!(matches!(old_peer_response, Ok(head) if head.split_whitespace().nth(1) == Some("200")));
    assert!(matches!(new_peer_response, Ok(head) if head.split_whitespace().nth(1) == Some("200")));
    assert!(matches!(listener_join, Ok(Err(error)) if error.is_cancelled()));
    assert_eq!(joined, Ok(SocketDrainOutcome::Joined));
    assert_eq!(final_usage, ModelCaptureUsage::default());
}

//! Child of model_originals::host_source_tests. Actual HTTP, no socket upgrade.
use super::*;
use crate::commands::ui::socket_tasks::SocketDrainOutcome;
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _};

async fn http_reply(stream: &mut tokio::net::TcpStream) -> (String, Vec<u8>) {
    tokio::time::timeout(WAIT, async {
        let mut head = Vec::new();
        while !head.ends_with(b"\r\n\r\n") {
            assert!(head.len() < 65_536, "bounded actual response headers");
            head.push(stream.read_u8().await.unwrap());
        }
        let head = String::from_utf8(head).unwrap();
        let length = head
            .lines()
            .filter_map(|line| line.split_once(':'))
            .find(|(name, _)| name.eq_ignore_ascii_case("content-length"))
            .map_or(0, |(_, value)| value.trim().parse::<usize>().unwrap());
        assert!(length <= 65_536, "bounded actual session response");
        let mut body = vec![0; length];
        stream.read_exact(&mut body).await.unwrap();
        (head, body)
    })
    .await
    .unwrap()
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn authenticated_keepalive_driver_stays_owned_after_listener_join() {
    let fixture = SourceFixture::new(None);
    let scope = fixture.scope();
    let _files = register_before_discovery(&scope, &fixture);
    let startup = prepare_native_ui_observed(
        fixture.held(),
        &fixture.root,
        "observed-native-session",
        fixture.home(),
        ConfigLoadOptions::default(),
        Default::default(),
        &scope,
    )
    .unwrap();
    let mut host = BoundUiHost::bind_source_observed(
        "observed-native-session".into(),
        startup.capabilities(),
        Some(startup.originals_provider()),
        &scope,
    )
    .await
    .unwrap();
    let address = host.address();
    let base = host.base_url();
    let launch = host.launch_url();
    let mut sockets = host.take_socket_cleanup().unwrap();
    let mut captures = host.take_capture_cleanup().unwrap().into_pending();
    let usage = host.model_originals_observer();
    let listener = tokio::spawn(host.serve());
    // Remove all independent startup/provider writer aliases. The actual HTTP
    // driver/router must be the only remaining source writer after listener join.
    drop(startup);
    let mut stream = tokio::time::timeout(WAIT, tokio::net::TcpStream::connect(address))
        .await
        .unwrap()
        .unwrap();
    let launch_path = launch.strip_prefix(&base).unwrap();
    let launch_request =
        format!("GET {launch_path} HTTP/1.1\r\nHost: {address}\r\nConnection: keep-alive\r\n\r\n");
    stream.write_all(launch_request.as_bytes()).await.unwrap();
    let (launch_head, _) = http_reply(&mut stream).await;
    let cookie = launch_head
        .lines()
        .filter_map(|line| line.split_once(':'))
        .find(|(name, _)| name.eq_ignore_ascii_case("set-cookie"))
        .unwrap()
        .1
        .trim()
        .split(';')
        .next()
        .unwrap();
    let request = format!(
        "GET /api/session HTTP/1.1\r\nHost: {address}\r\nOrigin: {base}\r\nCookie: {cookie}\r\nConnection: keep-alive\r\n\r\n"
    );
    stream.write_all(request.as_bytes()).await.unwrap();
    let (session_head, body) = http_reply(&mut stream).await;
    let session: Value = serde_json::from_slice(&body).unwrap();
    sockets.stop_accepting_upgrades();
    listener.abort();
    let listener_join = tokio::time::timeout(WAIT, listener).await;
    let retained = sockets.retained_tasks();
    let (scope, early_snapshot, was_pending) = match scope.try_seal() {
        Err(pending) => (Some(pending.into_scope()), None, true),
        Ok(snapshot) => (None, Some(snapshot), false),
    };
    // Baseline axum::serve detaches the real driver. Close its actual peer and
    // wait for its source holder to retire too, before evaluating the RED.
    // Source-holder retirement alone is not labelled an HTTP task join.
    drop(stream);
    let socket_join = tokio::time::timeout(WAIT, sockets.join()).await;
    let capture_join = tokio::time::timeout(WAIT, captures.join_retained()).await;
    drop(sockets);
    drop(captures);
    let final_source = match scope {
        Some(scope) => recover(scope).await,
        None => early_snapshot.unwrap(),
    };
    let final_usage = usage.usage();
    assert_eq!(launch_head.split_whitespace().nth(1), Some("303"));
    assert_eq!(session_head.split_whitespace().nth(1), Some("200"));
    assert_eq!(session["sessionId"], "observed-native-session");
    assert!(matches!(listener_join, Ok(Err(error)) if error.is_cancelled()));
    assert_eq!(retained, 1, "the actual HTTP driver remains owned");
    assert!(
        was_pending,
        "the held actual driver prevents same-scope seal"
    );
    assert_eq!(socket_join, Ok(SocketDrainOutcome::Joined));
    assert!(matches!(capture_join, Ok(Ok(()))));
    final_source.require_source_complete().unwrap();
    assert_eq!(final_usage, ModelCaptureUsage::default());
}

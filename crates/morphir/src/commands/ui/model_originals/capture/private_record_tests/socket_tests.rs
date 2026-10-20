//! Real authenticated host/RPC path. No diagnostic API or fixture observation.
use super::*;
use crate::commands::ui::{model_originals::CaptureId, server::BoundUiHost};
use futures_util::{SinkExt as _, StreamExt as _};
use serde_json::{Value, json};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};

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
                    let value: Value = serde_json::from_str(&text).unwrap();
                    assert_eq!(value["id"], id);
                    return value;
                }
                Message::Ping(_) | Message::Pong(_) => {}
                other => panic!("unexpected actual socket frame: {other:?}"),
            }
        }
    })
    .await
    .unwrap()
}
pub(super) async fn component(actual: &Actual, run: &mut NativeOriginalRun<'_>) {
    let source = actual
        ._startup
        .workspace_provider()
        .initial_sources()
        .pop()
        .unwrap();
    let source_json = serde_json::to_value(&source).unwrap();
    let project = project_key(&source, ".");
    let (mut host, records) = BoundUiHost::bind_record_observed(
        "same-spelling-session".into(),
        actual._startup.capabilities(),
        Some(actual._startup.originals_provider()),
        &actual.scope,
    )
    .await
    .unwrap();
    let usage = host.model_originals_observer();
    let mut socket_cleanup = crate::commands::ui::socket_tasks::SocketCleanup::Pending(
        host.take_socket_cleanup().unwrap(),
    );
    let base = host.base_url();
    let launch = host.launch_url();
    let mut listener = Listener(Some(tokio::spawn(host.serve())));
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();
    let auth = tokio::time::timeout(WAIT, client.get(launch).send())
        .await
        .unwrap()
        .unwrap();
    assert_eq!(auth.status(), reqwest::StatusCode::SEE_OTHER);
    let cookie = auth.headers()["set-cookie"]
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
        json!({"source":source_json}),
    )
    .await;
    assert!(
        opened["result"]["snapshot"]["projects"]
            .as_array()
            .unwrap()
            .iter()
            .any(|item| item["id"] == project)
    );
    let baseline = usage.usage();
    assert_eq!(baseline.source_bytes(), 0);
    assert_eq!(baseline.captures(), 0);
    assert_eq!(baseline.active_workers(), 0);
    assert_eq!(
        baseline.metadata_bytes(),
        socket_cleanup.retained_metadata_bytes()
    );
    let ready = exchange(&mut socket, 3, "morphir.model-originals.capture", json!({
        "contractVersion":"0.1.0-draft.1", "source":{"providerId":source_json["providerId"],"locator":source_json["locator"]},
        "projectId":project, "scope":"complete", "semantic":"none",
    })).await;
    assert_eq!(ready["result"]["status"], "ready");
    assert_eq!(ready["result"]["inventory"]["sourceByteLength"], 111);
    assert_eq!(ready["result"]["origin"]["record"]["byteLength"], 237);
    assert_eq!(
        ready["result"]["origin"]["record"]["sha256"],
        "8002319afb380077c229776ede0d60eb8634ae49308b74420461b34a59f626d1"
    );
    let id = CaptureId::parse(ready["result"]["captureId"].as_str().unwrap()).unwrap();
    // This issued host-bound view retrieves the actual socket connection's
    // retained record. The capture ID is lookup data, never authority by itself.
    let observer = records.for_capture(&id).unwrap();
    let (pointer, capacity) = observer
        .with_ready_record(&id, |raw| {
            assert_eq!(raw.as_slice(), RECORD);
            (raw.as_ptr(), raw.capacity())
        })
        .unwrap();
    assert_eq!(observer.snapshot().retained_bytes(), 237);
    assert_eq!(usage.usage().active_workers(), 1);
    actual
        .scope
        .snapshot()
        .workers()
        .require_joined_cleanup()
        .unwrap();
    actual.assert_file_counts(237, 2);

    let foreign_fixture = Fixture::new(RECORD);
    let foreign = Actual::new(&foreign_fixture);
    let (foreign_host, foreign_records) = BoundUiHost::bind_record_observed(
        "same-spelling-session".into(),
        foreign._startup.capabilities(),
        Some(foreign._startup.originals_provider()),
        &foreign.scope,
    )
    .await
    .unwrap();
    assert!(matches!(
        foreign_records.for_capture(&id),
        Err(PrivateRecordObservationError::NotOwned)
    ));
    drop(foreign_host);
    assert_eq!(observer.snapshot().retained_bytes(), 237);

    let ticket = observer
        .with_ready_record(&id, |raw| run.prepare_private_record_adoption(raw))
        .unwrap()
        .unwrap();
    assert_eq!(ticket.usage().reserved_bytes(), capacity as u64);
    let data = observer.take(&id).unwrap().adopt(ticket).unwrap();
    assert_eq!(utf8(&data).as_bytes(), RECORD);
    assert_eq!(utf8(&data).as_ptr(), pointer);
    assert_eq!(observer.snapshot().retained_bytes(), 0);
    assert_eq!(observer.snapshot().retained_capacity(), 0);
    assert_eq!(usage.usage().active_workers(), 0);
    let released = exchange(
        &mut socket,
        4,
        "morphir.model-originals.release",
        json!({"contractVersion":"0.1.0-draft.1","captureId":id.as_str()}),
    )
    .await;
    assert_eq!(released["result"]["status"], "released");
    assert!(
        records.for_capture(&id).is_err(),
        "retired association is removed, never a live tombstone"
    );
    assert!(observer.with_ready_record(&id, |_| ()).is_err());
    assert_eq!(usage.usage(), baseline);
    drop(data);
    socket.close(None).await.unwrap();
    drop(socket);
    socket_cleanup.stop_accepting_upgrades();
    let task = listener.0.take().unwrap();
    task.abort();
    assert!(
        task.await.unwrap_err().is_cancelled(),
        "actual listener task joined after socket shutdown"
    );
    assert_eq!(
        socket_cleanup
            .drain(tokio::time::Instant::now() + WAIT)
            .await,
        crate::commands::ui::socket_tasks::SocketDrainOutcome::Joined,
    );
    tokio::time::timeout(WAIT, async {
        while usage.usage() != ModelCaptureUsage::default() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(usage.usage(), ModelCaptureUsage::default());
    // Full final host seal belongs to the actual CLI workflow; these component
    // fixtures intentionally still retain their genuine provider writer leases.
}

//! Actual SDK registry → production invoker/provider → authenticated socket.
#[path = "../examples/support/artifact_fixture.rs"]
mod artifact_fixture;

use base64::{Engine as _, engine::general_purpose::STANDARD};
use futures_util::{SinkExt, StreamExt};
use morphir::commands::ui::{provider::SessionCapabilities, server::BoundUiHost};
use morphir_distribution::Sha256Digest;
use serde_json::{Value, json};
use std::sync::{Arc, atomic::Ordering};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{Message, client::IntoClientRequest},
};

type Socket =
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>;
async fn exchange(socket: &mut Socket, id: u64, method: &str, params: Value) -> Value {
    socket
        .send(Message::Text(
            json!({"jsonrpc":"2.0","id":id,"method":method,"params":params})
                .to_string()
                .into(),
        ))
        .await
        .unwrap();
    serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap()
}

#[derive(Clone, Copy)]
enum FixtureCompletion {
    Success,
    Failure,
}
enum GateState {
    Held,
    Completed(FixtureCompletion),
}
struct FixtureControl {
    state: std::sync::Mutex<GateState>,
    changed: std::sync::Condvar,
}
impl FixtureControl {
    fn hold(&self) {
        *self.state.lock().unwrap() = GateState::Held;
    }
    fn complete(&self, completion: FixtureCompletion) {
        *self.state.lock().unwrap() = GateState::Completed(completion);
        self.changed.notify_all();
    }
    fn wait(&self) -> FixtureCompletion {
        let (state, _) = self
            .changed
            .wait_timeout_while(
                self.state.lock().unwrap(),
                std::time::Duration::from_secs(10),
                |state| matches!(state, GateState::Held),
            )
            .unwrap();
        match *state {
            GateState::Completed(completion) => completion,
            GateState::Held => FixtureCompletion::Failure,
        }
    }
}
struct ControlledBackend {
    control: Arc<FixtureControl>,
    invocations: Arc<std::sync::atomic::AtomicUsize>,
    requests: Arc<std::sync::Mutex<Vec<morphir_extension_sdk::GenerateRequest>>>,
}
impl morphir_extension_sdk::Extension for ControlledBackend {
    fn info() -> morphir_extension_sdk::ExtensionInfo {
        <artifact_fixture::FixtureBackend as morphir_extension_sdk::Extension>::info()
    }
    fn capabilities() -> morphir_extension_sdk::ExtensionCapabilities {
        <artifact_fixture::FixtureBackend as morphir_extension_sdk::Extension>::capabilities()
    }
}
impl morphir_extension_sdk::Backend for ControlledBackend {
    fn target_languages() -> Vec<String> {
        vec![artifact_fixture::TARGET.into()]
    }
    fn generate(
        &self,
        request: morphir_extension_sdk::GenerateRequest,
    ) -> morphir_extension_sdk::Result<morphir_extension_sdk::GenerateResult> {
        self.requests.lock().unwrap().push(request.clone());
        self.invocations.fetch_add(1, Ordering::SeqCst);
        match self.control.wait() {
            FixtureCompletion::Success => morphir_extension_sdk::Backend::generate(
                &artifact_fixture::FixtureBackend::new(Arc::new(
                    std::sync::atomic::AtomicUsize::new(0),
                )),
                request,
            ),
            FixtureCompletion::Failure => Ok(morphir_extension_sdk::GenerateResult {
                success: false,
                artifacts: vec![],
                diagnostics: vec![],
            }),
        }
    }
}
struct ControlledFixture {
    provider: morphir::commands::ui::provider::playground::NativePlaygroundProvider,
    invocations: Arc<std::sync::atomic::AtomicUsize>,
    control: Arc<FixtureControl>,
    requests: Arc<std::sync::Mutex<Vec<morphir_extension_sdk::GenerateRequest>>>,
}
fn controlled_provider() -> ControlledFixture {
    let invocations = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let control = Arc::new(FixtureControl {
        state: std::sync::Mutex::new(GateState::Completed(FixtureCompletion::Success)),
        changed: std::sync::Condvar::new(),
    });
    let backend = ControlledBackend {
        control: control.clone(),
        invocations: invocations.clone(),
        requests: Arc::default(),
    };
    let requests = backend.requests.clone();
    let mut registry = morphir_host::Registry::new();
    registry
        .register(Arc::new(morphir_host_native::NativeSource::new(
            morphir_extension_sdk::NativeExtension::backend_only(backend).unwrap(),
        )))
        .unwrap();
    ControlledFixture {
        provider:
            morphir::commands::ui::provider::playground::NativePlaygroundProvider::from_registry(
                registry,
                std::env::current_dir().unwrap(),
            ),
        invocations,
        control,
        requests,
    }
}

#[tokio::test]
async fn authenticated_literal_ir_and_options_reach_actual_sdk_backend_unchanged() {
    let ControlledFixture {
        provider,
        invocations,
        requests,
        ..
    } = controlled_provider();
    let host = BoundUiHost::bind(
        "fixture-session".into(),
        SessionCapabilities {
            playground: Some(Arc::new(provider)),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let url = host.base_url();
    let launch = host.launch_url();
    let task = tokio::spawn(host.serve());
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();
    let response = client.get(launch).send().await.unwrap();
    let cookie = response.headers()["set-cookie"]
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap();
    let mut request = (url.replacen("http://", "ws://", 1) + "/rpc")
        .into_client_request()
        .unwrap();
    request.headers_mut().insert("origin", url.parse().unwrap());
    request
        .headers_mut()
        .insert("cookie", cookie.parse().unwrap());
    let (mut socket, _) = connect_async(request).await.unwrap();
    exchange(
        &mut socket,
        1,
        "morphir.session.initialize",
        json!({"protocolVersion":1,"sessionId":"fixture-session"}),
    )
    .await;
    let literal_ir = json!({"formatVersion":4,"nested":{"$serde_json::private::Number":"1"}});
    let literal_option = json!({"$serde_json::private::RawValue":"{\"x\":1,\"x\":2}"});
    let result=exchange(&mut socket,2,"morphir.artifacts.generate",json!({"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":literal_ir,"irVersion":"4","target":artifact_fixture::TARGET,"options":{"literal":literal_option}}})).await;
    assert_eq!(result["result"]["status"], "ready");
    assert_eq!(invocations.load(Ordering::SeqCst), 1);
    let captured = requests.lock().unwrap()[0].clone();
    assert_eq!(captured.ir, literal_ir);
    assert_eq!(captured.options["literal"], literal_option);
    assert_eq!(captured.options["emitParseStage"], false);
    socket.close(None).await.unwrap();
    task.abort();
}

#[tokio::test]
async fn one_host_invocation_credit_refuses_another_socket_and_rolls_back_success_and_failure() {
    let ControlledFixture {
        provider,
        invocations,
        control,
        ..
    } = controlled_provider();
    let host = BoundUiHost::bind(
        "fixture-session".into(),
        SessionCapabilities {
            playground: Some(Arc::new(provider)),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let observer = host.artifact_observer();
    let url = host.base_url();
    let launch = host.launch_url();
    let task = tokio::spawn(host.serve());
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();
    let response = client.get(launch).send().await.unwrap();
    let cookie = response.headers()["set-cookie"]
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap();
    let mut request = (url.replacen("http://", "ws://", 1) + "/rpc")
        .into_client_request()
        .unwrap();
    request.headers_mut().insert("origin", url.parse().unwrap());
    request
        .headers_mut()
        .insert("cookie", cookie.parse().unwrap());
    let (mut first, _) = connect_async(request.clone()).await.unwrap();
    let (mut second, _) = connect_async(request).await.unwrap();
    for socket in [&mut first, &mut second] {
        assert_eq!(
            exchange(
                socket,
                1,
                "morphir.session.initialize",
                json!({"protocolVersion":1,"sessionId":"fixture-session"})
            )
            .await["result"]["protocolVersion"],
            1
        );
    }
    let generation = json!({"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":{"formatVersion":4},"irVersion":"4","target":artifact_fixture::TARGET,"options":{}}});
    for (attempt, completion) in [FixtureCompletion::Success, FixtureCompletion::Failure]
        .into_iter()
        .enumerate()
    {
        control.hold();
        let id = 2 + (attempt as u64) * 2;
        first.send(Message::Text(json!({"jsonrpc":"2.0","id":id,"method":"morphir.artifacts.generate","params":generation}).to_string().into())).await.unwrap();
        tokio::time::timeout(std::time::Duration::from_secs(2), async {
            while invocations.load(Ordering::SeqCst) != attempt + 1 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .unwrap();
        assert_eq!(observer.snapshot().active_invocations(), 1);
        assert_eq!(observer.snapshot().reserved_generations(), 1);
        let refused = exchange(
            &mut second,
            id,
            "morphir.artifacts.generate",
            generation.clone(),
        )
        .await;
        assert_eq!(refused["result"]["status"], "failed");
        assert_eq!(
            refused["result"]["diagnostics"][0]["code"],
            "artifacts.capacity"
        );
        assert_eq!(invocations.load(Ordering::SeqCst), attempt + 1);
        assert_eq!(observer.snapshot().active_invocations(), 1);
        assert_eq!(observer.snapshot().reserved_generations(), 1);
        control.complete(completion);
        let result: Value =
            serde_json::from_str(first.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(observer.snapshot().active_invocations(), 0);
        match completion {
            FixtureCompletion::Success => {
                assert_eq!(result["result"]["status"], "ready");
                assert_eq!(observer.snapshot().reserved_generations(), 1);
                assert_eq!(exchange(&mut first,id+1,"morphir.artifacts.release",json!({"contractVersion":"0.1.0-draft.1","generationId":result["result"]["generationId"]})).await["result"],json!({}));
            }
            FixtureCompletion::Failure => assert_eq!(result["result"]["status"], "failed"),
        }
        assert_eq!(observer.snapshot().reserved_generations(), 0);
        assert_eq!(observer.snapshot().reserved_bytes(), 0);
    }
    control.complete(FixtureCompletion::Success);
    assert_eq!(
        exchange(&mut second, 7, "morphir.artifacts.generate", generation).await["result"]["status"],
        "ready"
    );
    assert_eq!(invocations.load(Ordering::SeqCst), 3);
    first.close(None).await.unwrap();
    second.close(None).await.unwrap();
    task.abort();
}

#[tokio::test]
async fn actual_rust_producer_and_authenticated_host_transfer_fixed_large_bytes_once() {
    let (provider, invocations) = artifact_fixture::provider();
    let host = BoundUiHost::bind(
        "fixture-session".into(),
        SessionCapabilities {
            playground: Some(Arc::new(provider)),
            ..Default::default()
        },
    )
    .await
    .unwrap();
    let url = host.base_url();
    let observer = host.artifact_observer();
    let launch = host.launch_url();
    let task = tokio::spawn(host.serve());
    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .unwrap();
    let response = client.get(launch).send().await.unwrap();
    let cookie = response.headers()["set-cookie"]
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap();
    let mut request = (url.replacen("http://", "ws://", 1) + "/rpc")
        .into_client_request()
        .unwrap();
    request.headers_mut().insert("origin", url.parse().unwrap());
    request
        .headers_mut()
        .insert("cookie", cookie.parse().unwrap());
    let (mut socket, _) = connect_async(request.clone()).await.unwrap();
    macro_rules! call { ($id:expr,$method:expr,$params:expr) => {{
        socket.send(Message::Text(json!({"jsonrpc":"2.0","id":$id,"method":$method,"params":$params}).to_string().into())).await.unwrap();
        serde_json::from_str::<Value>(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap()
    }}; }
    assert_eq!(
        call!(
            1,
            "morphir.session.initialize",
            json!({"protocolVersion":1,"sessionId":"fixture-session"})
        )["result"]["protocolVersion"],
        1
    );
    let manifest = call!(2,"morphir.artifacts.generate",json!({"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":{"formatVersion":4},"irVersion":"4","target":artifact_fixture::TARGET,"options":{}}}))["result"].clone();
    assert_eq!(manifest["status"], "ready");
    assert_eq!(manifest["producer"]["id"], artifact_fixture::PRODUCER);
    assert_eq!(manifest["producer"]["version"], "0.1.0");
    assert_eq!(observer.snapshot().reserved_generations(), 1);
    assert_eq!(observer.snapshot().active_invocations(), 0);
    assert_eq!(
        observer.snapshot().reserved_bytes(),
        1_048_833 + "\u{feff}Original\r\nline two\r\n".len()
    );
    let generation = manifest["generationId"].clone();
    let artifact = manifest["artifacts"][0]["id"].clone();
    let (mut other, _) = connect_async(request).await.unwrap();
    other.send(Message::Text(json!({"jsonrpc":"2.0","id":1,"method":"morphir.session.initialize","params":{"protocolVersion":1,"sessionId":"fixture-session"}}).to_string().into())).await.unwrap();
    other.next().await.unwrap().unwrap();
    other.send(Message::Text(json!({"jsonrpc":"2.0","id":2,"method":"morphir.artifacts.read","params":{"contractVersion":"0.1.0-draft.1","generationId":generation,"artifactId":artifact,"offset":0,"maxBytes":1}}).to_string().into())).await.unwrap();
    let stolen: Value =
        serde_json::from_str(other.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
    assert_eq!(stolen["error"]["data"]["code"], "artifacts.unknown_handle");
    other.close(None).await.unwrap();
    assert_eq!(manifest["artifacts"][0]["byteLength"], 1_048_833);
    // This literal was independently authored from the byte recipe before
    // the backend existed, cross-checked by MoonBit SHA-256 and OpenSSL.
    const EXPECTED: &str = "fa651153f54c6b07a3b2d6543fdd2601cf423ebe8e5a5e0d278437e6ac5565e0";
    assert_eq!(manifest["artifacts"][0]["sha256"], EXPECTED);
    let mut bytes = Vec::new();
    let mut id = 3;
    while bytes.len() < 1_048_833 {
        let offset = bytes.len();
        let result = call!(
            id,
            "morphir.artifacts.read",
            json!({"contractVersion":"0.1.0-draft.1","generationId":generation,"artifactId":artifact,"offset":offset,"maxBytes":65536})
        );
        let chunk = &result["result"];
        assert_eq!(chunk["offset"], offset);
        let decoded = STANDARD.decode(chunk["content"].as_str().unwrap()).unwrap();
        assert!(decoded.len() <= 65536);
        bytes.extend(decoded);
        assert_eq!(chunk["nextOffset"], bytes.len());
        id += 1;
    }
    assert_eq!(Sha256Digest::of_bytes(&bytes).to_string(), EXPECTED);
    assert!(
        bytes
            .iter()
            .enumerate()
            .all(|(i, byte)| *byte == (i % 256) as u8 ^ ((i / 65536) % 256) as u8)
    );
    assert_eq!(invocations.load(Ordering::SeqCst), 1);
    assert_eq!(
        call!(
            id,
            "morphir.artifacts.release",
            json!({"contractVersion":"0.1.0-draft.1","generationId":generation})
        )["result"],
        json!({})
    );
    id += 1;
    assert_eq!(observer.snapshot().reserved_bytes(), 0);
    assert_eq!(observer.snapshot().reserved_generations(), 0);
    assert_eq!(
        call!(
            id,
            "morphir.artifacts.release",
            json!({"contractVersion":"0.1.0-draft.1","generationId":generation})
        )["result"],
        json!({})
    );
    id += 1;
    assert_eq!(
        call!(
            id,
            "morphir.artifacts.read",
            json!({"contractVersion":"0.1.0-draft.1","generationId":generation,"artifactId":artifact,"offset":0,"maxBytes":1})
        )["error"]["data"]["code"],
        "artifacts.unknown_handle"
    );
    assert_eq!(invocations.load(Ordering::SeqCst), 1);
    id += 1;
    assert_eq!(
        call!(
            id,
            "morphir.artifacts.generate",
            json!({"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":{"formatVersion":4},"irVersion":"4","target":artifact_fixture::TARGET,"options":{}}})
        )["result"]["status"],
        "ready"
    );
    assert_eq!(observer.snapshot().reserved_generations(), 1);
    socket.close(None).await.unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        while observer.snapshot().reserved_generations() != 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    assert_eq!(observer.snapshot().reserved_bytes(), 0);
    task.abort();
}

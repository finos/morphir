//! Authenticated JSON-RPC v1-over-WebSocket handling.

use std::collections::BTreeMap;

use axum::{
    extract::{
        State, WebSocketUpgrade,
        ws::{Message, WebSocket},
    },
    http::{HeaderMap, StatusCode, header},
    response::{IntoResponse, Response},
};
use serde::Deserialize;
use serde_json::{Value, json};

use super::{
    protocol::{
        CONNECTED_PROTOCOL_VERSION, ConnectedMethod, JsonRpcRequest, ProjectModelOpenParams,
        RequestLedger, WorkbenchSourceRef, WorkspaceSnapshot,
    },
    server::{UiHostState, authenticated, unauthorized},
};

const MAX_INBOUND_MESSAGE_BYTES: usize = 1024 * 1024;

pub(crate) async fn upgrade(
    State(state): State<UiHostState>,
    headers: HeaderMap,
    upgrade: WebSocketUpgrade,
) -> Response {
    if !authenticated(&state, &headers) {
        return unauthorized();
    }
    if !valid_origin_and_host(&state, &headers) {
        return StatusCode::FORBIDDEN.into_response();
    }
    upgrade
        .max_message_size(MAX_INBOUND_MESSAGE_BYTES)
        .max_frame_size(MAX_INBOUND_MESSAGE_BYTES)
        .on_upgrade(move |socket| serve_socket(socket, state))
        .into_response()
}

fn valid_origin_and_host(state: &UiHostState, headers: &HeaderMap) -> bool {
    let host = headers
        .get(header::HOST)
        .and_then(|value| value.to_str().ok());
    let origin = headers
        .get(header::ORIGIN)
        .and_then(|value| value.to_str().ok());
    host == Some(state.authority.as_str())
        && origin == Some(format!("http://{}", state.authority).as_str())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct InitializeParams {
    protocol_version: u32,
    session_id: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct SourceParams {
    source: WorkbenchSourceRef,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UnwatchParams {
    subscription_id: String,
}

struct ConnectionState {
    initialized: bool,
    ledger: RequestLedger,
    next_subscription: u64,
    subscriptions: BTreeMap<String, WatchSubscription>,
}

struct WatchSubscription {
    source: WorkbenchSourceRef,
    last_snapshot: WorkspaceSnapshot,
    refresh_failed: bool,
}

impl Default for ConnectionState {
    fn default() -> Self {
        Self {
            initialized: false,
            ledger: RequestLedger::default(),
            next_subscription: 1,
            subscriptions: BTreeMap::new(),
        }
    }
}

async fn serve_socket(mut socket: WebSocket, host: UiHostState) {
    let mut state = ConnectionState::default();
    let mut watch_interval = tokio::time::interval(host.provider.watch_refresh_interval());
    watch_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    loop {
        tokio::select! {
            message = socket.recv() => {
                let Some(message) = message else {
                    break;
                };
                let Ok(message) = message else {
                    break;
                };
                let Message::Text(text) = message else {
                    let _ = socket.send(Message::Close(None)).await;
                    break;
                };
                if text.len() > MAX_INBOUND_MESSAGE_BYTES {
                    let _ = socket.send(Message::Close(None)).await;
                    break;
                }
                let Ok(request) = serde_json::from_str::<JsonRpcRequest>(&text) else {
                    if send_value(
                        &mut socket,
                        rpc_error(Value::Null, -32600, "Invalid Request"),
                    )
                    .await
                    .is_err()
                    {
                        break;
                    }
                    continue;
                };
                if let Err(error) = state.ledger.register(request.id) {
                    let _ = send_value(
                        &mut socket,
                        rpc_error(json!(request.id), -32600, &error.to_string()),
                    )
                    .await;
                    break;
                }
                if !state.initialized && request.method != ConnectedMethod::Initialize {
                    let _ = send_value(
                        &mut socket,
                        rpc_error(
                            json!(request.id),
                            -32001,
                            "morphir.session.initialize must be the first call",
                        ),
                    )
                    .await;
                    break;
                }
                let response = dispatch(&host, &mut state, &request).await;
                let watch_snapshot = response.watch_snapshot.clone();
                let subscription_id = response.subscription_id.clone();
                if send_value(&mut socket, response.envelope).await.is_err() {
                    break;
                }
                if let (Some(snapshot), Some(subscription_id)) =
                    (watch_snapshot, subscription_id)
                    && send_workspace_event(&mut socket, &subscription_id, snapshot)
                        .await
                        .is_err()
                {
                    break;
                }
            }
            _ = watch_interval.tick(), if !state.subscriptions.is_empty() => {
                if refresh_subscriptions(&mut socket, &host, &mut state).await.is_err() {
                    break;
                }
            }
        }
    }
}

async fn refresh_subscriptions(
    socket: &mut WebSocket,
    host: &UiHostState,
    state: &mut ConnectionState,
) -> Result<(), ()> {
    let pending = state
        .subscriptions
        .iter()
        .map(|(id, subscription)| (id.clone(), subscription.source.clone()))
        .collect::<Vec<_>>();
    for (subscription_id, source) in pending {
        match host.provider.open(&source).await {
            Ok(snapshot) => {
                let should_emit =
                    state
                        .subscriptions
                        .get(&subscription_id)
                        .is_some_and(|subscription| {
                            subscription.refresh_failed || subscription.last_snapshot != snapshot
                        });
                if !should_emit {
                    continue;
                }
                send_workspace_event(socket, &subscription_id, snapshot.clone()).await?;
                if let Some(subscription) = state.subscriptions.get_mut(&subscription_id) {
                    subscription.last_snapshot = snapshot;
                    subscription.refresh_failed = false;
                }
            }
            Err(error) => {
                let should_emit = state
                    .subscriptions
                    .get(&subscription_id)
                    .is_some_and(|subscription| !subscription.refresh_failed);
                if !should_emit {
                    continue;
                }
                send_provider_disconnected_event(
                    socket,
                    &subscription_id,
                    &source.provider_id,
                    &error.to_string(),
                )
                .await?;
                if let Some(subscription) = state.subscriptions.get_mut(&subscription_id) {
                    subscription.refresh_failed = true;
                }
            }
        }
    }
    Ok(())
}

async fn send_workspace_event(
    socket: &mut WebSocket,
    subscription_id: &str,
    snapshot: WorkspaceSnapshot,
) -> Result<(), ()> {
    send_value(
        socket,
        json!({
            "jsonrpc": "2.0",
            "method": "morphir.workspace.event",
            "params": {
                "subscriptionId": subscription_id,
                "event": {"tag": "snapshot", "snapshot": snapshot}
            }
        }),
    )
    .await
}

async fn send_provider_disconnected_event(
    socket: &mut WebSocket,
    subscription_id: &str,
    provider_id: &str,
    message: &str,
) -> Result<(), ()> {
    send_value(
        socket,
        json!({
            "jsonrpc": "2.0",
            "method": "morphir.workspace.event",
            "params": {
                "subscriptionId": subscription_id,
                "event": {
                    "tag": "provider-disconnected",
                    "providerId": provider_id,
                    "message": message
                }
            }
        }),
    )
    .await
}

struct DispatchResult {
    envelope: Value,
    subscription_id: Option<String>,
    watch_snapshot: Option<super::protocol::WorkspaceSnapshot>,
}

impl DispatchResult {
    fn result(id: u64, result: Value) -> Self {
        Self {
            envelope: json!({"jsonrpc": "2.0", "id": id, "result": result}),
            subscription_id: None,
            watch_snapshot: None,
        }
    }

    fn error(id: u64, code: i64, message: &str) -> Self {
        Self {
            envelope: rpc_error(json!(id), code, message),
            subscription_id: None,
            watch_snapshot: None,
        }
    }
}

async fn dispatch(
    host: &UiHostState,
    state: &mut ConnectionState,
    request: &JsonRpcRequest,
) -> DispatchResult {
    match request.method {
        ConnectedMethod::Initialize => {
            if state.initialized {
                return DispatchResult::error(request.id, -32600, "Session is already initialized");
            }
            let Ok(params) = serde_json::from_value::<InitializeParams>(request.params.clone())
            else {
                return DispatchResult::error(request.id, -32602, "Invalid initialize parameters");
            };
            if params.protocol_version != CONNECTED_PROTOCOL_VERSION
                || params.session_id != host.manifest.session_id
            {
                return DispatchResult::error(
                    request.id,
                    -32602,
                    "Connected session identity or protocol version does not match",
                );
            }
            state.initialized = true;
            DispatchResult::result(
                request.id,
                json!({"protocolVersion": CONNECTED_PROTOCOL_VERSION}),
            )
        }
        ConnectedMethod::DevelopmentInspect => {
            let Ok(params) = serde_json::from_value::<SourceParams>(request.params.clone()) else {
                return DispatchResult::error(request.id, -32602, "Invalid source parameters");
            };
            match host.provider.inspect(&params.source).await {
                Ok(result) => DispatchResult::result(request.id, json!(result)),
                Err(error) => DispatchResult::error(request.id, -32602, &error.to_string()),
            }
        }
        ConnectedMethod::ProjectModelOpen => {
            let Ok(params) =
                serde_json::from_value::<ProjectModelOpenParams>(request.params.clone())
            else {
                return DispatchResult::error(
                    request.id,
                    -32602,
                    "Invalid project model parameters",
                );
            };
            let Ok(params) = params.validate() else {
                return DispatchResult::error(
                    request.id,
                    -32602,
                    "Invalid project model parameters",
                );
            };
            match host
                .provider
                .load_project_model(&params.source, &params.project_id)
                .await
            {
                Ok(result) => DispatchResult::result(request.id, json!(result)),
                Err(error) => DispatchResult::error(request.id, -32602, &error.to_string()),
            }
        }
        ConnectedMethod::WorkspaceOpen => {
            let Ok(params) = serde_json::from_value::<SourceParams>(request.params.clone()) else {
                return DispatchResult::error(request.id, -32602, "Invalid source parameters");
            };
            match host.provider.open(&params.source).await {
                Ok(snapshot) => DispatchResult::result(request.id, json!({"snapshot": snapshot})),
                Err(error) => DispatchResult::error(request.id, -32602, &error.to_string()),
            }
        }
        ConnectedMethod::WorkspaceWatch => {
            let Ok(params) = serde_json::from_value::<SourceParams>(request.params.clone()) else {
                return DispatchResult::error(request.id, -32602, "Invalid source parameters");
            };
            match host.provider.open(&params.source).await {
                Ok(snapshot) => {
                    let subscription_id = format!("watch:{}", state.next_subscription);
                    state.next_subscription += 1;
                    state.subscriptions.insert(
                        subscription_id.clone(),
                        WatchSubscription {
                            source: params.source,
                            last_snapshot: snapshot.clone(),
                            refresh_failed: false,
                        },
                    );
                    DispatchResult {
                        envelope: json!({
                            "jsonrpc": "2.0",
                            "id": request.id,
                            "result": {"subscriptionId": subscription_id}
                        }),
                        subscription_id: Some(subscription_id),
                        watch_snapshot: Some(snapshot),
                    }
                }
                Err(error) => DispatchResult::error(request.id, -32602, &error.to_string()),
            }
        }
        ConnectedMethod::WorkspaceUnwatch => {
            let Ok(params) = serde_json::from_value::<UnwatchParams>(request.params.clone()) else {
                return DispatchResult::error(request.id, -32602, "Invalid unwatch parameters");
            };
            DispatchResult::result(
                request.id,
                json!({"removed": state.subscriptions.remove(&params.subscription_id).is_some()}),
            )
        }
        // Wire types only land in this task; a later task wires these
        // methods to the capability catalog and the compile/generate
        // providers.
        ConnectedMethod::PlaygroundCatalog
        | ConnectedMethod::PlaygroundCompile
        | ConnectedMethod::PlaygroundGenerate => {
            DispatchResult::error(request.id, -32601, "Method not yet implemented")
        }
    }
}

fn rpc_error(id: Value, code: i64, message: &str) -> Value {
    json!({
        "jsonrpc": "2.0",
        "id": id,
        "error": {"code": code, "message": message}
    })
}

async fn send_value(socket: &mut WebSocket, value: Value) -> Result<(), ()> {
    let encoded = serde_json::to_string(&value).map_err(|_| ())?;
    socket
        .send(Message::Text(encoded.into()))
        .await
        .map_err(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        commands::ui::{
            protocol::{InspectResult, ProviderManifest, WorkspaceSnapshot},
            provider::{WorkspaceCapability, native::NativeWorkspaceProvider},
            server::BoundUiHost,
        },
        error::CliError,
    };
    use futures_util::{SinkExt as _, StreamExt as _};
    use tokio_tungstenite::{connect_async, tungstenite::client::IntoClientRequest as _};

    fn fixture() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../ecosystem/morphir-rust/tests/fixtures/workspace-discovery/valid-monorepo")
    }

    async fn launched_host() -> (String, String, tokio::task::JoinHandle<()>) {
        let provider = std::sync::Arc::new(
            NativeWorkspaceProvider::discover(&fixture(), "session-1").unwrap(),
        );
        launched_host_with_provider(provider).await
    }

    async fn launched_host_with_provider(
        provider: std::sync::Arc<dyn WorkspaceCapability>,
    ) -> (String, String, tokio::task::JoinHandle<()>) {
        let host = BoundUiHost::bind("session-1".into(), provider)
            .await
            .unwrap();
        let launch_url = host.launch_url();
        let base_url = host.base_url();
        let (listener, router) = host.into_parts();
        let task = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
        let response = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .unwrap()
            .get(launch_url)
            .send()
            .await
            .unwrap();
        let cookie = response.headers()[header::SET_COOKIE]
            .to_str()
            .unwrap()
            .split(';')
            .next()
            .unwrap()
            .to_owned();
        (base_url, cookie, task)
    }

    struct MutableWorkspaceProvider {
        delegate: NativeWorkspaceProvider,
        snapshot: std::sync::RwLock<WorkspaceSnapshot>,
        fail_open: std::sync::atomic::AtomicBool,
    }

    impl MutableWorkspaceProvider {
        async fn new() -> Self {
            let delegate = NativeWorkspaceProvider::discover(&fixture(), "session-1").unwrap();
            let source = delegate.initial_sources().pop().unwrap();
            let snapshot = delegate.open(&source).await.unwrap();
            Self {
                delegate,
                snapshot: std::sync::RwLock::new(snapshot),
                fail_open: std::sync::atomic::AtomicBool::new(false),
            }
        }

        fn replace_name(&self, name: &str) {
            self.snapshot.write().unwrap().name = Some(name.into());
        }

        fn set_open_failure(&self, fail: bool) {
            self.fail_open
                .store(fail, std::sync::atomic::Ordering::SeqCst);
        }
    }

    #[async_trait::async_trait]
    impl WorkspaceCapability for MutableWorkspaceProvider {
        fn watch_refresh_interval(&self) -> std::time::Duration {
            std::time::Duration::from_millis(25)
        }

        fn manifest(&self) -> ProviderManifest {
            self.delegate.manifest()
        }

        fn initial_sources(&self) -> Vec<WorkbenchSourceRef> {
            self.delegate.initial_sources()
        }

        async fn inspect(&self, source: &WorkbenchSourceRef) -> Result<InspectResult, CliError> {
            self.delegate.inspect(source).await
        }

        async fn open(&self, source: &WorkbenchSourceRef) -> Result<WorkspaceSnapshot, CliError> {
            self.delegate.inspect(source).await?;
            if self.fail_open.load(std::sync::atomic::Ordering::SeqCst) {
                return Err(CliError::Extension {
                    message: "controlled provider failure".into(),
                });
            }
            Ok(self.snapshot.read().unwrap().clone())
        }

        async fn load_project_model(
            &self,
            source: &WorkbenchSourceRef,
            project_id: &str,
        ) -> Result<super::super::protocol::ProjectModelOpenResult, CliError> {
            self.delegate.load_project_model(source, project_id).await
        }
    }

    fn socket_request(base_url: &str, cookie: &str) -> axum::http::Request<()> {
        let socket_url = base_url.replacen("http://", "ws://", 1) + "/rpc";
        let mut request = socket_url.into_client_request().unwrap();
        let authority = base_url.trim_start_matches("http://");
        request.headers_mut().insert(
            header::ORIGIN,
            format!("http://{authority}").parse().unwrap(),
        );
        request
            .headers_mut()
            .insert(header::COOKIE, cookie.parse().unwrap());
        request
    }

    #[tokio::test]
    async fn rejects_missing_origin_before_websocket_upgrade() {
        let (base_url, cookie, task) = launched_host().await;
        let socket_url = base_url.replacen("http://", "ws://", 1) + "/rpc";
        let mut request = socket_url.into_client_request().unwrap();
        request
            .headers_mut()
            .insert(header::COOKIE, cookie.parse().unwrap());

        let error = connect_async(request).await.unwrap_err();
        assert!(error.to_string().contains("403"));
        task.abort();
    }

    #[tokio::test]
    async fn rejects_wrong_host_origin_and_session_cookie() {
        let (base_url, cookie, task) = launched_host().await;

        let mut wrong_host = socket_request(&base_url, &cookie);
        wrong_host
            .headers_mut()
            .insert(header::HOST, "127.0.0.1:1".parse().unwrap());
        assert!(
            connect_async(wrong_host)
                .await
                .unwrap_err()
                .to_string()
                .contains("403")
        );

        let mut wrong_origin = socket_request(&base_url, &cookie);
        wrong_origin
            .headers_mut()
            .insert(header::ORIGIN, "https://example.invalid".parse().unwrap());
        assert!(
            connect_async(wrong_origin)
                .await
                .unwrap_err()
                .to_string()
                .contains("403")
        );

        let mut wrong_cookie = socket_request(&base_url, "morphir_session=wrong");
        wrong_cookie
            .headers_mut()
            .insert(header::ORIGIN, base_url.parse().unwrap());
        assert!(
            connect_async(wrong_cookie)
                .await
                .unwrap_err()
                .to_string()
                .contains("401")
        );

        task.abort();
    }

    async fn initialize_socket(
        base_url: &str,
        cookie: &str,
    ) -> tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>
    {
        let (mut socket, _) = connect_async(socket_request(base_url, cookie))
            .await
            .unwrap();
        socket
            .send(tokio_tungstenite::tungstenite::Message::Text(
                json!({
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "morphir.session.initialize",
                    "params": {"protocolVersion": CONNECTED_PROTOCOL_VERSION, "sessionId": "session-1"}
                })
                .to_string()
                .into(),
            ))
            .await
            .unwrap();
        let initialized: Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(
            initialized["result"]["protocolVersion"],
            CONNECTED_PROTOCOL_VERSION
        );
        socket
    }

    #[tokio::test]
    async fn rejects_unadvertised_methods_malformed_requests_and_foreign_sources() {
        let (base_url, cookie, task) = launched_host().await;
        let mut socket = initialize_socket(&base_url, &cookie).await;

        for (expected_id, text) in [
            (
                None,
                json!({
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "morphir.filesystem.read",
                    "params": {}
                })
                .to_string(),
            ),
            (None, "not json".into()),
            (
                Some(3),
                json!({
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "morphir.workspace.open",
                    "params": {"source": {
                        "providerId": "cli:another-session",
                        "locator": "workspace:initial",
                        "displayName": "foreign"
                    }}
                })
                .to_string(),
            ),
            (
                Some(4),
                json!({
                    "jsonrpc": "2.0",
                    "id": 4,
                    "method": "morphir.project-model.open",
                    "params": {
                        "source": {
                            "providerId": "cli:another-session",
                            "locator": "workspace:initial",
                            "displayName": "foreign"
                        },
                        "projectId": "project-1"
                    }
                })
                .to_string(),
            ),
        ] {
            socket
                .send(tokio_tungstenite::tungstenite::Message::Text(text.into()))
                .await
                .unwrap();
            let response: Value =
                serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap())
                    .unwrap();
            assert!(response["error"].is_object());
            match expected_id {
                Some(id) => assert_eq!(response["id"], id),
                None => assert!(response["id"].is_null()),
            }
        }

        task.abort();
    }

    #[tokio::test]
    async fn closes_on_binary_and_oversized_frames() {
        let (base_url, cookie, task) = launched_host().await;
        let mut binary = initialize_socket(&base_url, &cookie).await;
        binary
            .send(tokio_tungstenite::tungstenite::Message::Binary(
                vec![1, 2, 3].into(),
            ))
            .await
            .unwrap();
        assert!(!matches!(
            binary.next().await,
            Some(Ok(tokio_tungstenite::tungstenite::Message::Text(_)))
        ));

        let mut oversized = initialize_socket(&base_url, &cookie).await;
        let payload = "x".repeat(MAX_INBOUND_MESSAGE_BYTES + 1);
        let sent = oversized
            .send(tokio_tungstenite::tungstenite::Message::Text(
                payload.into(),
            ))
            .await;
        if sent.is_ok() {
            assert!(!matches!(
                oversized.next().await,
                Some(Ok(tokio_tungstenite::tungstenite::Message::Text(_)))
            ));
        }

        task.abort();
    }

    #[tokio::test]
    async fn initializes_opens_and_watches_the_initial_workspace() {
        let (base_url, cookie, task) = launched_host().await;
        let mut socket = initialize_socket(&base_url, &cookie).await;

        let source = json!({
            "providerId": "cli:session-1",
            "locator": "workspace:initial",
            "displayName": "valid-monorepo"
        });
        socket
            .send(tokio_tungstenite::tungstenite::Message::Text(
                json!({
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "morphir.workspace.watch",
                    "params": {"source": source}
                })
                .to_string()
                .into(),
            ))
            .await
            .unwrap();
        let watched: Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(watched["result"]["subscriptionId"], "watch:1");
        let event: Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(event["method"], "morphir.workspace.event");
        assert_eq!(
            event["params"]["event"]["snapshot"]["root"]["providerId"],
            "cli:session-1"
        );

        task.abort();
    }

    #[tokio::test]
    async fn opens_a_selected_project_model_after_initialization() {
        let root = tempfile::tempdir().unwrap();
        std::fs::write(
            root.path().join("morphir.toml"),
            "[project]\nname = \"acme/orders\"\nsource_directory = \"src\"\n",
        )
        .unwrap();
        let content = r#"{"formatVersion":3,"distribution":["Library",[],[],{"modules":[]}]}"#;
        std::fs::write(root.path().join("morphir-ir.json"), content).unwrap();
        let provider = std::sync::Arc::new(
            NativeWorkspaceProvider::discover(root.path(), "session-1").unwrap(),
        );
        let source = provider.initial_sources().pop().unwrap();
        let project_id = provider.open(&source).await.unwrap().projects[0].id.clone();
        let (base_url, cookie, task) = launched_host_with_provider(provider).await;
        let mut socket = initialize_socket(&base_url, &cookie).await;

        socket
            .send(tokio_tungstenite::tungstenite::Message::Text(
                json!({
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "morphir.project-model.open",
                    "params": {"source": source, "projectId": project_id}
                })
                .to_string()
                .into(),
            ))
            .await
            .unwrap();
        let response: Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();

        assert_eq!(response["result"]["content"], content);
        assert_eq!(response["result"]["descriptor"]["kind"], "model");
        assert_eq!(response["result"]["descriptor"]["route"], "explorer");
        task.abort();
    }

    #[tokio::test]
    async fn sends_workspace_responses_larger_than_inbound_limit() {
        let provider = std::sync::Arc::new(MutableWorkspaceProvider::new().await);
        let oversized_name = "x".repeat(MAX_INBOUND_MESSAGE_BYTES + 1);
        provider.replace_name(&oversized_name);
        let (base_url, cookie, task) = launched_host_with_provider(provider).await;
        let mut socket = initialize_socket(&base_url, &cookie).await;

        socket
            .send(tokio_tungstenite::tungstenite::Message::Text(
                json!({
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "morphir.workspace.open",
                    "params": {"source": {
                        "providerId": "cli:session-1",
                        "locator": "workspace:initial",
                        "displayName": "valid-monorepo"
                    }}
                })
                .to_string()
                .into(),
            ))
            .await
            .unwrap();

        let response = tokio::time::timeout(std::time::Duration::from_secs(2), socket.next())
            .await
            .expect("the host should send a workspace response larger than the inbound limit")
            .expect("the socket should remain open")
            .expect("the response should be a valid WebSocket message");
        let response: Value = serde_json::from_str(response.to_text().unwrap()).unwrap();
        assert_eq!(
            response["result"]["snapshot"]["name"]
                .as_str()
                .unwrap()
                .len(),
            oversized_name.len()
        );

        task.abort();
    }

    #[tokio::test]
    async fn watch_emits_snapshots_after_provider_changes() {
        let provider = std::sync::Arc::new(MutableWorkspaceProvider::new().await);
        let (base_url, cookie, task) = launched_host_with_provider(provider.clone()).await;
        let mut socket = initialize_socket(&base_url, &cookie).await;

        socket
            .send(tokio_tungstenite::tungstenite::Message::Text(
                json!({
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "morphir.workspace.watch",
                    "params": {"source": {
                        "providerId": "cli:session-1",
                        "locator": "workspace:initial",
                        "displayName": "valid-monorepo"
                    }}
                })
                .to_string()
                .into(),
            ))
            .await
            .unwrap();
        let watched: Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(watched["result"]["subscriptionId"], "watch:1");
        let initial: Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(initial["method"], "morphir.workspace.event");

        provider.replace_name("changed");
        let changed = tokio::time::timeout(std::time::Duration::from_secs(2), socket.next())
            .await
            .expect("a live watch should emit a changed snapshot")
            .unwrap()
            .unwrap();
        let event: Value = serde_json::from_str(changed.to_text().unwrap()).unwrap();
        assert_eq!(event["params"]["event"]["snapshot"]["name"], "changed");

        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(100), socket.next())
                .await
                .is_err(),
            "unchanged snapshots must not emit duplicate events"
        );

        socket
            .send(tokio_tungstenite::tungstenite::Message::Text(
                json!({
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "morphir.workspace.unwatch",
                    "params": {"subscriptionId": "watch:1"}
                })
                .to_string()
                .into(),
            ))
            .await
            .unwrap();
        let unwatched: Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        assert_eq!(unwatched["result"]["removed"], true);

        provider.replace_name("after-unwatch");
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(100), socket.next())
                .await
                .is_err(),
            "unwatched subscriptions must not emit later events"
        );

        task.abort();
    }

    #[tokio::test]
    async fn watch_reports_disconnect_once_and_emits_recovery_snapshot() {
        let provider = std::sync::Arc::new(MutableWorkspaceProvider::new().await);
        let (base_url, cookie, task) = launched_host_with_provider(provider.clone()).await;
        let mut socket = initialize_socket(&base_url, &cookie).await;

        socket
            .send(tokio_tungstenite::tungstenite::Message::Text(
                json!({
                    "jsonrpc": "2.0",
                    "id": 2,
                    "method": "morphir.workspace.watch",
                    "params": {"source": {
                        "providerId": "cli:session-1",
                        "locator": "workspace:initial",
                        "displayName": "valid-monorepo"
                    }}
                })
                .to_string()
                .into(),
            ))
            .await
            .unwrap();
        let _watched = socket.next().await.unwrap().unwrap();
        let initial: Value =
            serde_json::from_str(socket.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
        let initial_name = initial["params"]["event"]["snapshot"]["name"].clone();

        provider.set_open_failure(true);
        let disconnected = tokio::time::timeout(std::time::Duration::from_secs(2), socket.next())
            .await
            .expect("the first failed refresh should emit a disconnect event")
            .unwrap()
            .unwrap();
        let event: Value = serde_json::from_str(disconnected.to_text().unwrap()).unwrap();
        assert_eq!(event["params"]["event"]["tag"], "provider-disconnected");
        assert_eq!(event["params"]["event"]["providerId"], "cli:session-1");
        assert!(
            event["params"]["event"]["message"]
                .as_str()
                .unwrap()
                .contains("controlled provider failure")
        );

        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(100), socket.next())
                .await
                .is_err(),
            "repeated refresh failures must not emit duplicate disconnect events"
        );

        provider.set_open_failure(false);
        let recovered = tokio::time::timeout(std::time::Duration::from_secs(2), socket.next())
            .await
            .expect("the first successful refresh should emit a recovery snapshot")
            .unwrap()
            .unwrap();
        let event: Value = serde_json::from_str(recovered.to_text().unwrap()).unwrap();
        assert_eq!(event["params"]["event"]["tag"], "snapshot");
        assert_eq!(event["params"]["event"]["snapshot"]["name"], initial_name);

        task.abort();
    }
}

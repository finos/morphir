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

use crate::error::CliError;

use super::{
    protocol::{
        CONNECTED_PROTOCOL_VERSION, ConnectedMethod, JsonRpcRequest, PlaygroundCompileParams,
        PlaygroundGenerateParams, ProjectModelOpenParams, RequestLedger, WorkbenchSourceRef,
        WorkspaceSnapshot,
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
    let refresh_interval = host
        .capabilities
        .workspace
        .as_ref()
        .map_or(std::time::Duration::from_millis(500), |workspace| {
            workspace.watch_refresh_interval()
        });
    let mut watch_interval = tokio::time::interval(refresh_interval);
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
    // Subscriptions are only ever created by the `morphir.workspace.watch`
    // arm, which itself requires a workspace capability, so an absent
    // workspace here means there is nothing pending to refresh.
    let Some(workspace) = host.capabilities.workspace.as_ref() else {
        return Ok(());
    };
    let pending = state
        .subscriptions
        .iter()
        .map(|(id, subscription)| (id.clone(), subscription.source.clone()))
        .collect::<Vec<_>>();
    for (subscription_id, source) in pending {
        match workspace.open(&source).await {
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
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid initialize parameters",
                );
            };
            if params.protocol_version != CONNECTED_PROTOCOL_VERSION
                || params.session_id != host.manifest.session_id
            {
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
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
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid source parameters",
                );
            };
            let Some(workspace) = &host.capabilities.workspace else {
                return workspace_unavailable(request.id);
            };
            match workspace.inspect(&params.source).await {
                Ok(result) => DispatchResult::result(request.id, json!(result)),
                Err(error) => DispatchResult::error(request.id, INVALID_PARAMS, &error.to_string()),
            }
        }
        ConnectedMethod::ProjectModelOpen => {
            let Ok(params) =
                serde_json::from_value::<ProjectModelOpenParams>(request.params.clone())
            else {
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid project model parameters",
                );
            };
            let Ok(params) = params.validate() else {
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid project model parameters",
                );
            };
            let Some(workspace) = &host.capabilities.workspace else {
                return workspace_unavailable(request.id);
            };
            match workspace
                .load_project_model(&params.source, &params.project_id)
                .await
            {
                Ok(result) => DispatchResult::result(request.id, json!(result)),
                Err(error) => DispatchResult::error(request.id, INVALID_PARAMS, &error.to_string()),
            }
        }
        ConnectedMethod::WorkspaceOpen => {
            let Ok(params) = serde_json::from_value::<SourceParams>(request.params.clone()) else {
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid source parameters",
                );
            };
            let Some(workspace) = &host.capabilities.workspace else {
                return workspace_unavailable(request.id);
            };
            match workspace.open(&params.source).await {
                Ok(snapshot) => DispatchResult::result(request.id, json!({"snapshot": snapshot})),
                Err(error) => DispatchResult::error(request.id, INVALID_PARAMS, &error.to_string()),
            }
        }
        ConnectedMethod::WorkspaceWatch => {
            let Ok(params) = serde_json::from_value::<SourceParams>(request.params.clone()) else {
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid source parameters",
                );
            };
            let Some(workspace) = &host.capabilities.workspace else {
                return workspace_unavailable(request.id);
            };
            match workspace.open(&params.source).await {
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
                Err(error) => DispatchResult::error(request.id, INVALID_PARAMS, &error.to_string()),
            }
        }
        ConnectedMethod::WorkspaceUnwatch => {
            let Ok(params) = serde_json::from_value::<UnwatchParams>(request.params.clone()) else {
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid unwatch parameters",
                );
            };
            DispatchResult::result(
                request.id,
                json!({"removed": state.subscriptions.remove(&params.subscription_id).is_some()}),
            )
        }
        ConnectedMethod::PlaygroundCatalog => {
            let Some(playground) = &host.capabilities.playground else {
                return capability_unavailable(request.id, "playground");
            };
            match playground.catalog().await {
                Ok(catalog) => DispatchResult::result(request.id, json!(catalog)),
                Err(error) => provider_failure(request.id, &error),
            }
        }
        ConnectedMethod::PlaygroundCompile => {
            let Ok(params) =
                serde_json::from_value::<PlaygroundCompileParams>(request.params.clone())
            else {
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid playground compile parameters",
                );
            };
            let Some(playground) = &host.capabilities.playground else {
                return capability_unavailable(request.id, "playground");
            };
            match playground.compile(params).await {
                Ok(result) => DispatchResult::result(request.id, json!(result)),
                Err(error) => provider_failure(request.id, &error),
            }
        }
        ConnectedMethod::PlaygroundGenerate => {
            let Ok(params) =
                serde_json::from_value::<PlaygroundGenerateParams>(request.params.clone())
            else {
                return DispatchResult::error(
                    request.id,
                    INVALID_PARAMS,
                    "Invalid playground generate parameters",
                );
            };
            let Some(playground) = &host.capabilities.playground else {
                return capability_unavailable(request.id, "playground");
            };
            match playground.generate(params).await {
                Ok(result) => DispatchResult::result(request.id, json!(result)),
                Err(error) => provider_failure(request.id, &error),
            }
        }
    }
}

/// JSON-RPC error code reported when a request names a capability this
/// session was not bound with. Established for the workspace methods and
/// reused for the playground methods: both name the same kind of failure,
/// so they share one code rather than each minting their own.
///
/// Defined locally rather than imported, so this browser-facing protocol
/// stays decoupled from the daemon's extension protocol (a different
/// JSON-RPC channel with its own evolution). The value is chosen to match
/// `morphir_daemon::extensions::protocol::error_codes::CAPABILITY_UNAVAILABLE`
/// anyway: a wire trace should not require knowing which channel produced a
/// given error code to look it up.
const CAPABILITY_UNAVAILABLE: i64 = -32013;

/// Standard JSON-RPC code for a request whose params did not deserialize.
/// Reserved for exactly that: a malformed request the dispatcher rejects
/// before any provider runs.
const INVALID_PARAMS: i64 = -32602;

/// JSON-RPC error code reported when a playground request reached its
/// provider and the provider, or the extension behind it, failed.
///
/// The playground design gives the view four failure classes and asks it to
/// present them differently: an absent capability disables a control and
/// shows the reason, whereas a failed extension raises a banner naming the
/// provider and keeps the user's selections. Folding both into
/// [`INVALID_PARAMS`] forced clients to string-match the message to tell
/// which had happened.
///
/// The value is the standard JSON-RPC internal-error code, which is what an
/// extension crash is from the browser's point of view: the request was well
/// formed and the host could not answer it.
const EXTENSION_FAILED: i64 = -32603;

/// Classifies a playground provider failure into the class the view renders
/// it as, so a client can branch on the error code alone.
///
/// A [`CliError::Validation`] from a playground method says the request asked
/// for something no available extension offers -- "no extension compiles
/// language cobol" -- which is the same statement to the view as a session
/// that carries no playground at all: disable the control, show the reason.
/// It therefore shares [`CAPABILITY_UNAVAILABLE`].
///
/// Everything else is the provider or its extension failing to answer a
/// request it accepted, which the view shows as a banner naming the provider
/// while keeping the user's selections. That is [`EXTENSION_FAILED`].
///
/// Neither is [`INVALID_PARAMS`], which stays reserved for requests rejected
/// before a provider ran.
fn provider_failure(id: u64, error: &CliError) -> DispatchResult {
    let code = match error {
        CliError::Validation { .. } => CAPABILITY_UNAVAILABLE,
        _ => EXTENSION_FAILED,
    };
    DispatchResult::error(id, code, &error.to_string())
}

/// Reported when a request names a capability this session was not bound
/// with.
fn capability_unavailable(id: u64, capability: &str) -> DispatchResult {
    DispatchResult::error(
        id,
        CAPABILITY_UNAVAILABLE,
        &format!("This session has no {capability} capability"),
    )
}

fn workspace_unavailable(id: u64) -> DispatchResult {
    capability_unavailable(id, "workspace")
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
            auth::SessionAuth,
            protocol::{
                InspectResult, JsonRpcVersion, PlaygroundCatalog, PlaygroundCompileResult,
                PlaygroundGenerateResult, ProviderKind, ProviderManifest, ProviderStatus,
                SessionManifest, WorkspaceSnapshot,
            },
            provider::{
                PlaygroundCapability, SessionCapabilities, WorkspaceCapability,
                native::NativeWorkspaceProvider,
            },
            server::{BoundUiHost, tests::StubPlayground},
        },
        error::CliError,
    };
    use futures_util::{SinkExt as _, StreamExt as _};
    use tokio_tungstenite::{connect_async, tungstenite::client::IntoClientRequest as _};

    fn fixture() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../ecosystem/morphir-rust/tests/fixtures/workspace-discovery/valid-monorepo")
    }

    /// Builds a [`UiHostState`] directly, without binding a real TCP
    /// listener. Dispatch only reads `capabilities` (and `manifest` for
    /// `Initialize`), so this is enough for exercising method dispatch
    /// without the socket harness the connection-level tests use.
    fn host_state(capabilities: SessionCapabilities) -> UiHostState {
        let (auth, _launch_token) = SessionAuth::generate("session-1").unwrap();
        let mut providers = Vec::new();
        if let Some(workspace) = &capabilities.workspace {
            providers.push(workspace.manifest());
        }
        if let Some(playground) = &capabilities.playground {
            providers.push(playground.manifest());
        }
        let manifest = SessionManifest {
            protocol_version: CONNECTED_PROTOCOL_VERSION,
            web_socket_path: "/rpc".into(),
            session_id: "session-1".into(),
            providers,
            initial_sources: Vec::new(),
        }
        .validate()
        .unwrap();
        UiHostState {
            auth: std::sync::Arc::new(auth),
            manifest,
            capabilities,
            initial_view: None,
            authority: "127.0.0.1:0".into(),
        }
    }

    fn state_with_playground() -> UiHostState {
        host_state(SessionCapabilities {
            playground: Some(std::sync::Arc::new(StubPlayground)),
            ..Default::default()
        })
    }

    fn state_with_workspace_only() -> UiHostState {
        let provider = std::sync::Arc::new(
            NativeWorkspaceProvider::discover(&fixture(), "session-1").unwrap(),
        );
        host_state(SessionCapabilities {
            workspace: Some(provider),
            ..Default::default()
        })
    }

    /// Runs one request straight through [`dispatch`], bypassing the
    /// WebSocket loop entirely.
    async fn dispatch_request(host: &UiHostState, method: ConnectedMethod, params: Value) -> Value {
        let request = JsonRpcRequest {
            jsonrpc: JsonRpcVersion::V2,
            id: 1,
            method,
            params,
        };
        dispatch(host, &mut ConnectionState::default(), &request)
            .await
            .envelope
    }

    /// A playground provider that records whether any method was invoked,
    /// so a test can prove params validation short-circuits before the
    /// provider is ever reached.
    struct TrackingPlayground {
        called: std::sync::Arc<std::sync::atomic::AtomicBool>,
    }

    #[async_trait::async_trait]
    impl PlaygroundCapability for TrackingPlayground {
        fn manifest(&self) -> ProviderManifest {
            ProviderManifest {
                id: "playground".into(),
                name: "Tracking Playground".into(),
                kind: ProviderKind::Connected,
                status: ProviderStatus::Available,
                capabilities: Vec::new(),
                provenance: None,
            }
        }

        async fn catalog(&self) -> Result<PlaygroundCatalog, CliError> {
            self.called.store(true, std::sync::atomic::Ordering::SeqCst);
            Ok(PlaygroundCatalog::default())
        }

        async fn compile(
            &self,
            _params: PlaygroundCompileParams,
        ) -> Result<PlaygroundCompileResult, CliError> {
            self.called.store(true, std::sync::atomic::Ordering::SeqCst);
            Ok(PlaygroundCompileResult {
                success: true,
                ir_version: None,
                ir: None,
                diagnostics: Vec::new(),
                modules: Vec::new(),
            })
        }

        async fn generate(
            &self,
            _params: PlaygroundGenerateParams,
        ) -> Result<PlaygroundGenerateResult, CliError> {
            self.called.store(true, std::sync::atomic::Ordering::SeqCst);
            Ok(PlaygroundGenerateResult {
                success: true,
                artifacts: Vec::new(),
                diagnostics: Vec::new(),
            })
        }
    }

    #[tokio::test]
    async fn a_catalog_request_returns_the_catalog() {
        let state = state_with_playground();

        let response =
            dispatch_request(&state, ConnectedMethod::PlaygroundCatalog, json!({})).await;

        assert!(
            response["result"]["frontends"].is_array(),
            "response: {response}"
        );
    }

    #[tokio::test]
    async fn a_workspace_request_without_a_workspace_reports_the_missing_capability() {
        let state = state_with_playground();
        let params = json!({"source": {
            "providerId": "cli:session-1",
            "locator": "workspace:initial",
            "displayName": "valid-monorepo"
        }});

        let response = dispatch_request(&state, ConnectedMethod::WorkspaceOpen, params).await;

        assert_eq!(response["error"]["code"], CAPABILITY_UNAVAILABLE);
        assert!(
            response["error"]["message"]
                .as_str()
                .unwrap()
                .contains("workspace"),
            "response: {response}"
        );
    }

    #[tokio::test]
    async fn a_playground_request_without_a_playground_reports_the_missing_capability() {
        let state = state_with_workspace_only();

        let response = dispatch_request(
            &state,
            ConnectedMethod::PlaygroundCompile,
            valid_compile_params(),
        )
        .await;

        assert_eq!(response["error"]["code"], CAPABILITY_UNAVAILABLE);
    }

    /// A playground whose every method fails with a configured error, so a
    /// test can observe how the dispatcher classifies provider failures on
    /// the wire.
    struct FailingPlayground {
        make_error: Box<dyn Fn() -> CliError + Send + Sync>,
    }

    impl FailingPlayground {
        fn extension() -> Self {
            Self {
                make_error: Box::new(|| CliError::Extension {
                    message: "morphir-elm exited before answering".into(),
                }),
            }
        }

        fn validation() -> Self {
            Self {
                make_error: Box::new(|| CliError::Validation {
                    message: "No extension compiles language 'cobol'".into(),
                }),
            }
        }
    }

    #[async_trait::async_trait]
    impl PlaygroundCapability for FailingPlayground {
        fn manifest(&self) -> ProviderManifest {
            ProviderManifest {
                id: "playground".into(),
                name: "Failing Playground".into(),
                kind: ProviderKind::Connected,
                status: ProviderStatus::Available,
                capabilities: Vec::new(),
                provenance: None,
            }
        }

        async fn catalog(&self) -> Result<PlaygroundCatalog, CliError> {
            Err((self.make_error)())
        }

        async fn compile(
            &self,
            _params: PlaygroundCompileParams,
        ) -> Result<PlaygroundCompileResult, CliError> {
            Err((self.make_error)())
        }

        async fn generate(
            &self,
            _params: PlaygroundGenerateParams,
        ) -> Result<PlaygroundGenerateResult, CliError> {
            Err((self.make_error)())
        }
    }

    fn state_with_failing_playground(playground: FailingPlayground) -> UiHostState {
        host_state(SessionCapabilities {
            playground: Some(std::sync::Arc::new(playground)),
            ..Default::default()
        })
    }

    fn valid_compile_params() -> Value {
        json!({
            "languageId": "elm",
            "documents": [],
            "package": {"name": "local/main", "exposedModules": []},
            "irVersion": "3",
            "options": {}
        })
    }

    fn valid_generate_params() -> Value {
        json!({
            "ir": {},
            "irVersion": "3",
            "target": "scala",
            "options": {}
        })
    }

    #[tokio::test]
    async fn a_failed_extension_is_distinguishable_from_bad_compile_params() {
        // The view renders these two as different things: a banner naming the
        // provider versus a rejected request. A client must not have to
        // string-match the message to tell them apart.
        let state = state_with_failing_playground(FailingPlayground::extension());

        let response = dispatch_request(
            &state,
            ConnectedMethod::PlaygroundCompile,
            valid_compile_params(),
        )
        .await;

        assert_eq!(
            response["error"]["code"], EXTENSION_FAILED,
            "response: {response}"
        );
        assert_ne!(
            response["error"]["code"], INVALID_PARAMS,
            "a crashed extension is not an invalid-params error"
        );
        assert!(
            response["error"]["message"]
                .as_str()
                .unwrap()
                .contains("morphir-elm"),
            "response: {response}"
        );
    }

    #[tokio::test]
    async fn a_failed_extension_is_distinguishable_on_generate_too() {
        let state = state_with_failing_playground(FailingPlayground::extension());

        let response = dispatch_request(
            &state,
            ConnectedMethod::PlaygroundGenerate,
            valid_generate_params(),
        )
        .await;

        assert_eq!(
            response["error"]["code"], EXTENSION_FAILED,
            "response: {response}"
        );
    }

    #[tokio::test]
    async fn a_failed_extension_is_distinguishable_on_catalog_too() {
        let state = state_with_failing_playground(FailingPlayground::extension());

        let response =
            dispatch_request(&state, ConnectedMethod::PlaygroundCatalog, json!({})).await;

        assert_eq!(
            response["error"]["code"], EXTENSION_FAILED,
            "response: {response}"
        );
    }

    #[tokio::test]
    async fn an_unsupported_language_reports_an_absent_capability_not_an_extension_failure() {
        // "No extension compiles language x" is the capability-absent class:
        // the view disables the control and shows the reason. It shares a code
        // with a session that was never bound with a playground at all,
        // because both say the same thing to the view.
        let state = state_with_failing_playground(FailingPlayground::validation());

        let response = dispatch_request(
            &state,
            ConnectedMethod::PlaygroundCompile,
            valid_compile_params(),
        )
        .await;

        assert_eq!(
            response["error"]["code"], CAPABILITY_UNAVAILABLE,
            "response: {response}"
        );
        assert_ne!(response["error"]["code"], EXTENSION_FAILED);
        assert_ne!(response["error"]["code"], INVALID_PARAMS);
        assert!(
            response["error"]["message"]
                .as_str()
                .unwrap()
                .contains("cobol"),
            "response: {response}"
        );
    }

    #[tokio::test]
    async fn malformed_generate_params_stay_an_invalid_params_error() {
        // The provider is never reached, so this must keep the JSON-RPC
        // invalid-params code rather than borrowing a provider failure class.
        let state = state_with_failing_playground(FailingPlayground::extension());

        let response = dispatch_request(
            &state,
            ConnectedMethod::PlaygroundGenerate,
            json!({"target": 7}),
        )
        .await;

        assert_eq!(
            response["error"]["code"], INVALID_PARAMS,
            "response: {response}"
        );
    }

    #[tokio::test]
    async fn malformed_compile_params_are_rejected_without_reaching_the_provider() {
        let called = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let state = host_state(SessionCapabilities {
            playground: Some(std::sync::Arc::new(TrackingPlayground {
                called: called.clone(),
            })),
            ..Default::default()
        });

        let response = dispatch_request(
            &state,
            ConnectedMethod::PlaygroundCompile,
            json!({"languageId": 7}),
        )
        .await;

        assert_eq!(
            response["error"]["code"], INVALID_PARAMS,
            "response: {response}"
        );
        assert!(
            !called.load(std::sync::atomic::Ordering::SeqCst),
            "params must be validated before dispatch"
        );
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
        let host = BoundUiHost::bind(
            "session-1".into(),
            SessionCapabilities {
                workspace: Some(provider),
                ..Default::default()
            },
        )
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

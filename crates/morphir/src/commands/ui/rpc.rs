//! Authenticated JSON-RPC v1-over-WebSocket handling.

mod model_originals;

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

fn selects_originals(raw: &str) -> bool {
    struct MethodEvidence<'a>(&'a mut bool);
    impl<'de> serde::de::Visitor<'de> for MethodEvidence<'_> {
        type Value = ();
        fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            formatter.write_str("a request object")
        }
        fn visit_map<A: serde::de::MapAccess<'de>>(self, mut map: A) -> Result<(), A::Error> {
            while let Some(key) = map.next_key::<String>()? {
                if key == "method" {
                    let value = map.next_value::<Value>()?;
                    *self.0 |= value
                        .as_str()
                        .is_some_and(|method| method.starts_with("morphir.model-originals."));
                } else {
                    map.next_value::<serde::de::IgnoredAny>()?;
                }
            }
            Ok(())
        }
    }
    // Retain an actually decoded root method even if a later member is malformed.
    // This only classifies errors; the strict decoder still refuses the frame.
    let mut selected = false;
    let _ = serde::Deserializer::deserialize_map(
        &mut serde_json::Deserializer::from_str(raw),
        MethodEvidence(&mut selected),
    );
    selected
}

#[cfg(test)]
mod profile_selection_tests {
    use super::*;
    #[test]
    fn duplicate_originals_method_retains_profile_refusal_classification() {
        let raw = r#"{"jsonrpc":"2.0","id":1,"method":"morphir.model-originals.read","method":"morphir.model-originals.read","params":{}}"#;
        assert!(decode_rpc_request(raw).is_err());
        assert!(selects_originals(raw));
        let error = model_originals::invalid_frame(Value::Null);
        assert_eq!(error["error"]["code"], INVALID_PARAMS);
        assert_eq!(
            error["error"]["data"]["code"],
            "model_originals.invalid_request"
        );
    }
}

async fn send_profile_value(socket: &mut WebSocket, value: Value) -> Result<(), ()> {
    tokio::time::timeout(
        std::time::Duration::from_secs(30),
        send_value(socket, value),
    )
    .await
    .map_err(|_| ())?
}

/// Probe only the method with IgnoredAny for other fields. New profile frames
/// are then validated literally before constructing maps or numeric values.
/// Legacy requests keep their original decoder and wire behavior.
fn decode_rpc_request(raw: &str) -> Result<JsonRpcRequest, ()> {
    #[derive(Deserialize)]
    struct MethodProbe {
        method: String,
    }
    let probe = serde_json::from_str::<MethodProbe>(raw).map_err(|_| ())?;
    if probe.method.starts_with("morphir.model-originals.") {
        if raw.len() > super::model_originals::wire::MAX_REQUEST_BYTES {
            return Err(());
        }
        let value = morphir_mck::json::parse_exact_document(raw).map_err(|_| ())?;
        let map = value.as_object().ok_or(())?;
        if map.len() != 4
            || !["jsonrpc", "id", "method", "params"]
                .iter()
                .all(|key| map.contains_key(*key))
            || value["jsonrpc"] != "2.0"
        {
            return Err(());
        }
        #[derive(Deserialize)]
        struct RawId<'a> {
            #[serde(borrow)]
            id: &'a serde_json::value::RawValue,
        }
        let raw_id: RawId<'_> = serde_json::from_str(raw).map_err(|_| ())?;
        if raw_id.id.get().is_empty() || !raw_id.id.get().bytes().all(|b| b.is_ascii_digit()) {
            return Err(());
        }
        let id = raw_id.id.get().parse::<u64>().map_err(|_| ())?;
        let method = match probe.method.as_str() {
            "morphir.model-originals.capture" => ConnectedMethod::ModelOriginalsCapture,
            "morphir.model-originals.inventory" => ConnectedMethod::ModelOriginalsInventory,
            "morphir.model-originals.read" => ConnectedMethod::ModelOriginalsRead,
            "morphir.model-originals.release" => ConnectedMethod::ModelOriginalsRelease,
            _ => return Err(()),
        };
        return Ok(JsonRpcRequest {
            jsonrpc: super::protocol::JsonRpcVersion::V2,
            id,
            method,
            params: value["params"].clone(),
        });
    }
    if matches!(
        probe.method.as_str(),
        "morphir.artifacts.generate" | "morphir.artifacts.read" | "morphir.artifacts.release"
    ) {
        let limit = if probe.method == "morphir.artifacts.generate" {
            super::artifacts::MAX_GENERATE_REQUEST_BYTES
        } else {
            super::artifacts::MAX_CONTROL_REQUEST_BYTES
        };
        if raw.len() > limit {
            return Err(());
        }
        let value = morphir_mck::json::parse_exact_document(raw).map_err(|_| ())?;
        let mut fields =
            super::artifacts::closed_object(value, &["jsonrpc", "id", "method", "params"])
                .map_err(|_| ())?;
        if fields["jsonrpc"] != "2.0" {
            return Err(());
        }
        let id = fields["id"].as_u64().ok_or(())?;
        let method = match fields["method"].as_str() {
            Some("morphir.artifacts.generate") => ConnectedMethod::ArtifactsGenerate,
            Some("morphir.artifacts.read") => ConnectedMethod::ArtifactsRead,
            Some("morphir.artifacts.release") => ConnectedMethod::ArtifactsRelease,
            _ => return Err(()),
        };
        // Value::Deserialize may reinterpret serde's private marker maps.
        // Move literal params directly rather than deserialize them again.
        Ok(JsonRpcRequest {
            jsonrpc: super::protocol::JsonRpcVersion::V2,
            id,
            method,
            params: fields.remove("params").expect("closed params"),
        })
    } else {
        serde_json::from_str(raw).map_err(|_| ())
    }
}

fn artifact_rpc_error(id: u64, error: super::artifacts::ArtifactError) -> DispatchResult {
    let mut response = DispatchResult::error(id, INVALID_PARAMS, &error.to_string());
    response.envelope["error"]["data"] = json!({ "profile": super::artifacts::PROFILE, "contractVersion": super::artifacts::CONTRACT_VERSION, "code": error.code() });
    response
}

fn artifact_profile_available(host: &UiHostState, provider_id: Option<&str>) -> bool {
    let Some(provider) = host.current.playground() else {
        return false;
    };
    let current = provider.manifest();
    current.status == super::protocol::ProviderStatus::Available
        && provider_id.is_none_or(|id| id == current.id)
        && current.capabilities.iter().any(|offer| {
            offer.name == super::artifacts::PROFILE
                && offer.version == super::artifacts::CONTRACT_VERSION
        })
        && host.manifest.providers.iter().any(|captured| {
            captured.id == current.id
                && captured.status == super::protocol::ProviderStatus::Available
                && captured.capabilities.iter().any(|offer| {
                    offer.name == super::artifacts::PROFILE
                        && offer.version == super::artifacts::CONTRACT_VERSION
                })
        })
}

async fn dispatch_artifacts(
    host: &UiHostState,
    state: &mut ConnectionState,
    request: &JsonRpcRequest,
) -> DispatchResult {
    use super::artifacts::*;
    if !state.initialized || !artifact_profile_available(host, None) {
        return artifact_rpc_error(request.id, ArtifactError::Unavailable);
    }
    match request.method {
        ConnectedMethod::ArtifactsGenerate => {
            let params = match decode_generate(&request.params.to_string()) {
                Ok(params) => params,
                Err(error) => return artifact_rpc_error(request.id, error),
            };
            if !artifact_profile_available(host, Some(params.provider_id.as_str())) {
                return artifact_rpc_error(request.id, ArtifactError::Unavailable);
            }
            if let Err(error) = state.artifacts.begin(&host.artifact_capacity) {
                return if error == ArtifactError::Capacity {
                    DispatchResult::result(request.id, json!(ArtifactFailure::error(error)))
                } else {
                    artifact_rpc_error(request.id, error)
                };
            }
            let _invocation = match host.artifact_capacity.reserve_invocation() {
                Ok(permit) => permit,
                Err(error) => {
                    state.artifacts.fail();
                    return DispatchResult::result(
                        request.id,
                        json!(ArtifactFailure::error(error)),
                    );
                }
            };
            let target = params.generation.target().clone();
            let ir_version = params.generation.ir_version().clone();
            let provider = host.current.playground().expect("offered playground");
            let generated = match provider.generate_artifacts(params.generation).await {
                Ok(Some(generated)) => generated,
                Ok(None) => {
                    state.artifacts.fail();
                    return artifact_rpc_error(request.id, ArtifactError::Unavailable);
                }
                Err(error) => {
                    tracing::warn!(%error, "Negotiated artifact generation failed");
                    state.artifacts.fail();
                    return DispatchResult::result(
                        request.id,
                        json!(ArtifactFailure::generation_failed()),
                    );
                }
            };
            let diagnostics = match ArtifactDiagnostics::from_sdk(&generated.result.diagnostics) {
                Ok(diagnostics) => diagnostics,
                Err(error) => {
                    state.artifacts.fail();
                    return DispatchResult::result(
                        request.id,
                        json!(ArtifactFailure::error(error)),
                    );
                }
            };
            if !generated.result.success {
                state.artifacts.fail();
                return DispatchResult::result(
                    request.id,
                    json!(ArtifactFailure::diagnostics(diagnostics)),
                );
            }
            let retained = SessionId::parse(&host.manifest.session_id)
                .and_then(|session| {
                    Producer::parse(&generated.producer.id, &generated.producer.version).map(
                        |producer| {
                            GenerationContext::new(
                                session,
                                params.provider_id,
                                target,
                                ir_version,
                                producer,
                            )
                        },
                    )
                })
                .and_then(|context| {
                    PreparedArtifacts::inspect(generated.result.artifacts).and_then(|prepared| {
                        state.artifacts.retain(
                            prepared,
                            context,
                            diagnostics,
                            &host.artifact_capacity,
                        )
                    })
                });
            match retained {
                Ok(manifest) => DispatchResult::result(request.id, json!(manifest)),
                Err(error) => {
                    state.artifacts.fail();
                    DispatchResult::result(request.id, json!(ArtifactFailure::error(error)))
                }
            }
        }
        ConnectedMethod::ArtifactsRead => {
            let params = match decode_read(&request.params.to_string()) {
                Ok(params) => params,
                Err(error) => return artifact_rpc_error(request.id, error),
            };
            match state.artifacts.read(
                &params.generation_id,
                &params.artifact_id,
                params.offset,
                params.max_bytes,
            ) {
                Ok(chunk) => DispatchResult::result(request.id, json!(chunk)),
                Err(error) => artifact_rpc_error(request.id, error),
            }
        }
        ConnectedMethod::ArtifactsRelease => {
            let params = match decode_release(&request.params.to_string()) {
                Ok(params) => params,
                Err(error) => return artifact_rpc_error(request.id, error),
            };
            match state.artifacts.release(&params.generation_id) {
                Ok(()) => DispatchResult::result(request.id, json!({})),
                Err(error) => artifact_rpc_error(request.id, error),
            }
        }
        _ => unreachable!("artifact dispatch only"),
    }
}

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
    artifacts: super::artifacts::ArtifactSession,
    originals: model_originals::OriginalSession,
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
            artifacts: super::artifacts::ArtifactSession::default(),
            originals: model_originals::OriginalSession::new(Default::default()),
        }
    }
}

async fn serve_socket(mut socket: WebSocket, host: UiHostState) {
    let mut state = ConnectionState {
        originals: model_originals::OriginalSession::new(host.original_capacity.clone()),
        ..Default::default()
    };
    let refresh_interval = host
        .capabilities
        .workspace
        .as_ref()
        .map_or(std::time::Duration::from_millis(500), |workspace| {
            workspace.watch_refresh_interval()
        });
    let mut watch_interval = tokio::time::interval(refresh_interval);
    watch_interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
    // One bounded request may wait behind an active operation. Continue reading
    // control frames so a Ping or ordinary pipelined request is not a disconnect.
    let mut queued = None;
    loop {
        tokio::select! {
            message = async { match queued.take() { Some(message) => Some(Ok(message)), None => socket.recv().await } } => {
                let Some(message) = message else {
                    break;
                };
                let Ok(message) = message else {
                    break;
                };
                let text = match message {
                    Message::Text(text) => text,
                    Message::Ping(bytes) => { if socket.send(Message::Pong(bytes)).await.is_err() { break; } continue; },
                    Message::Pong(_) => continue,
                    _ => { let _ = socket.send(Message::Close(None)).await; break; },
                };
                if text.len() > MAX_INBOUND_MESSAGE_BYTES {
                    let _ = socket.send(Message::Close(None)).await;
                    break;
                }
                let Ok(request) = decode_rpc_request(&text) else {
                    let failure = if selects_originals(&text) {
                        model_originals::invalid_frame(Value::Null)
                    } else { rpc_error(Value::Null, -32600, "Invalid Request") };
                    if send_profile_value(&mut socket, failure)
                    .await
                    .is_err()
                    {
                        break;
                    }
                    continue;
                };
                if let Err(error) = state.ledger.register(request.id) {
                    let failure = if request.method.is_model_originals() { model_originals::invalid_frame(json!(request.id)) } else { rpc_error(json!(request.id), -32600, &error.to_string()) };
                    let _ = send_profile_value(&mut socket, failure)
                    .await;
                    break;
                }
                if !state.initialized && request.method != ConnectedMethod::Initialize {
                    let failure = if request.method.is_model_originals() { model_originals::invalid_frame(json!(request.id)) } else { rpc_error(
                            json!(request.id),
                            -32001,
                            "morphir.session.initialize must be the first call",
                        ) };
                    let _ = send_profile_value(&mut socket, failure)
                    .await;
                    break;
                }
                // Keep receiving while a capture worker awaits the real compile
                // lock. Observed disconnect must cancel its owner immediately;
                // the worker itself retains its credit through actual exit.
                let response = if request.method.is_model_originals() {
                    let pending = dispatch(&host, &mut state, &request);
                    tokio::pin!(pending);
                    loop {
                        tokio::select! {
                            response = &mut pending => break Some(response),
                            message = socket.recv() => match message {
                                Some(Ok(Message::Ping(bytes))) => {
                                    if !matches!(tokio::time::timeout(std::time::Duration::from_secs(30), socket.send(Message::Pong(bytes))).await, Ok(Ok(()))) { break None; }
                                },
                                Some(Ok(Message::Pong(_))) => {},
                                Some(Ok(Message::Text(text))) if queued.is_none() && text.len() <= MAX_INBOUND_MESSAGE_BYTES => queued = Some(Message::Text(text)),
                                Some(Ok(Message::Text(_))) => {
                                    let _ = send_profile_value(&mut socket, model_originals::invalid_frame(Value::Null)).await;
                                    break None;
                                },
                                _ => break None,
                            },
                        }
                    }
                } else { Some(dispatch(&host, &mut state, &request).await) };
                let Some(response) = response else { break; };
                let watch_snapshot = response.watch_snapshot.clone();
                let subscription_id = response.subscription_id.clone();
                let sent = if request.method.is_model_originals() { send_profile_value(&mut socket, response.envelope).await } else { send_value(&mut socket, response.envelope).await };
                if sent.is_err() {
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
    state.originals.close();
}

async fn refresh_subscriptions(
    socket: &mut WebSocket,
    host: &UiHostState,
    state: &mut ConnectionState,
) -> Result<(), ()> {
    // Subscriptions are only ever created by the `morphir.workspace.watch`
    // arm, which itself requires a workspace capability, so an absent
    // workspace here means there is nothing pending to refresh.
    let workspace = host.current.workspace();
    let pending = state
        .subscriptions
        .iter()
        .map(|(id, subscription)| (id.clone(), subscription.source.clone()))
        .collect::<Vec<_>>();
    for (subscription_id, source) in pending {
        let Some(workspace) = &workspace else {
            if state
                .subscriptions
                .get(&subscription_id)
                .is_some_and(|subscription| !subscription.refresh_failed)
            {
                send_provider_disconnected_event(
                    socket,
                    &subscription_id,
                    &source.provider_id,
                    "Workspace capability was revoked",
                )
                .await?;
                if let Some(subscription) = state.subscriptions.get_mut(&subscription_id) {
                    subscription.refresh_failed = true;
                }
            }
            continue;
        };
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
    if request.method.is_model_originals() {
        return model_originals::dispatch_originals(host, state, request).await;
    }
    match request.method {
        ConnectedMethod::ModelOriginalsCapture
        | ConnectedMethod::ModelOriginalsInventory
        | ConnectedMethod::ModelOriginalsRead
        | ConnectedMethod::ModelOriginalsRelease => unreachable!("dispatched model originals"),
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
            let Some(workspace) = host.current.workspace() else {
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
            let Some(workspace) = host.current.workspace() else {
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
            let Some(workspace) = host.current.workspace() else {
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
            let Some(workspace) = host.current.workspace() else {
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
            let Some(playground) = host.current.playground() else {
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
            let Some(playground) = host.current.playground() else {
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
            let Some(playground) = host.current.playground() else {
                return capability_unavailable(request.id, "playground");
            };
            match playground.generate(params).await {
                Ok(result) => DispatchResult::result(request.id, json!(result)),
                Err(error) => provider_failure(request.id, &error),
            }
        }
        ConnectedMethod::ArtifactsGenerate
        | ConnectedMethod::ArtifactsRead
        | ConnectedMethod::ArtifactsRelease => dispatch_artifacts(host, state, request).await,
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
/// `morphir_extension_sdk::protocol::error_codes::CAPABILITY_UNAVAILABLE`
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
            current: super::super::provider::current::CurrentSessionCapabilities::new(
                capabilities.clone(),
            ),
            capabilities,
            initial_view: None,
            authority: "127.0.0.1:0".into(),
            artifact_capacity: super::super::artifacts::HostArtifactCapacity::default(),
            original_capacity: Default::default(),
        }
    }

    fn state_with_playground() -> UiHostState {
        host_state(SessionCapabilities {
            playground: Some(std::sync::Arc::new(StubPlayground)),
            ..Default::default()
        })
    }

    #[test]
    fn artifact_raw_frames_keep_duplicates_and_fractional_tokens_before_conversion() {
        let raw = r#"{"jsonrpc":"2.0","id":1,"method":"morphir.artifacts.read","params":{"contractVersion":"0.1.0-draft.1","generationId":"g","artifactId":"a","offset":1e-9999,"maxBytes":1}}"#;
        let request = decode_rpc_request(raw).unwrap();
        assert_eq!(
            super::super::artifacts::decode_read(&request.params.to_string()).unwrap_err(),
            super::super::artifacts::ArtifactError::InvalidRange
        );
        assert!(
            decode_rpc_request(&raw.replace("\"offset\":1e-9999", "\"offset\":0,\"offset\":1"))
                .is_err()
        );
        assert!(decode_rpc_request(&raw.replace("\"g\"", r#""\ud800""#)).is_err());
        assert!(
            decode_rpc_request(&raw.replace(
                "\"maxBytes\":1",
                &format!("\"maxBytes\":1,\"padding\":\"{}\"", "x".repeat(16384))
            ))
            .is_err()
        );
    }

    #[test]
    fn artifact_rpc_literal_objects_cannot_impersonate_serde_private_numbers() {
        let raw = r#"{"jsonrpc":"2.0","id":1,"method":"morphir.artifacts.read","params":{"contractVersion":"0.1.0-draft.1","generationId":"g","artifactId":"a","offset":{"$serde_json::private::Number":"1"},"maxBytes":1}}"#;
        let request = decode_rpc_request(raw).unwrap();
        assert!(request.params["offset"].is_object());
        assert_eq!(
            super::super::artifacts::decode_read(&request.params.to_string()).unwrap_err(),
            super::super::artifacts::ArtifactError::InvalidRange
        );
        let raw = r#"{"jsonrpc":"2.0","id":2,"method":"morphir.artifacts.generate","params":{"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":{"$serde_json::private::Number":"1"},"irVersion":"4","target":"fixture","options":{"$serde_json::private::RawValue":"{\"x\":1,\"x\":2}"}}}}"#;
        let request = decode_rpc_request(raw).unwrap();
        let generation = super::super::artifacts::decode_generate(&request.params.to_string())
            .unwrap()
            .generation
            .into_playground();
        assert_eq!(generation.ir["$serde_json::private::Number"], "1");
        assert_eq!(
            generation.options["$serde_json::private::RawValue"],
            r#"{"x":1,"x":2}"#
        );
    }

    #[tokio::test]
    async fn artifact_methods_refuse_uninitialized_or_unoffered_capabilities() {
        let host = state_with_playground();
        let request = decode_rpc_request(r#"{"jsonrpc":"2.0","id":1,"method":"morphir.artifacts.generate","params":{"contractVersion":"0.1.0-draft.1","providerId":"playground","generation":{"ir":{},"irVersion":"4","target":"fixture","options":{}}}}"#).unwrap();
        let mut connection = ConnectionState::default();
        assert_eq!(
            dispatch(&host, &mut connection, &request).await.envelope["error"]["data"]["code"],
            "artifacts.unavailable"
        );
        connection.initialized = true;
        assert_eq!(
            dispatch(&host, &mut connection, &request).await.envelope["error"]["data"]["code"],
            "artifacts.unavailable"
        );
        assert_eq!(host.artifact_capacity.reserved_generations(), 0);
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

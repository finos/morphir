//! Drives the whole playground pipeline through the real HTTP and WebSocket
//! surface, so what a human already checked by hand cannot silently
//! regress: the `/launch` deep link redirects into the playground route and
//! mints a session cookie, `/api/session` reports protocol version 2 with a
//! `playground` provider, and the three `morphir.playground.*` JSON-RPC
//! methods work over `/rpc`.
//!
//! The playground capability here is a stub, not `NativePlaygroundProvider`.
//! A real provider needs an installed extension to compile or generate
//! anything, which a contributor's machine or a CI runner may not have;
//! `playground_provider.rs` and the unit tests in `provider/playground.rs`
//! already cover that provider directly, against a real (if extension-less)
//! Morphir home. What this test needs is hermetic coverage of everything
//! that crosses a module boundary in front of the provider: HTTP routing,
//! cookie authentication, the WebSocket upgrade, JSON-RPC dispatch, and wire
//! serialization of the catalog/compile/generate payloads in both
//! directions. A stub proves all of that; it just does not prove that a real
//! extension invocation round-trips, which is a different, already-covered
//! concern.
//!
//! The no-write guarantee is checked by running the whole exchange with the
//! process's working directory pointed at an empty scratch directory and
//! asserting it is still empty afterward. That is process-wide state, so
//! this file intentionally contains a single test.

use std::sync::Arc;

use axum::http::{StatusCode, header};
use futures_util::{SinkExt as _, StreamExt as _};
use morphir::CliError;
use morphir::commands::ui::protocol::{
    CONNECTED_PROTOCOL_VERSION, InitialView, PlaygroundArtifact, PlaygroundCatalog,
    PlaygroundCompileParams, PlaygroundCompileResult, PlaygroundFrontend, PlaygroundGenerateParams,
    PlaygroundGenerateResult, PlaygroundProviderOrigin, PlaygroundProviderRef, PlaygroundTarget,
    ProviderKind, ProviderManifest, ProviderStatus,
};
use morphir::commands::ui::provider::{PlaygroundCapability, SessionCapabilities};
use morphir::commands::ui::server::BoundUiHost;
use serde_json::{Value, json};
use tokio_tungstenite::{
    MaybeTlsStream, WebSocketStream, connect_async,
    tungstenite::{Message, client::IntoClientRequest as _},
};

/// A playground provider that returns fixed, non-trivial data instead of
/// launching a real extension, so the transport and dispatch layers can be
/// exercised without depending on what is installed on the test machine.
struct StubPlayground;

#[async_trait::async_trait]
impl PlaygroundCapability for StubPlayground {
    fn manifest(&self) -> ProviderManifest {
        ProviderManifest {
            id: "playground".into(),
            name: "Stub Playground".into(),
            kind: ProviderKind::Connected,
            status: ProviderStatus::Available,
            capabilities: Vec::new(),
            provenance: None,
        }
    }

    async fn catalog(&self) -> Result<PlaygroundCatalog, CliError> {
        Ok(PlaygroundCatalog {
            frontends: vec![PlaygroundFrontend {
                language_id: "elm".into(),
                display_name: "Elm Frontend".into(),
                file_extensions: vec![".elm".into()],
                ir_versions: vec!["3".into()],
                compile: true,
                incremental: Some(false),
                fragments: Some(false),
                provider: PlaygroundProviderRef {
                    extension_id: "builtin.elm".into(),
                    extension_name: "Elm Frontend".into(),
                    version: "1.0.0".into(),
                    origin: PlaygroundProviderOrigin::Builtin,
                    invocation_mode: "native-direct".into(),
                },
            }],
            targets: vec![PlaygroundTarget {
                target: "json-schema".into(),
                display_name: "JSON Schema Backend".into(),
                ir_versions: vec!["3".into()],
                generate: true,
                provider: PlaygroundProviderRef {
                    extension_id: "builtin.json-schema".into(),
                    extension_name: "JSON Schema Backend".into(),
                    version: "1.0.0".into(),
                    origin: PlaygroundProviderOrigin::Builtin,
                    invocation_mode: "native-direct".into(),
                },
            }],
        })
    }

    async fn compile(
        &self,
        params: PlaygroundCompileParams,
    ) -> Result<PlaygroundCompileResult, CliError> {
        Ok(PlaygroundCompileResult {
            success: true,
            ir_version: Some(params.ir_version),
            ir: Some(json!({"formatVersion": 3, "distribution": []})),
            diagnostics: Vec::new(),
            modules: vec![format!("{}.Main", params.package.name)],
        })
    }

    async fn generate(
        &self,
        params: PlaygroundGenerateParams,
    ) -> Result<PlaygroundGenerateResult, CliError> {
        Ok(PlaygroundGenerateResult {
            success: true,
            artifacts: vec![PlaygroundArtifact {
                path: format!("out.{}", params.target),
                content: "generated content".into(),
                binary: false,
            }],
            diagnostics: Vec::new(),
        })
    }
}

/// Restores the process's working directory when dropped, so a panic
/// anywhere in the test still leaves the process pointed at a real
/// directory before the scratch `TempDir` deletes itself on its own drop.
/// `std::env::set_current_dir` is process-wide state, which is also why
/// this file holds exactly one test.
struct WorkingDirectoryGuard {
    original: std::path::PathBuf,
}

impl WorkingDirectoryGuard {
    fn switch_to(target: &std::path::Path) -> Self {
        let original = std::env::current_dir().expect("the current working directory");
        std::env::set_current_dir(target).expect("switching into the scratch working directory");
        Self { original }
    }
}

impl Drop for WorkingDirectoryGuard {
    fn drop(&mut self) {
        let _ = std::env::set_current_dir(&self.original);
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

async fn send_request(
    socket: &mut WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>,
    id: u64,
    method: &str,
    params: Value,
) {
    socket
        .send(Message::Text(
            json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params})
                .to_string()
                .into(),
        ))
        .await
        .expect("the request sends over the websocket");
}

async fn recv_response(
    socket: &mut WebSocketStream<MaybeTlsStream<tokio::net::TcpStream>>,
) -> Value {
    let message = socket
        .next()
        .await
        .expect("a response arrives before the socket closes")
        .expect("a valid websocket frame");
    serde_json::from_str(message.to_text().expect("a text frame")).expect("valid JSON-RPC")
}

#[tokio::test]
async fn the_playground_pipeline_works_end_to_end_over_http_and_websocket() {
    let workdir = tempfile::tempdir().expect("a scratch working directory");
    let _cwd_guard = WorkingDirectoryGuard::switch_to(workdir.path());

    let host = BoundUiHost::bind(
        "session-1".into(),
        SessionCapabilities {
            playground: Some(Arc::new(StubPlayground)),
            initial_view: Some(InitialView::Playground),
            ..Default::default()
        },
    )
    .await
    .expect("a playground-only session binds");
    let launch_url = host.launch_url();
    let base_url = host.base_url();
    let server = tokio::spawn(async move { host.serve().await });

    let client = reqwest::Client::builder()
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .expect("an http client");

    // The deep link a human already checked by hand: /launch redirects into
    // the playground route, not root, and mints a session cookie.
    let launched = client
        .get(&launch_url)
        .send()
        .await
        .expect("the launch request completes");
    assert_eq!(launched.status(), StatusCode::SEE_OTHER);
    assert_eq!(launched.headers()[header::LOCATION], "/#/playground");
    let cookie = launched.headers()[header::SET_COOKIE]
        .to_str()
        .expect("a set-cookie header")
        .split(';')
        .next()
        .expect("a cookie name=value pair")
        .to_owned();

    // The manifest the deep link lands on: protocol version 2, with a
    // playground provider advertised.
    let manifest_response = client
        .get(format!("{base_url}/api/session"))
        .header(header::COOKIE, &cookie)
        .send()
        .await
        .expect("the session manifest request completes");
    assert_eq!(manifest_response.status(), StatusCode::OK);
    let manifest: Value = manifest_response
        .json()
        .await
        .expect("the manifest is valid JSON");
    // Pinned to the literal 2, not CONNECTED_PROTOCOL_VERSION. A client in
    // another repository (morphir-ui, in TypeScript) decodes this field
    // against a schema that expects exactly 2; comparing against the same
    // constant the server used to produce it would only prove the server
    // agrees with itself, not that the wire contract held. Bumping this
    // literal must be a deliberate edit here, made in lockstep with that
    // client, not something that happens automatically because someone
    // changed the constant.
    assert_eq!(manifest["protocolVersion"], 2);
    let providers = manifest["providers"].as_array().expect("a providers array");
    assert!(
        providers
            .iter()
            .any(|provider| provider["id"] == "playground"),
        "manifest carried no playground provider: {manifest}"
    );

    // The JSON-RPC surface: initialize, then the three playground methods.
    let (mut socket, _) = connect_async(socket_request(&base_url, &cookie))
        .await
        .expect("the websocket upgrades");

    // The outbound protocolVersion is intentionally CONNECTED_PROTOCOL_VERSION,
    // not the literal: this mimics a real client, which reads the version off
    // the manifest it was just served (asserted above) and echoes it back. It
    // is the inbound checks -- what the server hands back -- that need the
    // literal pin.
    send_request(
        &mut socket,
        1,
        "morphir.session.initialize",
        json!({"protocolVersion": CONNECTED_PROTOCOL_VERSION, "sessionId": "session-1"}),
    )
    .await;
    let initialized = recv_response(&mut socket).await;
    // Same reasoning as the manifest check above: pinned to the literal.
    assert_eq!(
        initialized["result"]["protocolVersion"], 2,
        "initialize response: {initialized}"
    );

    send_request(&mut socket, 2, "morphir.playground.catalog", json!({})).await;
    let catalog_response = recv_response(&mut socket).await;
    let frontends = catalog_response["result"]["frontends"]
        .as_array()
        .unwrap_or_else(|| panic!("catalog result carried no frontends array: {catalog_response}"));
    let targets = catalog_response["result"]["targets"]
        .as_array()
        .unwrap_or_else(|| panic!("catalog result carried no targets array: {catalog_response}"));
    assert!(
        !frontends.is_empty(),
        "catalog carried no frontends: {catalog_response}"
    );
    assert!(
        !targets.is_empty(),
        "catalog carried no targets: {catalog_response}"
    );

    send_request(
        &mut socket,
        3,
        "morphir.playground.compile",
        json!({
            "languageId": "elm",
            "documents": [{
                "uri": "file:///Main.elm",
                "languageId": "elm",
                "version": 1,
                "text": "module Main exposing (..)\n"
            }],
            "package": {"name": "local/main", "exposedModules": ["Main"]},
            "irVersion": "3",
            "options": {}
        }),
    )
    .await;
    let compile_response = recv_response(&mut socket).await;
    let compiled: PlaygroundCompileResult =
        serde_json::from_value(compile_response["result"].clone())
            .expect("the compile result deserializes as a PlaygroundCompileResult");
    assert!(
        compiled.success,
        "compile did not report success: {compile_response}"
    );

    send_request(
        &mut socket,
        4,
        "morphir.playground.generate",
        json!({
            "ir": {"formatVersion": 3, "distribution": []},
            "irVersion": "3",
            "target": "json-schema",
            "options": {}
        }),
    )
    .await;
    let generate_response = recv_response(&mut socket).await;
    let generated: PlaygroundGenerateResult =
        serde_json::from_value(generate_response["result"].clone())
            .expect("the generate result deserializes as a PlaygroundGenerateResult");
    assert!(
        !generated.artifacts.is_empty(),
        "generate returned no artifacts: {generate_response}"
    );

    drop(socket);
    server.abort();

    let leftover: Vec<_> = walkdir::WalkDir::new(workdir.path())
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| entry.path().to_path_buf())
        .collect();
    assert!(
        leftover.is_empty(),
        "the playground pipeline wrote files to the working directory: {leftover:?}"
    );
}

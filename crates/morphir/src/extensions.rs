//! CLI-owned integration boundary for built-in and installed extension providers.

use crate::error::CliError;
use crate::home::MorphirHome;
use morphir_daemon::DaemonError;
use morphir_daemon::extensions::{
    FailedSession, Loaded, MepTransport, Session, SessionHandle, activate_transport,
    protocol::methods, spawn_session,
};
use morphir_distribution::{
    InstalledExtensionSnapshot, activate_installed_snapshot, list_installed,
};
use morphir_elm_binding::ElmExtension;
use morphir_extension_sdk::{
    CompileRequest, CompileResult, GenerateRequest, GenerateResult, NativeExtension,
};
use morphir_gleam_binding::GleamExtension;
use morphir_host::{InvocationMode, Registry, Resolved};
use morphir_host_native::process::ProcessLaunch;
use morphir_host_native::{InstalledSource, NativeSource};
use morphir_workspace::{DiscoveryRequest, DiscoveryResponse};
use serde::{Serialize, de::DeserializeOwned};
use std::path::Path;
use std::sync::Arc;

pub(crate) mod guest;
#[cfg(all(test, unix))]
pub(crate) mod installed_fixture;

/// Construct the complete provider registry used by one CLI command.
///
/// Installed providers start below `home` when they are invoked.
pub fn extension_registry(
    home: &MorphirHome,
    installed: impl IntoIterator<Item = InstalledExtensionSnapshot>,
) -> Result<Registry, CliError> {
    extension_registry_for(home, installed, None)
}

/// Construct the provider registry, optionally restricted to one provider id.
///
/// `--extension <id>` is a choice of provider, not a preference: the registry
/// resolves by language and origin, so the only way to make the caller's choice
/// binding is to leave every other provider out of the registry it resolves
/// against. A registry restricted to an id that provides nothing for the
/// requested language then fails resolution, which is the same answer as
/// "that extension does not provide this language".
///
/// The native Elm provider is opt-in: it is registered only when `only` names
/// it, so a command that does not ask for it by id behaves as though it were
/// not built in at all.
///
/// The former Gleam id is an alias for its native provider, unless an installed
/// extension still uses that id. An exact installed selection remains binding.
pub fn extension_registry_for(
    home: &MorphirHome,
    installed: impl IntoIterator<Item = InstalledExtensionSnapshot>,
    only: Option<&str>,
) -> Result<Registry, CliError> {
    let installed: Vec<_> = installed.into_iter().collect();
    let only = match only {
        Some("morphir-gleam-binding")
            if !installed.iter().any(|snapshot| {
                snapshot.installed().extension_id().as_str() == "morphir-gleam-binding"
            }) =>
        {
            Some("morphir-gleam")
        }
        selector => selector,
    };
    let mut registry = Registry::new();
    for (language, builtin, opt_in) in builtin_providers()? {
        let requested = only == Some(builtin.info().id.as_str());
        if (opt_in && !requested) || only.is_some_and(|id| id != builtin.info().id) {
            continue;
        }
        registry
            .register(Arc::new(NativeSource::new(builtin)))
            .map_err(|error| CliError::Extension {
                message: format!(
                    "Failed to register native {language} provider: {}",
                    DaemonError::from(error)
                ),
            })?;
    }
    for snapshot in installed {
        let id = snapshot.installed().extension_id().to_string();
        if only.is_some_and(|only| only != id) {
            continue;
        }
        let source = InstalledSource::new(home.clone(), snapshot);
        registry
            .register(Arc::new(guest::InstalledProvider::new(source)))
            .map_err(|error| CliError::Extension {
                message: format!(
                    "Failed to register installed provider '{id}': {}",
                    DaemonError::from(error)
                ),
            })?;
    }
    Ok(registry)
}

/// The built-in native providers: their language, the provider, and whether
/// it is registered only when selected by id.
fn builtin_providers() -> Result<[(&'static str, NativeExtension, bool); 2], CliError> {
    let gleam = NativeExtension::builder(GleamExtension)
        .with_frontend()
        .with_backend()
        .with_workspace()
        .finish()
        .map_err(|error| CliError::Extension {
            message: format!("Failed to construct native Gleam provider: {error}"),
        })?;
    let elm = NativeExtension::builder(ElmExtension)
        .with_frontend()
        .with_backend()
        .with_workspace()
        .finish()
        .map_err(|error| CliError::Extension {
            message: format!("Failed to construct native Elm provider: {error}"),
        })?;
    Ok([("Gleam", gleam, false), ("Elm", elm, true)])
}

/// Invoke a resolved frontend through only the mode selected by the registry.
///
/// `NativeDirect` calls the built-in's typed handle. Every other mode opens
/// the guest [`Resolved::connect`] starts, for one call.
pub async fn invoke_frontend(
    workspace: &Path,
    resolved: &Resolved,
    request: CompileRequest,
) -> Result<CompileResult, CliError> {
    request
        .source_paths()
        .map_err(|error| CliError::Validation {
            message: error.to_string(),
        })?;
    match resolved.invocation_mode() {
        InvocationMode::NativeDirect => {
            // A native provider compiles synchronously, so running it inline
            // would occupy this task until it returned: it would never reach
            // an await point, which costs a runtime worker for the duration
            // and leaves any timeout wrapped around this future unable to
            // fire. `spawn_blocking` moves the call off the runtime, so the
            // caller's future stays pollable and a caller that gave up
            // waiting really can stop waiting.
            let resolved = resolved.clone();
            blocking(resolved.info().id.clone(), move || {
                resolved
                    .native()
                    .and_then(NativeExtension::frontend)
                    .ok_or_else(|| {
                        unavailable_mode(resolved.info().id.as_str(), "native frontend")
                    })?
                    .compile(request)
                    .map_err(|error| CliError::Extension {
                        message: format!(
                            "Native frontend provider '{}' failed: {error}",
                            resolved.info().id
                        ),
                    })
            })
            .await
        }
        _ => {
            let provider = resolved.info().id.as_str();
            let connection = guest::connect(resolved, workspace).await?;
            guest::call_once(connection, provider, methods::COMPILE, &request).await
        }
    }
}

/// Ask a resolved frontend's provider to discover an ad-hoc source selection,
/// through only the mode selected by the registry.
///
/// A discovery refusal is a successful answer carrying
/// [`DiscoveryResponse::Failure`]; only a provider that could not answer at
/// all is an error here.
pub async fn invoke_workspace_discovery(
    workspace: &Path,
    resolved: &Resolved,
    request: DiscoveryRequest,
) -> Result<DiscoveryResponse, CliError> {
    match resolved.invocation_mode() {
        InvocationMode::NativeDirect => {
            let resolved = resolved.clone();
            blocking(resolved.info().id.clone(), move || {
                resolved
                    .native()
                    .and_then(NativeExtension::workspace)
                    .ok_or_else(|| {
                        unavailable_mode(resolved.info().id.as_str(), "native workspace")
                    })?
                    .discover(request)
                    .map_err(|error| CliError::Extension {
                        message: format!(
                            "Native workspace provider '{}' failed: {error}",
                            resolved.info().id
                        ),
                    })
            })
            .await
        }
        _ => {
            let provider = resolved.info().id.as_str();
            let connection = guest::connect(resolved, workspace).await?;
            guest::call_once(connection, provider, methods::WORKSPACE_DISCOVER, request).await
        }
    }
}

/// What a spawned process provider said about itself when a session was
/// negotiated with it.
#[derive(Debug, Clone)]
pub struct NegotiatedProvider {
    /// The extension's identity and declared roles.
    pub info: morphir_extension_sdk::ExtensionInfo,
    /// The capabilities the session negotiated.
    pub capabilities: morphir_extension_sdk::ExtensionCapabilities,
}

/// Start a process provider, negotiate a session, record what it declares,
/// and stop it again.
///
/// A provider configured by `[extensions.<id>] command` has no installed
/// record to read capabilities from, so the only way to learn them is to ask.
pub async fn probe_process(
    launch: ProcessLaunch,
    provider: &str,
) -> Result<NegotiatedProvider, CliError> {
    guest::negotiate(guest::configured(launch, provider).await?, provider).await
}

/// Start a process provider and invoke one method over a fresh session.
pub async fn invoke_process<P, R>(
    launch: ProcessLaunch,
    provider: &str,
    method: &str,
    request: P,
) -> Result<R, CliError>
where
    P: Serialize,
    R: DeserializeOwned,
{
    guest::call_once(
        guest::configured(launch, provider).await?,
        provider,
        method,
        request,
    )
    .await
}

/// Invoke a resolved backend through only the mode selected by the registry.
///
/// See [`invoke_frontend`] for how the mode selects the call.
pub async fn invoke_backend(
    workspace: &Path,
    resolved: &Resolved,
    request: GenerateRequest,
) -> Result<GenerateResult, CliError> {
    match resolved.invocation_mode() {
        InvocationMode::NativeDirect => {
            // See `invoke_frontend`: a native provider generates
            // synchronously and must not hold the runtime while it does.
            let resolved = resolved.clone();
            blocking(resolved.info().id.clone(), move || {
                resolved
                    .native()
                    .and_then(NativeExtension::backend)
                    .ok_or_else(|| unavailable_mode(resolved.info().id.as_str(), "native backend"))?
                    .generate(request)
                    .map_err(|error| CliError::Extension {
                        message: format!(
                            "Native backend provider '{}' failed: {error}",
                            resolved.info().id
                        ),
                    })
            })
            .await
        }
        _ => {
            let provider = resolved.info().id.as_str();
            let connection = guest::connect(resolved, workspace).await?;
            guest::call_once(connection, provider, methods::GENERATE, request).await
        }
    }
}

/// Open a long-lived session to a resolved frontend, or `None` when its
/// invocation mode has no session to hold.
///
/// The returned handle answers any number of MEP invocations over one
/// negotiated session, ends the session when the last clone is dropped, and
/// stops itself after five idle minutes. `None` is the native-direct case: an
/// in-process function call has no process and no handshake, so there is
/// nothing to keep warm, and the caller should use [`invoke_frontend`].
pub async fn open_frontend_session(
    home: &MorphirHome,
    workspace: &Path,
    resolved: &Resolved,
) -> Result<Option<SessionHandle>, CliError> {
    open_session(home, workspace, resolved, "frontend").await
}

/// Open a long-lived session to a resolved backend, or `None` when its
/// invocation mode has no session to hold. See [`open_frontend_session`].
pub async fn open_backend_session(
    home: &MorphirHome,
    workspace: &Path,
    resolved: &Resolved,
) -> Result<Option<SessionHandle>, CliError> {
    open_session(home, workspace, resolved, "backend").await
}

/// Open a daemon session for a provider the host registry resolved.
///
/// A temporary bridge for the workbench's session reuse, which still holds
/// daemon sessions: a [`Resolved`] does not lend its source back, so a
/// `NativeMep` built-in is built again by id, and an installed provider's
/// snapshot is read again from `home` by id.
async fn open_session(
    home: &MorphirHome,
    workspace: &Path,
    resolved: &Resolved,
    role: &str,
) -> Result<Option<SessionHandle>, CliError> {
    let provider = resolved.info().id.as_str();
    match resolved.invocation_mode() {
        InvocationMode::NativeDirect => Ok(None),
        InvocationMode::NativeMep => {
            let native = builtin_providers()?
                .into_iter()
                .map(|(_, builtin, _)| builtin)
                .find(|builtin| builtin.info().id == provider)
                .ok_or_else(|| unavailable_mode(provider, &format!("native MEP {role}")))?;
            let loaded =
                Session::loaded(morphir_daemon::extensions::NativeMepTransport::new(native));
            Ok(Some(open_loaded(loaded, provider).await?))
        }
        _ => {
            let snapshot = list_installed(home)
                .map_err(|error| CliError::Extension {
                    message: format!("Failed to list installed extensions: {error}"),
                })?
                .into_iter()
                .find(|snapshot| snapshot.installed().extension_id().as_str() == provider)
                .ok_or_else(|| unavailable_mode(provider, &format!("installed MEP {role}")))?;
            let loaded = installed_loaded(home, workspace, &snapshot, provider).await?;
            Ok(Some(open_loaded(loaded, provider).await?))
        }
    }
}

/// Initialize a loaded session and hand it to an actor that owns it.
async fn open_loaded<T: MepTransport + Send + 'static>(
    loaded: Session<T, Loaded>,
    provider: &str,
) -> Result<SessionHandle, CliError> {
    let ready = loaded
        .initialize(crate::commands::extension::host_config().initialize_params())
        .await
        .map_err(|failure| session_failure(provider, "initialize", failure))?;
    Ok(spawn_session(ready))
}

/// Run one synchronous provider call off the async runtime.
///
/// A provider that panics takes its blocking thread with it rather than the
/// process, so the join failure is reported as an extension failure: the
/// caller asked an extension to do something and the extension did not
/// answer, which is the same shape as any other invocation error.
async fn blocking<R>(
    provider: String,
    call: impl FnOnce() -> Result<R, CliError> + Send + 'static,
) -> Result<R, CliError>
where
    R: Send + 'static,
{
    match tokio::task::spawn_blocking(call).await {
        Ok(result) => result,
        Err(error) => Err(CliError::Extension {
            message: format!("Native provider '{provider}' did not complete: {error}"),
        }),
    }
}

fn unavailable_mode(provider: &str, mode: &str) -> CliError {
    CliError::Extension {
        message: format!("Resolved provider '{provider}' did not expose its selected {mode} mode"),
    }
}

/// Verify and activate an installed extension into a loaded session.
async fn installed_loaded(
    home: &MorphirHome,
    workspace: &Path,
    snapshot: &InstalledExtensionSnapshot,
    provider: &str,
) -> Result<Session<morphir_daemon::extensions::BoxedMepTransport, Loaded>, CliError> {
    let artifact =
        activate_installed_snapshot(home, snapshot).map_err(|error| CliError::Extension {
            message: format!("Failed to verify installed provider '{provider}': {error}"),
        })?;
    activate_transport(artifact, workspace)
        .await
        .map_err(|error| CliError::Extension {
            message: format!("Failed to activate installed provider '{provider}': {error}"),
        })
}

fn session_failure<T>(provider: &str, operation: &str, failure: FailedSession<T>) -> CliError {
    CliError::Extension {
        message: format!(
            "Provider '{provider}' failed during {operation}: {}",
            failed_session_message(&failure)
        ),
    }
}

fn failed_session_message<T>(failure: &FailedSession<T>) -> String {
    match failure {
        FailedSession::Stopped(_, error) => error.to_string(),
        FailedSession::Indeterminate(_, error) => {
            format!("{error}; transport state is indeterminate")
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        extension_registry, invoke_backend, invoke_frontend, open_backend_session,
        open_frontend_session,
    };
    use crate::home::MorphirHome;
    use morphir_extension_sdk::{
        CompileOptions, CompilePackage, CompileRequest, GenerateRequest, SourceDocument, SourceSet,
    };
    use morphir_host::{InvocationPolicy, Registry, Resolved};
    use serde_json::json;
    use std::collections::HashMap;
    use std::path::Path;

    #[test]
    fn host_initialize_identifies_cli_kind() {
        let params = crate::commands::extension::host_config().initialize_params();
        assert_eq!(
            params.host.kind,
            morphir_extension_sdk::protocol::PeerKind::Cli
        );
        assert_eq!(params.host.name, "morphir-cli");
    }

    #[test]
    fn gleam_native_selectors_resolve_to_the_same_native_provider() {
        let temp = tempfile::tempdir().unwrap();
        let home = MorphirHome::resolve_from(Some(temp.path().as_os_str()), None).unwrap();
        for selector in [None, Some("morphir-gleam"), Some("morphir-gleam-binding")] {
            let registry = super::extension_registry_for(&home, [], selector).unwrap();
            for policy in [
                InvocationPolicy::PreferDirect,
                InvocationPolicy::ProtocolOnly,
            ] {
                let frontend = registry.resolve_frontend("gleam", "4", policy).unwrap();
                let backend = registry.resolve_backend("gleam", "4", policy).unwrap();
                assert_eq!(frontend.info().id, "morphir-gleam");
                assert_eq!(backend.info().id, "morphir-gleam");
                let expected = match policy {
                    InvocationPolicy::PreferDirect => super::InvocationMode::NativeDirect,
                    InvocationPolicy::ProtocolOnly => super::InvocationMode::NativeMep,
                };
                assert_eq!(frontend.invocation_mode(), expected);
                assert_eq!(backend.invocation_mode(), expected);
                assert!(frontend.capabilities().workspace.is_some());
                if policy == InvocationPolicy::PreferDirect {
                    assert!(frontend.native().unwrap().workspace().is_some());
                }
            }
        }
    }

    fn compile_request(output_dir: &Path) -> CompileRequest {
        CompileRequest {
            language_id: "gleam".into(),
            sources: SourceSet {
                root: Some("file:///workspace/src".into()),
                documents: vec![SourceDocument {
                    uri: "file:///workspace/src/main.gleam".into(),
                    language_id: "gleam".into(),
                    version: 1,
                    text: "pub fn hello() {\n  \"world\"\n}\n".into(),
                }],
            },
            package: CompilePackage {
                name: "example/hello".into(),
                exposed_modules: Some(vec![]),
            },
            dependencies: vec![],
            baseline: None,
            options: CompileOptions {
                types_only: false,
                ir_version: "4.0.0".into(),
                extra: HashMap::from([
                    ("outputDir".into(), json!(output_dir)),
                    ("emitParseStage".into(), json!(false)),
                    ("emitParseStageFatal".into(), json!(false)),
                ]),
            },
        }
    }

    fn resolve_frontend(registry: &Registry, policy: InvocationPolicy) -> Resolved {
        registry.resolve_frontend("gleam", "4.0.0", policy).unwrap()
    }

    fn resolve_backend(registry: &Registry, policy: InvocationPolicy) -> Resolved {
        registry.resolve_backend("gleam", "4.0.0", policy).unwrap()
    }

    // Requirement: a session opened once answers many invocations, and answers
    // them identically to the one-shot path. This is what the playground's
    // session reuse stands on: reuse must change the cost of a compile, never
    // its result.
    #[tokio::test]
    async fn an_open_session_answers_repeated_invocations_like_the_one_shot_path() {
        let temp = tempfile::tempdir().unwrap();
        let home =
            MorphirHome::resolve_from(Some(temp.path().join("home").as_os_str()), None).unwrap();
        let registry = extension_registry(&home, []).unwrap();
        let resolved = resolve_frontend(&registry, InvocationPolicy::ProtocolOnly);
        let request = compile_request(&temp.path().join("compile"));

        let handle = open_frontend_session(&home, temp.path(), &resolved)
            .await
            .unwrap()
            .expect("a native MEP frontend has a session to open");
        let first: morphir_extension_sdk::CompileResult = handle
            .invoke(
                morphir_daemon::extensions::protocol::methods::COMPILE,
                &request,
            )
            .await
            .unwrap();
        let second: morphir_extension_sdk::CompileResult = handle
            .invoke(
                morphir_daemon::extensions::protocol::methods::COMPILE,
                &request,
            )
            .await
            .unwrap();
        let one_shot = invoke_frontend(temp.path(), &resolved, request)
            .await
            .unwrap();
        handle.shutdown().await.unwrap();

        assert_eq!(
            serde_json::to_value(&first).unwrap(),
            serde_json::to_value(&second).unwrap()
        );
        assert_eq!(
            serde_json::to_value(&second).unwrap(),
            serde_json::to_value(&one_shot).unwrap()
        );
    }

    #[tokio::test]
    async fn a_backend_session_opens_and_generates() {
        let temp = tempfile::tempdir().unwrap();
        let home =
            MorphirHome::resolve_from(Some(temp.path().join("home").as_os_str()), None).unwrap();
        let registry = extension_registry(&home, []).unwrap();
        let compiled = invoke_frontend(
            temp.path(),
            &resolve_frontend(&registry, InvocationPolicy::PreferDirect),
            compile_request(&temp.path().join("compile")),
        )
        .await
        .unwrap();

        let resolved = resolve_backend(&registry, InvocationPolicy::ProtocolOnly);
        let handle = open_backend_session(&home, temp.path(), &resolved)
            .await
            .unwrap()
            .expect("a native MEP backend has a session to open");
        let generated: morphir_extension_sdk::GenerateResult = handle
            .invoke(
                morphir_daemon::extensions::protocol::methods::GENERATE,
                &GenerateRequest {
                    ir: compiled.ir.unwrap(),
                    target: "gleam".into(),
                    options: HashMap::new(),
                },
            )
            .await
            .unwrap();
        handle.shutdown().await.unwrap();

        assert!(generated.success);
    }

    // A native-direct provider is an in-process function call: there is no
    // process and no negotiated session, so there is nothing to keep warm.
    // `None` tells the caller to use the one-shot path, rather than an error
    // telling them something went wrong.
    #[tokio::test]
    async fn a_native_direct_provider_has_no_session_to_open() {
        let temp = tempfile::tempdir().unwrap();
        let home =
            MorphirHome::resolve_from(Some(temp.path().join("home").as_os_str()), None).unwrap();
        let registry = extension_registry(&home, []).unwrap();

        let frontend = open_frontend_session(
            &home,
            temp.path(),
            &resolve_frontend(&registry, InvocationPolicy::PreferDirect),
        )
        .await
        .unwrap();
        let backend = open_backend_session(
            &home,
            temp.path(),
            &resolve_backend(&registry, InvocationPolicy::PreferDirect),
        )
        .await
        .unwrap();

        assert!(frontend.is_none());
        assert!(backend.is_none());
    }

    /// A configured process provider that speaks MEP over stdio and refuses
    /// every compile with an RPC error.
    #[cfg(unix)]
    fn rejecting_provider(directory: &Path) -> std::path::PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let python = std::process::Command::new("sh")
            .args(["-c", "command -v python3"])
            .output()
            .unwrap();
        assert!(python.status.success(), "python3 is required for this test");
        let python = String::from_utf8(python.stdout).unwrap();
        let script = format!(
            r#"#!{python}
import json
import sys

def receive():
    length = None
    while True:
        line = sys.stdin.buffer.readline()
        if line in (b"\n", b"\r\n"):
            break
        if not line:
            raise SystemExit(0)
        name, value = line.decode("ascii").split(":", 1)
        if name.lower() == "content-length":
            length = int(value.strip())
    return json.loads(sys.stdin.buffer.read(length))

def send(message):
    message["jsonrpc"] = "2.0"
    body = json.dumps(message, separators=(",", ":")).encode()
    sys.stdout.buffer.write(
        b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body
    )
    sys.stdout.buffer.flush()

while True:
    request = receive()
    method = request["method"]
    if "id" not in request:
        if method == "morphir.exit":
            raise SystemExit(0)
        continue
    identifier = request["id"]
    if method == "morphir.initialize":
        send({{"id": identifier, "result": {{
            "protocolVersion": "0.1",
            "extension": {{
                "id": "fixture",
                "name": "Rejecting fixture",
                "version": "1.0.0",
                "types": ["frontend"],
            }},
            "capabilities": {{
                "frontend": {{
                    "languages": [{{"id": "gleam", "fileExtensions": [".gleam"]}}],
                    "irVersions": ["4.0.0"],
                    "compile": True,
                    "incremental": False,
                    "fragments": False,
                }}
            }},
        }}}})
    elif method == "morphir.frontend.compile":
        send({{"id": identifier, "error": {{"code": -32001, "message": "does not compile"}}}})
    elif method == "morphir.shutdown":
        send({{"id": identifier, "result": {{}}}})
    else:
        send({{"id": identifier, "error": {{"code": -32601, "message": "unknown"}}}})
"#,
            python = python.trim()
        );
        let path = directory.join("rejecting-provider");
        std::fs::write(&path, script).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
        path
    }

    // The text a configured provider's rejected call produces is part of the
    // CLI's contract: it must not change when the session machinery does.
    #[cfg(unix)]
    #[tokio::test]
    async fn a_configured_provider_rejecting_compile_keeps_the_rejected_text() {
        let temp = tempfile::tempdir().unwrap();
        let program = rejecting_provider(temp.path());
        let launch = super::ProcessLaunch::new("fixture", program, temp.path());

        let error = super::invoke_process::<_, morphir_extension_sdk::CompileResult>(
            launch,
            "fixture",
            morphir_extension_sdk::protocol::methods::COMPILE,
            &compile_request(&temp.path().join("compile")),
        )
        .await
        .unwrap_err();

        match error {
            crate::error::CliError::Extension { message } => assert_eq!(
                message,
                "Provider 'fixture' rejected 'morphir.frontend.compile': Extension error: RPC error -32001: does not compile"
            ),
            other => panic!("expected an extension error, got {other:?}"),
        }
    }

    // Probing a configured provider opens a session, reads what it
    // negotiated, and closes the session in order.
    #[cfg(unix)]
    #[tokio::test]
    async fn probing_a_configured_provider_reads_what_it_negotiated() {
        let temp = tempfile::tempdir().unwrap();
        let program = rejecting_provider(temp.path());
        let launch = super::ProcessLaunch::new("fixture", program, temp.path());

        let negotiated = super::probe_process(launch, "fixture").await.unwrap();

        assert_eq!(negotiated.info.id, "fixture");
        assert!(negotiated.capabilities.frontend.is_some());
    }

    // An installed provider's rejected call reads exactly like a configured
    // provider's: the session machinery under it must not change the text.
    #[cfg(unix)]
    #[tokio::test]
    async fn an_installed_provider_rejecting_compile_keeps_the_rejected_text() {
        let temp = tempfile::tempdir().unwrap();
        let frontend = json!({
            "languages": [{"id": "gleam", "fileExtensions": [".gleam"]}],
            "irVersions": ["4.0.0"],
            "compile": true,
        });
        let guest = super::installed_fixture::mep_guest(
            &json!({
                "protocolVersion": "0.1",
                "extension": {
                    "id": "fixture",
                    "name": "Rejecting fixture",
                    "version": "1.0.0",
                    "types": ["frontend"],
                },
                "capabilities": {"frontend": {
                    "languages": [{"id": "gleam", "fileExtensions": [".gleam"]}],
                    "irVersions": ["4.0.0"],
                    "compile": true,
                    "incremental": false,
                    "fragments": false,
                }},
            }),
            &json!({
                morphir_extension_sdk::protocol::methods::COMPILE: {
                    "error": {"code": -32001, "message": "does not compile"}
                }
            }),
        );
        let (home, snapshot) = super::installed_fixture::install_process(
            temp.path(),
            json!({
                "schemaVersion": "1.0",
                "id": "fixture",
                "name": "Rejecting fixture",
                "version": "1.0.0",
                "channels": ["stable"],
                "mepVersions": ["0.1"],
                "capabilities": ["frontend"],
                "frontend": frontend,
            }),
            &guest,
        );
        let registry = super::extension_registry_for(&home, [snapshot], Some("fixture")).unwrap();
        let resolved = resolve_frontend(&registry, InvocationPolicy::PreferDirect);
        let workspace = temp.path().join("workspace");
        std::fs::create_dir(&workspace).unwrap();

        let error = invoke_frontend(
            &workspace,
            &resolved,
            compile_request(&temp.path().join("compile")),
        )
        .await
        .unwrap_err();

        match error {
            crate::error::CliError::Extension { message } => assert_eq!(
                message,
                "Provider 'fixture' rejected 'morphir.frontend.compile': Extension error: RPC error -32001: does not compile"
            ),
            other => panic!("expected an extension error, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn real_gleam_direct_and_native_mep_results_are_identical() {
        let temp = tempfile::tempdir().unwrap();
        let home =
            MorphirHome::resolve_from(Some(temp.path().join("home").as_os_str()), None).unwrap();
        let registry = extension_registry(&home, []).unwrap();
        let compile_request = compile_request(&temp.path().join("compile"));
        let direct_compile = invoke_frontend(
            temp.path(),
            &resolve_frontend(&registry, InvocationPolicy::PreferDirect),
            compile_request.clone(),
        )
        .await
        .unwrap();
        let protocol_compile = invoke_frontend(
            temp.path(),
            &resolve_frontend(&registry, InvocationPolicy::ProtocolOnly),
            compile_request,
        )
        .await
        .unwrap();
        assert_eq!(
            serde_json::to_value(&direct_compile).unwrap(),
            serde_json::to_value(&protocol_compile).unwrap()
        );

        let ir = direct_compile.ir.unwrap();
        let generate_request = GenerateRequest {
            ir,
            target: "gleam".into(),
            options: HashMap::new(),
        };
        let direct_generate = invoke_backend(
            temp.path(),
            &resolve_backend(&registry, InvocationPolicy::PreferDirect),
            generate_request.clone(),
        )
        .await
        .unwrap();
        let protocol_generate = invoke_backend(
            temp.path(),
            &resolve_backend(&registry, InvocationPolicy::ProtocolOnly),
            generate_request,
        )
        .await
        .unwrap();
        assert_eq!(
            serde_json::to_value(direct_generate).unwrap(),
            serde_json::to_value(protocol_generate).unwrap()
        );
    }
}

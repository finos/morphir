//! CLI-owned integration boundary for built-in and installed extension providers.

use crate::error::CliError;
use crate::home::MorphirHome;
use morphir_daemon::ExtensionRegistry;
use morphir_daemon::extensions::{
    FailedSession, InvocationMode, InvokeOutcome, Loaded, MepTransport, ResolvedBackend,
    ResolvedFrontend, Session, activate_transport, protocol::methods,
};
use morphir_distribution::{InstalledExtensionSnapshot, activate_installed_snapshot};
use morphir_extension_sdk::protocol::{InitializeParams, MEP_VERSION, PeerInfo};
use morphir_extension_sdk::{
    CompileRequest, CompileResult, GenerateRequest, GenerateResult, NativeExtension,
};
use morphir_gleam_binding::GleamExtension;
use serde::{Serialize, de::DeserializeOwned};
use std::path::Path;

/// Construct the complete provider registry used by one CLI command.
pub fn extension_registry(
    installed: impl IntoIterator<Item = InstalledExtensionSnapshot>,
) -> Result<ExtensionRegistry, CliError> {
    let gleam =
        NativeExtension::frontend_backend(GleamExtension).map_err(|error| CliError::Extension {
            message: format!("Failed to construct native Gleam provider: {error}"),
        })?;
    let mut registry = ExtensionRegistry::new();
    registry
        .register_builtin(gleam)
        .map_err(|error| CliError::Extension {
            message: format!("Failed to register native Gleam provider: {error}"),
        })?;
    for snapshot in installed {
        let id = snapshot.installed().extension_id().to_string();
        registry
            .register_installed(snapshot)
            .map_err(|error| CliError::Extension {
                message: format!("Failed to register installed provider '{id}': {error}"),
            })?;
    }
    Ok(registry)
}

/// Invoke a resolved frontend through only the mode selected by the registry.
pub async fn invoke_frontend(
    home: &MorphirHome,
    workspace: &Path,
    resolved: &ResolvedFrontend,
    request: CompileRequest,
) -> Result<CompileResult, CliError> {
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
                    .native_frontend()
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
        InvocationMode::NativeMep => {
            let loaded = resolved.native_mep_session().ok_or_else(|| {
                unavailable_mode(resolved.info().id.as_str(), "native MEP frontend")
            })?;
            invoke_loaded(
                loaded,
                resolved.info().id.as_str(),
                methods::COMPILE,
                request,
            )
            .await
        }
        InvocationMode::ProcessMep | InvocationMode::WasmMep => {
            let snapshot = resolved.installed_snapshot().ok_or_else(|| {
                unavailable_mode(resolved.info().id.as_str(), "installed MEP frontend")
            })?;
            invoke_installed(
                home,
                workspace,
                snapshot,
                resolved.info().id.as_str(),
                methods::COMPILE,
                request,
            )
            .await
        }
    }
}

/// Invoke a resolved backend through only the mode selected by the registry.
pub async fn invoke_backend(
    home: &MorphirHome,
    workspace: &Path,
    resolved: &ResolvedBackend,
    request: GenerateRequest,
) -> Result<GenerateResult, CliError> {
    match resolved.invocation_mode() {
        InvocationMode::NativeDirect => {
            // See `invoke_frontend`: a native provider generates
            // synchronously and must not hold the runtime while it does.
            let resolved = resolved.clone();
            blocking(resolved.info().id.clone(), move || {
                resolved
                    .native_backend()
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
        InvocationMode::NativeMep => {
            let loaded = resolved.native_mep_session().ok_or_else(|| {
                unavailable_mode(resolved.info().id.as_str(), "native MEP backend")
            })?;
            invoke_loaded(
                loaded,
                resolved.info().id.as_str(),
                methods::GENERATE,
                request,
            )
            .await
        }
        InvocationMode::ProcessMep | InvocationMode::WasmMep => {
            let snapshot = resolved.installed_snapshot().ok_or_else(|| {
                unavailable_mode(resolved.info().id.as_str(), "installed MEP backend")
            })?;
            invoke_installed(
                home,
                workspace,
                snapshot,
                resolved.info().id.as_str(),
                methods::GENERATE,
                request,
            )
            .await
        }
    }
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

async fn invoke_installed<P, R>(
    home: &MorphirHome,
    workspace: &Path,
    snapshot: &InstalledExtensionSnapshot,
    provider: &str,
    method: &str,
    request: P,
) -> Result<R, CliError>
where
    P: Serialize,
    R: DeserializeOwned,
{
    let artifact =
        activate_installed_snapshot(home, snapshot).map_err(|error| CliError::Extension {
            message: format!("Failed to verify installed provider '{provider}': {error}"),
        })?;
    let loaded = activate_transport(artifact, workspace)
        .await
        .map_err(|error| CliError::Extension {
            message: format!("Failed to activate installed provider '{provider}': {error}"),
        })?;
    invoke_loaded(loaded, provider, method, request).await
}

async fn invoke_loaded<T, P, R>(
    loaded: Session<T, Loaded>,
    provider: &str,
    method: &str,
    request: P,
) -> Result<R, CliError>
where
    T: MepTransport,
    P: Serialize,
    R: DeserializeOwned,
{
    let ready = loaded
        .initialize(host_initialize_params())
        .await
        .map_err(|failure| session_failure(provider, "initialize", failure))?;
    match ready.invoke::<R>(method, request).await {
        InvokeOutcome::Success(ready, result) => {
            ready
                .shutdown()
                .await
                .map_err(|failure| session_failure(provider, "shutdown", failure))?;
            Ok(result)
        }
        InvokeOutcome::Rejected(ready, error) => {
            let mut message = format!("Provider '{provider}' rejected '{method}': {error}");
            if let Err(failure) = ready.shutdown().await {
                message.push_str(&format!(
                    "; orderly shutdown also failed: {}",
                    failed_session_message(&failure)
                ));
            }
            Err(CliError::Extension { message })
        }
        InvokeOutcome::Failed(failure) => Err(session_failure(provider, method, failure)),
    }
}

fn host_initialize_params() -> InitializeParams {
    InitializeParams {
        protocol_versions: vec![MEP_VERSION.into()],
        host: PeerInfo {
            name: "morphir-cli".into(),
            version: env!("CARGO_PKG_VERSION").into(),
        },
    }
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
    use super::{extension_registry, invoke_backend, invoke_frontend};
    use crate::home::MorphirHome;
    use morphir_daemon::{InvocationPolicy, ResolvedBackend, ResolvedFrontend};
    use morphir_extension_sdk::{
        CompileOptions, CompilePackage, CompileRequest, GenerateRequest, SourceDocument,
    };
    use serde_json::json;
    use std::collections::HashMap;
    use std::path::Path;

    fn compile_request(output_dir: &Path) -> CompileRequest {
        CompileRequest {
            language_id: "gleam".into(),
            documents: vec![SourceDocument {
                uri: "file:///workspace/src/main.gleam".into(),
                language_id: "gleam".into(),
                version: 1,
                text: "pub fn hello() {\n  \"world\"\n}\n".into(),
            }],
            package: CompilePackage {
                name: "example/hello".into(),
                exposed_modules: vec![],
            },
            dependencies: vec![],
            options: CompileOptions {
                types_only: false,
                ir_version: "4.0.0".into(),
                extra: HashMap::from([
                    ("outputDir".into(), json!(output_dir)),
                    ("sourceRootUri".into(), json!("file:///workspace/src")),
                    ("emitParseStage".into(), json!(false)),
                    ("emitParseStageFatal".into(), json!(false)),
                ]),
            },
        }
    }

    fn resolve_frontend(
        registry: &morphir_daemon::ExtensionRegistry,
        policy: InvocationPolicy,
    ) -> ResolvedFrontend {
        registry.resolve_frontend("gleam", "4.0.0", policy).unwrap()
    }

    fn resolve_backend(
        registry: &morphir_daemon::ExtensionRegistry,
        policy: InvocationPolicy,
    ) -> ResolvedBackend {
        registry.resolve_backend("gleam", "4.0.0", policy).unwrap()
    }

    #[tokio::test]
    async fn real_gleam_direct_and_native_mep_results_are_identical() {
        let temp = tempfile::tempdir().unwrap();
        let home =
            MorphirHome::resolve_from(Some(temp.path().join("home").as_os_str()), None).unwrap();
        let registry = extension_registry([]).unwrap();
        let compile_request = compile_request(&temp.path().join("compile"));
        let direct_compile = invoke_frontend(
            &home,
            temp.path(),
            &resolve_frontend(&registry, InvocationPolicy::PreferDirect),
            compile_request.clone(),
        )
        .await
        .unwrap();
        let protocol_compile = invoke_frontend(
            &home,
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
            &home,
            temp.path(),
            &resolve_backend(&registry, InvocationPolicy::PreferDirect),
            generate_request.clone(),
        )
        .await
        .unwrap();
        let protocol_generate = invoke_backend(
            &home,
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

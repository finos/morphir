//! CLI-owned integration boundary for built-in and installed extension providers.

use crate::error::CliError;
use crate::home::MorphirHome;
use morphir_daemon::DaemonError;
use morphir_distribution::InstalledExtensionSnapshot;
use morphir_elm_binding::ElmExtension;
use morphir_extension_sdk::protocol::methods;
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
#[cfg(test)]
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

#[cfg(test)]
mod tests {
    use super::{extension_registry, invoke_backend, invoke_frontend};
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

    /// A configured process provider that speaks MEP over stdio and refuses
    /// every compile with an RPC error.
    #[cfg(unix)]
    fn rejecting_provider(directory: &Path) -> std::path::PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let (guest, _record) = super::installed_fixture::rejecting_frontend();
        let path = directory.join("rejecting-provider");
        std::fs::write(&path, guest).unwrap();
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
        let (guest, record) = super::installed_fixture::rejecting_frontend();
        let (home, snapshot) =
            super::installed_fixture::install_process(temp.path(), record, &guest);
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

    // An installed artifact that changed after installation is refused before
    // it runs, in the text the CLI has always used for it.
    #[cfg(unix)]
    #[tokio::test]
    async fn an_installed_provider_whose_artifact_changed_fails_verification() {
        let temp = tempfile::tempdir().unwrap();
        let (guest, record) = super::installed_fixture::rejecting_frontend();
        let (home, snapshot) =
            super::installed_fixture::install_process(temp.path(), record, &guest);
        super::installed_fixture::tamper(&home, &snapshot);
        let registry = super::extension_registry_for(&home, [snapshot], Some("fixture")).unwrap();
        let resolved = resolve_frontend(&registry, InvocationPolicy::PreferDirect);

        let error = invoke_frontend(
            temp.path(),
            &resolved,
            compile_request(&temp.path().join("compile")),
        )
        .await
        .unwrap_err();

        match error {
            crate::error::CliError::Extension { message } => {
                assert!(
                    message.starts_with("Failed to verify installed provider 'fixture': "),
                    "{message}"
                );
                assert!(message.contains("digest mismatch"), "{message}");
            }
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

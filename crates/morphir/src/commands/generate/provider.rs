use crate::error::CliError;
use morphir_common::home::MorphirHome;
use morphir_daemon::extensions::{
    InvokeOutcome, Loaded, MepTransport, Ready, Session, activate_transport,
    protocol::{InitializeParams, MEP_VERSION, PeerInfo, methods},
};
use morphir_distribution::{
    InstalledExtension, InstalledExtensionSnapshot, activate_installed_snapshot,
};
use morphir_extension_sdk::{GenerateRequest, GenerateResult};
use serde_json::Value;
use std::collections::{BTreeSet, HashSet};
use std::path::Path;

fn host_initialize_params() -> InitializeParams {
    InitializeParams {
        protocol_versions: vec![MEP_VERSION.into()],
        host: PeerInfo {
            name: "morphir-cli".into(),
            version: env!("CARGO_PKG_VERSION").into(),
        },
    }
}

async fn invoke_loaded<T: MepTransport>(
    loaded: Session<T, Loaded>,
    installed: &InstalledExtension,
    target: &str,
    ir_version: &str,
    request: GenerateRequest,
) -> Result<GenerateResult, CliError> {
    let ready = loaded
        .initialize(host_initialize_params())
        .await
        .map_err(|failure| CliError::Extension {
            message: failure.error().to_string(),
        })?;
    let ready = validate_backend_session(ready, installed, target, ir_version).await?;
    let (ready, result) = match ready
        .invoke::<GenerateResult>(methods::GENERATE, request)
        .await
    {
        InvokeOutcome::Success(ready, result) => (ready, result),
        InvokeOutcome::Rejected(ready, error) => {
            let mut message = error.to_string();
            if let Err(failure) = ready.shutdown().await {
                message.push_str(&format!(
                    "; extension shutdown also failed: {}",
                    failure.error()
                ));
            }
            return Err(CliError::Extension { message });
        }
        InvokeOutcome::Failed(failure) => {
            return Err(CliError::Extension {
                message: failure.error().to_string(),
            });
        }
    };
    ready
        .shutdown()
        .await
        .map_err(|failure| CliError::Extension {
            message: failure.error().to_string(),
        })?;
    Ok(result)
}

async fn validate_backend_session<T: MepTransport>(
    session: Session<T, Ready>,
    installed: &InstalledExtension,
    target: &str,
    ir_version: &str,
) -> Result<Session<T, Ready>, CliError> {
    let validation = validate_backend_capabilities(&session, installed, target, ir_version);
    match validation {
        Ok(()) => Ok(session),
        Err(error) => match session.shutdown().await {
            Ok(_) => Err(error),
            Err(cleanup) => Err(CliError::Extension {
                message: format!(
                    "{}; extension shutdown also failed: {}",
                    error,
                    cleanup.error()
                ),
            }),
        },
    }
}

fn validate_backend_capabilities<T: MepTransport>(
    session: &Session<T, Ready>,
    installed: &InstalledExtension,
    target: &str,
    ir_version: &str,
) -> Result<(), CliError> {
    let negotiated = session.negotiated();
    let extension = negotiated.extension();
    let expected = installed.extension_info();
    let same_types = extension.types.iter().copied().collect::<HashSet<_>>()
        == expected.types.iter().copied().collect::<HashSet<_>>();
    let expected_backend = installed.backend().ok_or_else(|| CliError::Extension {
        message: format!(
            "Installed provider '{}' has no backend capability metadata",
            installed.extension_id()
        ),
    })?;
    let backend =
        negotiated
            .capabilities()
            .backend
            .as_ref()
            .ok_or_else(|| CliError::Extension {
                message: format!(
                    "Installed provider '{}' did not negotiate backend capability metadata",
                    installed.extension_id()
                ),
            })?;
    let same_targets = backend.targets.iter().collect::<BTreeSet<_>>()
        == expected_backend.targets().iter().collect::<BTreeSet<_>>();
    let same_ir_versions = backend.ir_versions.iter().collect::<BTreeSet<_>>()
        == expected_backend
            .ir_versions()
            .iter()
            .collect::<BTreeSet<_>>();
    if extension.id != expected.id
        || extension.name != expected.name
        || extension.version != expected.version
        || !same_types
        || !same_targets
        || !same_ir_versions
        || backend.generate != expected_backend.generate()
    {
        return Err(CliError::Extension {
            message: format!(
                "Backend provider '{}' initialized with capabilities that differ from its installed record",
                installed.extension_id()
            ),
        });
    }
    if !backend.generate
        || !backend.targets.iter().any(|candidate| candidate == target)
        || !backend
            .ir_versions
            .iter()
            .any(|candidate| candidate == ir_version)
    {
        return Err(CliError::Extension {
            message: format!(
                "Backend provider '{}' did not negotiate generation for target '{target}' with Morphir IR {ir_version}",
                installed.extension_id()
            ),
        });
    }
    Ok(())
}

pub async fn invoke_generate(
    home: &MorphirHome,
    provider: &InstalledExtensionSnapshot,
    workspace: &Path,
    target: &str,
    ir_version: &str,
    request: GenerateRequest,
) -> Result<GenerateResult, CliError> {
    let installed = provider.installed();
    let artifact =
        activate_installed_snapshot(home, provider).map_err(|error| CliError::Extension {
            message: format!(
                "Failed to activate installed backend provider '{}': {error}",
                installed.extension_id()
            ),
        })?;
    let loaded = activate_transport(artifact, workspace)
        .await
        .map_err(|error| CliError::Extension {
            message: format!(
                "Failed to load installed backend provider '{}': {error}",
                installed.extension_id()
            ),
        })?;
    invoke_loaded(loaded, installed, target, ir_version, request).await
}

pub(super) trait ProviderMetadata {
    fn installed(&self) -> &InstalledExtension;
}

impl ProviderMetadata for InstalledExtension {
    fn installed(&self) -> &InstalledExtension {
        self
    }
}

impl ProviderMetadata for InstalledExtensionSnapshot {
    fn installed(&self) -> &InstalledExtension {
        self.installed()
    }
}

pub(super) fn detect_ir_major(ir: &Value) -> Result<String, CliError> {
    let format_version = ir.get("formatVersion");
    if format_version == Some(&Value::from(4)) || format_version == Some(&Value::from("4.0.0")) {
        return Ok("4".into());
    }
    let classic_ir = match format_version.and_then(Value::as_str) {
        Some("3.0.0") => {
            let mut normalized = ir.clone();
            normalized["formatVersion"] = Value::from(3);
            normalized
        }
        Some(version) => {
            return Err(CliError::Extension {
                message: format!(
                    "Cannot detect a supported Morphir IR version: unsupported formatVersion {version}"
                ),
            });
        }
        None => ir.clone(),
    };
    let classic = serde_json::from_value::<morphir_core::ir::classic::Distribution>(classic_ir)
        .map_err(|error| CliError::Extension {
            message: format!("Cannot detect a supported Morphir IR version: {error}"),
        })?;
    if classic.format_version != 3 {
        return Err(CliError::Extension {
            message: format!(
                "Cannot detect a supported Morphir IR version: unsupported formatVersion {}",
                classic.format_version
            ),
        });
    }
    Ok("3".into())
}

pub(super) fn select_provider<'a, T: ProviderMetadata>(
    installed: &'a [T],
    target: &str,
    ir_version: &str,
) -> Result<&'a T, CliError> {
    let target_matches = installed
        .iter()
        .filter(|provider| {
            provider
                .installed()
                .backend()
                .is_some_and(|backend| backend.targets().iter().any(|value| value == target))
        })
        .collect::<Vec<_>>();
    if target_matches.is_empty() {
        return Err(CliError::Extension {
            message: format!("No installed backend provider advertises target '{target}'"),
        });
    }
    let matches = target_matches
        .into_iter()
        .filter(|provider| {
            provider.installed().backend().is_some_and(|backend| {
                backend
                    .ir_versions()
                    .iter()
                    .any(|value| value == ir_version)
            })
        })
        .collect::<Vec<_>>();
    match matches.as_slice() {
        [provider] => Ok(*provider),
        [] => Err(CliError::Extension {
            message: format!(
                "Installed backend providers advertise target '{target}' but none support Morphir IR {ir_version}"
            ),
        }),
        _ => Err(CliError::Extension {
            message: format!(
                "Target '{target}' with Morphir IR {ir_version} has more than one installed backend provider"
            ),
        }),
    }
}

pub(super) enum ProviderRoute<'a, T> {
    Installed(&'a T),
    LegacyBuiltin,
}

pub(super) fn resolve_provider<'a, T: ProviderMetadata>(
    installed: &'a [T],
    target: &str,
    ir_version: &str,
) -> Result<ProviderRoute<'a, T>, CliError> {
    let target_is_advertised = installed.iter().any(|provider| {
        provider
            .installed()
            .backend()
            .is_some_and(|backend| backend.targets().iter().any(|value| value == target))
    });
    if !target_is_advertised {
        return Ok(ProviderRoute::LegacyBuiltin);
    }
    select_provider(installed, target, ir_version).map(ProviderRoute::Installed)
}

#[cfg(test)]
mod tests {
    use async_trait::async_trait;
    #[cfg(unix)]
    use morphir_common::home::MorphirHome;
    use morphir_daemon::DaemonError;
    use morphir_daemon::extensions::{
        ExpectedExtension, MepTransport, Session, TransportError, TransportState,
        protocol::{
            ExtensionRequest, ExtensionResponse, InitializeResult, MEP_VERSION, RpcError, methods,
        },
    };
    use morphir_distribution::InstalledExtension;
    #[cfg(unix)]
    use morphir_distribution::{
        Channel, ExtensionId, ExtensionInstaller, LocalIndex, Platform, Selection, Sha256Digest,
        list_installed,
    };
    use morphir_extension_sdk::{
        Artifact, BackendCapability, ExtensionCapabilities, ExtensionInfo, ExtensionType,
        GenerateRequest, GenerateResult,
    };
    use serde_json::json;
    #[cfg(unix)]
    use std::fs;
    #[cfg(unix)]
    use std::os::unix::fs::PermissionsExt;
    #[cfg(unix)]
    use std::process::Command;
    use std::sync::{Arc, Mutex};

    use super::{
        ProviderRoute, detect_ir_major, invoke_generate, invoke_loaded, resolve_provider,
        select_provider,
    };

    #[derive(Default)]
    struct TransportStateMother {
        requests: Vec<ExtensionRequest>,
        terminated: bool,
    }

    struct GenerateTransport {
        state: Arc<Mutex<TransportStateMother>>,
        rejection: Option<RpcError>,
        generation_failure: bool,
        termination_failure: bool,
    }

    #[async_trait]
    impl MepTransport for GenerateTransport {
        fn expected_extension(&self) -> ExpectedExtension {
            ExpectedExtension::identified("test-backend")
        }

        async fn exchange(
            &mut self,
            request: ExtensionRequest,
        ) -> Result<ExtensionResponse, TransportError> {
            self.state.lock().unwrap().requests.push(request.clone());
            if request.method == methods::GENERATE && self.generation_failure {
                return Err(TransportError::new(
                    DaemonError::Extension("provider transport failed".into()),
                    TransportState::Indeterminate,
                ));
            }
            if request.method == methods::GENERATE
                && let Some(error) = self.rejection.clone()
            {
                return Ok(ExtensionResponse::error(request.id, error));
            }
            let result = match request.method.as_str() {
                methods::INITIALIZE => serde_json::to_value(InitializeResult {
                    protocol_version: MEP_VERSION.into(),
                    extension: ExtensionInfo {
                        id: "test-backend".into(),
                        name: "Test backend".into(),
                        version: "1.0.0".into(),
                        types: vec![ExtensionType::Backend],
                        ..ExtensionInfo::default()
                    },
                    capabilities: ExtensionCapabilities {
                        backend: Some(BackendCapability {
                            targets: vec!["avro".into()],
                            ir_versions: vec!["3".into(), "4".into()],
                            generate: true,
                        }),
                        ..ExtensionCapabilities::default()
                    },
                })
                .unwrap(),
                methods::GENERATE => serde_json::to_value(GenerateResult {
                    success: true,
                    artifacts: vec![Artifact {
                        path: "schema.avsc".into(),
                        content: "{}".into(),
                        binary: false,
                    }],
                    diagnostics: Vec::new(),
                })
                .unwrap(),
                methods::SHUTDOWN => serde_json::Value::Null,
                method => panic!("unexpected MEP method {method}"),
            };
            Ok(ExtensionResponse::success(request.id, result).unwrap())
        }

        async fn terminate(&mut self) -> Result<TransportState, TransportError> {
            self.state.lock().unwrap().terminated = true;
            if self.termination_failure {
                return Err(TransportError::new(
                    DaemonError::Extension("mock shutdown failed".into()),
                    TransportState::Stopped,
                ));
            }
            Ok(TransportState::Stopped)
        }
    }

    fn backend(id: &str, targets: &[&str], ir_versions: &[&str]) -> InstalledExtension {
        serde_json::from_value(json!({
            "extensionId": id,
            "name": "Test backend",
            "version": "1.0.0",
            "runtime": "wasm",
            "platform": null,
            "args": [],
            "digest": "0000000000000000000000000000000000000000000000000000000000000000",
            "storePath": format!("{id}.wasm"),
            "capabilities": ["backend"],
            "mepVersions": ["0.1"],
            "index": {
                "kind": "local-directory",
                "identity": "/test/index",
                "revision": "1111111111111111111111111111111111111111111111111111111111111111"
            },
            "backend": {
                "targets": targets,
                "irVersions": ir_versions
            },
            "executable": false
        }))
        .unwrap()
    }

    fn selected_backend() -> InstalledExtension {
        backend("test-backend", &["avro"], &["3", "4"])
    }

    #[test]
    fn selects_the_only_installed_provider_for_target_and_ir_version() {
        let installed = vec![
            backend("schema-provider", &["avro"], &["3", "4"]),
            backend("morphir-scala", &["scala"], &["3"]),
        ];

        let selected = select_provider(&installed, "avro", "4").unwrap();

        assert_eq!(selected.extension_id().as_str(), "schema-provider");
    }

    #[test]
    fn rejects_ambiguous_backend_providers() {
        let installed = vec![
            backend("avro-one", &["avro"], &["4"]),
            backend("avro-two", &["avro"], &["4"]),
        ];

        let error = select_provider(&installed, "avro", "4").unwrap_err();

        assert!(error.to_string().contains("more than one"), "{error}");
    }

    #[test]
    fn reports_when_no_installed_provider_advertises_the_target() {
        let installed = vec![backend("morphir-scala", &["scala"], &["3", "4"])];

        let error = select_provider(&installed, "avro", "4").unwrap_err();

        assert!(
            error
                .to_string()
                .contains("No installed backend provider advertises target 'avro'"),
            "{error}"
        );
    }

    #[test]
    fn rejects_an_ir_version_unsupported_by_the_target_providers() {
        let installed = vec![backend("morphir-avro", &["avro"], &["3", "4"])];

        let error = select_provider(&installed, "avro", "5").unwrap_err();

        assert!(
            error.to_string().contains(
                "Installed backend providers advertise target 'avro' but none support Morphir IR 5"
            ),
            "{error}"
        );
    }

    #[test]
    fn detects_integer_v4_format_versions() {
        let ir = json!({"formatVersion": 4, "distribution": {"Library": {}}});

        assert_eq!(detect_ir_major(&ir).unwrap(), "4");
    }

    #[test]
    fn detects_dotted_string_v4_format_versions() {
        let ir = json!({"formatVersion": "4.0.0", "distribution": {"Library": {}}});

        assert_eq!(detect_ir_major(&ir).unwrap(), "4");
    }

    #[test]
    fn rejects_unsupported_or_malformed_dotted_v4_versions() {
        for version in ["4.2.1", "4."] {
            let ir = json!({"formatVersion": version, "distribution": {"Library": {}}});

            let error = detect_ir_major(&ir).unwrap_err();

            assert!(
                error
                    .to_string()
                    .contains(&format!("unsupported formatVersion {version}")),
                "{error}"
            );
        }
    }

    #[test]
    fn rejects_classic_distributions_that_do_not_declare_v3() {
        let ir = json!({
            "formatVersion": 2,
            "distribution": ["Library", [["local"]], [], {"modules": []}]
        });

        let error = detect_ir_major(&ir).unwrap_err();

        assert!(
            error.to_string().contains("unsupported formatVersion 2"),
            "{error}"
        );
    }

    #[test]
    fn detects_typed_classic_v3_distributions() {
        let ir = json!({
            "formatVersion": 3,
            "distribution": ["Library", [["local"]], [], {"modules": []}]
        });

        assert_eq!(detect_ir_major(&ir).unwrap(), "3");
    }

    #[test]
    fn detects_exact_dotted_string_v3_after_typed_validation() {
        let ir = json!({
            "formatVersion": "3.0.0",
            "distribution": ["Library", [["local"]], [], {"modules": []}]
        });

        assert_eq!(detect_ir_major(&ir).unwrap(), "3");
    }

    #[test]
    fn uses_the_legacy_fallback_when_no_verified_provider_advertises_the_target() {
        let installed = vec![backend("morphir-scala", &["scala"], &["3", "4"])];

        let route = resolve_provider(&installed, "avro", "4").unwrap();

        assert!(matches!(route, ProviderRoute::LegacyBuiltin));
    }

    #[test]
    fn does_not_fall_back_when_an_advertised_target_lacks_ir_support() {
        let installed = vec![backend("morphir-avro", &["avro"], &["3"])];

        let error = match resolve_provider(&installed, "avro", "4") {
            Err(error) => error,
            Ok(_) => panic!("an advertised but incompatible provider must block fallback"),
        };

        assert!(
            error.to_string().contains("none support Morphir IR 4"),
            "{error}"
        );
    }

    #[tokio::test]
    async fn invokes_generate_with_only_typed_ir_and_options_then_shuts_down() {
        let state = Arc::new(Mutex::new(TransportStateMother::default()));
        let loaded = Session::loaded(GenerateTransport {
            state: Arc::clone(&state),
            rejection: None,
            generation_failure: false,
            termination_failure: false,
        });
        let request = GenerateRequest {
            ir: json!({"formatVersion": 4}),
            options: [("representation".into(), json!("idl"))]
                .into_iter()
                .collect(),
        };
        let installed = selected_backend();

        let result = invoke_loaded(loaded, &installed, "avro", "4", request)
            .await
            .unwrap();

        assert!(result.success);
        assert_eq!(result.artifacts[0].path, "schema.avsc");
        let state = state.lock().unwrap();
        assert_eq!(
            state
                .requests
                .iter()
                .map(|request| request.method.as_str())
                .collect::<Vec<_>>(),
            [methods::INITIALIZE, methods::GENERATE, methods::SHUTDOWN]
        );
        assert_eq!(
            state.requests[1].params,
            json!({
                "ir": {"formatVersion": 4},
                "options": {"representation": "idl"}
            })
        );
        assert!(state.terminated);
    }

    #[tokio::test]
    async fn rejects_runtime_backend_metadata_that_differs_from_the_installed_record() {
        let state = Arc::new(Mutex::new(TransportStateMother::default()));
        let loaded = Session::loaded(GenerateTransport {
            state: Arc::clone(&state),
            rejection: None,
            generation_failure: false,
            termination_failure: false,
        });
        let installed = backend("test-backend", &["json-schema"], &["4"]);

        let error = invoke_loaded(
            loaded,
            &installed,
            "json-schema",
            "4",
            GenerateRequest::default(),
        )
        .await
        .unwrap_err();

        assert!(error.to_string().contains("installed record"), "{error}");
        let state = state.lock().unwrap();
        assert_eq!(
            state
                .requests
                .iter()
                .map(|request| request.method.as_str())
                .collect::<Vec<_>>(),
            [methods::INITIALIZE, methods::SHUTDOWN]
        );
        assert!(state.terminated);
    }

    #[tokio::test]
    async fn rejected_generation_still_shuts_down_the_ready_session() {
        let state = Arc::new(Mutex::new(TransportStateMother::default()));
        let loaded = Session::loaded(GenerateTransport {
            state: Arc::clone(&state),
            rejection: Some(RpcError::invalid_params("bad generation request")),
            generation_failure: false,
            termination_failure: false,
        });
        let installed = selected_backend();

        let error = invoke_loaded(loaded, &installed, "avro", "4", GenerateRequest::default())
            .await
            .unwrap_err();

        assert!(
            error.to_string().contains("bad generation request"),
            "{error}"
        );
        let state = state.lock().unwrap();
        assert_eq!(
            state
                .requests
                .iter()
                .map(|request| request.method.as_str())
                .collect::<Vec<_>>(),
            [methods::INITIALIZE, methods::GENERATE, methods::SHUTDOWN]
        );
        assert!(state.terminated);
    }

    #[tokio::test]
    async fn rejected_generation_preserves_rejection_and_shutdown_failure() {
        let state = Arc::new(Mutex::new(TransportStateMother::default()));
        let loaded = Session::loaded(GenerateTransport {
            state,
            rejection: Some(RpcError::invalid_params("bad generation request")),
            generation_failure: false,
            termination_failure: true,
        });
        let installed = selected_backend();

        let error = invoke_loaded(loaded, &installed, "avro", "4", GenerateRequest::default())
            .await
            .unwrap_err();
        let message = error.to_string();

        assert!(message.contains("bad generation request"), "{message}");
        assert!(message.contains("mock shutdown failed"), "{message}");
    }

    #[tokio::test]
    async fn transport_failure_preserves_the_provider_error() {
        let state = Arc::new(Mutex::new(TransportStateMother::default()));
        let loaded = Session::loaded(GenerateTransport {
            state,
            rejection: None,
            generation_failure: true,
            termination_failure: false,
        });
        let installed = selected_backend();

        let error = invoke_loaded(loaded, &installed, "avro", "4", GenerateRequest::default())
            .await
            .unwrap_err();

        assert!(
            error.to_string().contains("provider transport failed"),
            "{error}"
        );
    }

    #[tokio::test]
    #[cfg(unix)]
    async fn installed_process_invocation_uses_the_exact_selected_snapshot() {
        let root = tempfile::tempdir().unwrap();
        let home =
            MorphirHome::resolve_from(Some(root.path().join("home").as_os_str()), None).unwrap();
        let workspace = root.path().join("workspace");
        fs::create_dir(&workspace).unwrap();
        install_process_provider(root.path(), &home, "1.0.0", "selected.avsc");
        let selected = list_installed(&home).unwrap().remove(0);
        install_process_provider(root.path(), &home, "2.0.0", "replacement.avsc");

        let result = invoke_generate(
            &home,
            &selected,
            &workspace,
            "avro",
            "4",
            GenerateRequest {
                ir: json!({"formatVersion": 4}),
                options: [("representation".into(), json!("idl"))]
                    .into_iter()
                    .collect(),
            },
        )
        .await
        .unwrap();

        assert!(result.success);
        assert_eq!(result.artifacts[0].path, "selected.avsc");
        assert_eq!(selected.installed().version().to_string(), "1.0.0");
        assert_eq!(
            list_installed(&home).unwrap()[0]
                .installed()
                .version()
                .to_string(),
            "2.0.0"
        );
    }

    #[cfg(unix)]
    fn install_process_provider(
        root: &std::path::Path,
        home: &MorphirHome,
        version: &str,
        generated_path: &str,
    ) {
        let index = root.join("index");
        let artifact_path = index.join("artifacts/morphir-avro");
        fs::create_dir_all(artifact_path.parent().unwrap()).unwrap();
        fs::create_dir_all(index.join("extensions")).unwrap();
        let script = process_provider_script(version, generated_path);
        fs::write(&artifact_path, script.as_bytes()).unwrap();
        fs::set_permissions(&artifact_path, fs::Permissions::from_mode(0o700)).unwrap();
        let digest = Sha256Digest::of_bytes(script.as_bytes());
        let platform = Platform::current();
        let record = json!({
            "schemaVersion": 2,
            "id": "morphir-avro",
            "name": "Morphir Avro",
            "version": version,
            "channels": ["stable"],
            "mepVersions": ["0.1"],
            "capabilities": ["backend"],
            "backend": {
                "targets": ["avro"],
                "irVersions": ["3", "4"]
            },
            "artifacts": [{
                "runtime": "process",
                "platform": { "os": platform.os(), "arch": platform.arch() },
                "source": { "kind": "local-file", "path": "artifacts/morphir-avro" },
                "sha256": digest,
                "filename": "morphir-avro",
                "args": [],
                "executable": true
            }]
        });
        fs::write(
            index.join("extensions/morphir-avro.jsonl"),
            format!("{record}\n"),
        )
        .unwrap();
        let id = ExtensionId::parse("morphir-avro").unwrap();
        let selected = LocalIndex::open(&index)
            .unwrap()
            .resolve(&id, Selection::Channel(Channel::Stable), &platform)
            .unwrap();
        ExtensionInstaller::new(home).install(selected).unwrap();
    }

    #[cfg(unix)]
    fn process_provider_script(version: &str, generated_path: &str) -> String {
        let python = Command::new("sh")
            .args(["-c", "command -v python3"])
            .output()
            .unwrap();
        assert!(python.status.success(), "python3 is required for this test");
        let python = String::from_utf8(python.stdout).unwrap();
        let template = r#"#!__PYTHON__
import json
import sys

def receive():
    length = None
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            raise SystemExit(0)
        if line in (b"\n", b"\r\n"):
            break
        name, value = line.decode("ascii").split(":", 1)
        if name.lower() == "content-length":
            length = int(value.strip())
    return json.loads(sys.stdin.buffer.read(length))

def send(identifier, result):
    message = json.dumps(
        {"jsonrpc": "2.0", "id": identifier, "result": result},
        separators=(",", ":"),
    ).encode()
    sys.stdout.buffer.write(
        b"Content-Length: " + str(len(message)).encode() + b"\r\n\r\n" + message
    )
    sys.stdout.buffer.flush()

while True:
    request = receive()
    method = request["method"]
    if method == "__INITIALIZE__":
        result = {
            "protocolVersion": "0.1",
            "extension": {
                "id": "morphir-avro",
                "name": "Morphir Avro",
                "version": "__VERSION__",
                "types": ["backend"],
            },
            "capabilities": {
                "backend": {
                    "targets": ["avro"],
                    "irVersions": ["3", "4"],
                    "generate": True,
                }
            },
        }
    elif method == "__GENERATE__":
        result = {
            "success": True,
            "artifacts": [
                {"path": "__GENERATED_PATH__", "content": "{}", "binary": False}
            ],
            "diagnostics": [],
        }
    elif method == "__SHUTDOWN__":
        result = {}
    elif method == "__EXIT__":
        break
    else:
        raise RuntimeError("unexpected method " + method)
    if "id" in request:
        send(request["id"], result)
"#;
        template
            .replace("__PYTHON__", python.trim())
            .replace("__VERSION__", version)
            .replace("__GENERATED_PATH__", generated_path)
            .replace("__INITIALIZE__", methods::INITIALIZE)
            .replace("__GENERATE__", methods::GENERATE)
            .replace("__SHUTDOWN__", methods::SHUTDOWN)
            .replace("__EXIT__", methods::EXIT)
    }
}

//! Session-reusing invocation for the playground provider.
//!
//! The one-shot extension boundary pays activation and the MEP handshake on
//! every call; for an installed extension that is a process spawn per click.
//! This module holds one [`SessionHandle`] per provider and answers every
//! playground compile and generate over it, falling back to the one-shot path
//! only for native-direct providers, which have no session at all.

use std::collections::HashMap;
use std::path::Path;

use async_trait::async_trait;
use morphir_daemon::DaemonError;
use morphir_daemon::extensions::protocol::methods;
use morphir_daemon::extensions::{ResolvedBackend, ResolvedFrontend, SessionHandle};
use morphir_extension_sdk::{CompileRequest, CompileResult, GenerateRequest, GenerateResult};
use serde::{Serialize, de::DeserializeOwned};
use tokio::sync::Mutex;

use super::playground::ExtensionInvoker;
use crate::error::CliError;
use crate::home::MorphirHome;

/// How the invoker opens sessions and reaches providers that have none.
///
/// Production is [`RegistryOpener`], which delegates to the CLI's own
/// extension boundary — the same functions `morphir compile` and `morphir
/// generate` call — so session reuse cannot acquire a private invocation
/// path. Injectable so a test can count opens and script session failures
/// without an extension process.
#[async_trait]
pub(super) trait SessionOpener: Send + Sync {
    async fn open_frontend(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: &ResolvedFrontend,
    ) -> Result<Option<SessionHandle>, CliError>;

    async fn open_backend(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: &ResolvedBackend,
    ) -> Result<Option<SessionHandle>, CliError>;

    async fn compile_without_session(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: &ResolvedFrontend,
        request: CompileRequest,
    ) -> Result<CompileResult, CliError>;

    async fn generate_without_session(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: &ResolvedBackend,
        request: GenerateRequest,
    ) -> Result<GenerateResult, CliError>;
}

/// The production opener: the CLI's extension boundary, nothing else.
pub(super) struct RegistryOpener;

#[async_trait]
impl SessionOpener for RegistryOpener {
    async fn open_frontend(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: &ResolvedFrontend,
    ) -> Result<Option<SessionHandle>, CliError> {
        crate::extensions::open_frontend_session(home, workspace, resolved).await
    }

    async fn open_backend(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: &ResolvedBackend,
    ) -> Result<Option<SessionHandle>, CliError> {
        crate::extensions::open_backend_session(home, workspace, resolved).await
    }

    async fn compile_without_session(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: &ResolvedFrontend,
        request: CompileRequest,
    ) -> Result<CompileResult, CliError> {
        crate::extensions::invoke_frontend(home, workspace, resolved, request).await
    }

    async fn generate_without_session(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: &ResolvedBackend,
        request: GenerateRequest,
    ) -> Result<GenerateResult, CliError> {
        crate::extensions::invoke_backend(home, workspace, resolved, request).await
    }
}

/// A frontend or backend resolution, so one code path serves both.
///
/// Holds references, so it is `Copy`: the retry path needs the resolution a
/// second time after the first open consumed it.
#[derive(Clone, Copy)]
enum Resolved<'a> {
    Frontend(&'a ResolvedFrontend),
    Backend(&'a ResolvedBackend),
}

/// An [`ExtensionInvoker`] that keeps one session per provider across calls.
///
/// Sessions are keyed by provider id alone, not per language or per
/// operation: a session belongs to one running extension, and an extension
/// serving two languages — or both compile and generate — serves all of them
/// over the same negotiated session.
pub(super) struct SessionReuseInvoker<O> {
    opener: O,
    sessions: Mutex<HashMap<String, SessionHandle>>,
}

impl<O> SessionReuseInvoker<O> {
    pub(super) fn new(opener: O) -> Self {
        Self {
            opener,
            sessions: Mutex::new(HashMap::new()),
        }
    }
}

impl<O: SessionOpener> SessionReuseInvoker<O> {
    async fn open(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        resolved: Resolved<'_>,
    ) -> Result<Option<SessionHandle>, CliError> {
        match resolved {
            Resolved::Frontend(frontend) => {
                self.opener.open_frontend(home, workspace, frontend).await
            }
            Resolved::Backend(backend) => self.opener.open_backend(home, workspace, backend).await,
        }
    }

    /// Answer one invocation over the provider's session, or `None` when the
    /// provider has no session mode and the caller must go one-shot.
    ///
    /// The map lock is held across the open on purpose: the playground serves
    /// one user, and two racing requests for the same provider each opening a
    /// session would leak one of them.
    async fn via_session<P, R>(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        provider: &str,
        resolved: Resolved<'_>,
        method: &str,
        request: &P,
    ) -> Result<Option<R>, CliError>
    where
        P: Serialize + Sync,
        R: DeserializeOwned,
    {
        let handle = {
            let mut sessions = self.sessions.lock().await;
            match sessions.get(provider) {
                Some(handle) => Some(handle.clone()),
                None => match self.open(home, workspace, resolved).await? {
                    Some(handle) => {
                        sessions.insert(provider.to_owned(), handle.clone());
                        Some(handle)
                    }
                    None => None,
                },
            }
        };
        let Some(handle) = handle else {
            return Ok(None);
        };
        match handle.invoke::<R>(method, request).await {
            Ok(result) => Ok(Some(result)),
            // The session ended — idle-stopped, crashed, or died under this
            // very request. That is a fact about the cached session, not about
            // the request, so the request gets a second chance on a fresh one.
            // Exactly one: a session that dies twice in a row is a provider
            // problem the user should see, not something to retry into.
            Err(DaemonError::SessionLost(_)) => {
                let fresh = {
                    let mut sessions = self.sessions.lock().await;
                    sessions.remove(provider);
                    let fresh = self.open(home, workspace, resolved).await?.ok_or_else(|| {
                        CliError::Extension {
                            message: format!(
                                "Provider '{provider}' lost its session and no longer offers one"
                            ),
                        }
                    })?;
                    sessions.insert(provider.to_owned(), fresh.clone());
                    fresh
                };
                match fresh.invoke::<R>(method, request).await {
                    Ok(result) => Ok(Some(result)),
                    Err(error) => {
                        // A dead handle left cached would burn the single
                        // retry of every request after this one.
                        if matches!(error, DaemonError::SessionLost(_)) {
                            self.sessions.lock().await.remove(provider);
                        }
                        Err(session_error(provider, method, error))
                    }
                }
            }
            Err(error) => Err(session_error(provider, method, error)),
        }
    }
}

fn session_error(provider: &str, method: &str, error: DaemonError) -> CliError {
    CliError::Extension {
        message: format!("Provider '{provider}' failed during '{method}': {error}"),
    }
}

#[async_trait]
impl<O: SessionOpener> ExtensionInvoker for SessionReuseInvoker<O> {
    async fn compile(
        &self,
        home: &MorphirHome,
        working_directory: &Path,
        resolved: &ResolvedFrontend,
        request: CompileRequest,
    ) -> Result<CompileResult, CliError> {
        let provider = resolved.info().id.clone();
        match self
            .via_session(
                home,
                working_directory,
                &provider,
                Resolved::Frontend(resolved),
                methods::COMPILE,
                &request,
            )
            .await?
        {
            Some(result) => Ok(result),
            None => {
                self.opener
                    .compile_without_session(home, working_directory, resolved, request)
                    .await
            }
        }
    }

    async fn generate(
        &self,
        home: &MorphirHome,
        working_directory: &Path,
        resolved: &ResolvedBackend,
        request: GenerateRequest,
    ) -> Result<GenerateResult, CliError> {
        let provider = resolved.info().id.clone();
        match self
            .via_session(
                home,
                working_directory,
                &provider,
                Resolved::Backend(resolved),
                methods::GENERATE,
                &request,
            )
            .await?
        {
            Some(result) => Ok(result),
            None => {
                self.opener
                    .generate_without_session(home, working_directory, resolved, request)
                    .await
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::extensions::extension_registry;
    use crate::home::MorphirHome;
    use morphir_daemon::extensions::protocol::{ExtensionRequest, ExtensionResponse};
    use morphir_daemon::extensions::{
        ExpectedExtension, InvocationPolicy, MepTransport, Session, TransportError, TransportState,
        spawn_session,
    };
    use morphir_extension_sdk::protocol::{
        InitializeParams, InitializeResult, MEP_VERSION, PeerInfo, RpcError,
    };
    use morphir_extension_sdk::{
        BackendCapability, CompileOptions, CompilePackage, ExtensionCapabilities, ExtensionInfo,
        ExtensionType, FrontendCapability, LanguageCapability,
    };
    use serde_json::json;
    use std::collections::HashMap;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Answers every request in place of a real extension subprocess, counting
    /// what it serves so a test can tell one session from two.
    struct ScriptedExtension {
        served: Arc<AtomicUsize>,
        reject_compiles: bool,
    }

    #[async_trait]
    impl MepTransport for ScriptedExtension {
        fn expected_extension(&self) -> ExpectedExtension {
            ExpectedExtension::identified("scripted")
        }

        async fn exchange(
            &mut self,
            request: ExtensionRequest,
        ) -> Result<ExtensionResponse, TransportError> {
            let result = match request.method.as_str() {
                methods::INITIALIZE => serde_json::to_value(InitializeResult {
                    protocol_version: MEP_VERSION.to_owned(),
                    extension: ExtensionInfo {
                        id: "scripted".to_owned(),
                        name: "Scripted".to_owned(),
                        version: "1.0.0".to_owned(),
                        types: vec![ExtensionType::Frontend, ExtensionType::Backend],
                        ..ExtensionInfo::default()
                    },
                    // The handshake refuses an extension whose declared types
                    // have no matching capability records, so both are filled.
                    capabilities: ExtensionCapabilities {
                        frontend: Some(FrontendCapability {
                            languages: vec![LanguageCapability {
                                id: "gleam".to_owned(),
                                file_extensions: vec![".gleam".to_owned()],
                            }],
                            ir_versions: vec!["4.0.0".to_owned()],
                            compile: true,
                            incremental: false,
                            fragments: false,
                        }),
                        backend: Some(BackendCapability {
                            targets: vec!["gleam".to_owned()],
                            ir_versions: vec!["4.0.0".to_owned()],
                            generate: true,
                        }),
                        ..ExtensionCapabilities::default()
                    },
                })
                .unwrap(),
                methods::COMPILE => {
                    if self.reject_compiles {
                        return Ok(ExtensionResponse::error(
                            request.id,
                            RpcError {
                                code: -32000,
                                message: "scripted rejection".into(),
                                data: None,
                            },
                        ));
                    }
                    let call = self.served.fetch_add(1, Ordering::SeqCst) + 1;
                    // success: false on purpose. The session layer validates a
                    // successful compile's IR as real Morphir IR, and a failed
                    // compile is the one result shape a script can produce
                    // that still round-trips the layer untouched. The invoker
                    // relays failed results exactly like successful ones, so
                    // nothing this module owns goes untested.
                    json!({
                        "success": false,
                        "diagnostics": [{"severity": "error", "message": format!("call-{call}")}],
                        "modules": [],
                    })
                }
                methods::GENERATE => {
                    let call = self.served.fetch_add(1, Ordering::SeqCst) + 1;
                    json!({
                        "success": true,
                        "artifacts": [{"path": format!("out-{call}.gleam"), "content": ""}],
                        "diagnostics": [],
                    })
                }
                _ => json!({}),
            };
            Ok(ExtensionResponse::success(request.id, result).unwrap())
        }

        async fn terminate(&mut self) -> Result<TransportState, TransportError> {
            Ok(TransportState::Stopped)
        }
    }

    async fn scripted_handle(served: Arc<AtomicUsize>, reject_compiles: bool) -> SessionHandle {
        let session = Session::loaded(ScriptedExtension {
            served,
            reject_compiles,
        })
        .initialize(InitializeParams {
            protocol_versions: vec![MEP_VERSION.into()],
            host: PeerInfo {
                name: "test".into(),
                version: "0".into(),
            },
        })
        .await
        .map_err(|failure| failure.into_error().to_string())
        .unwrap();
        spawn_session(session)
    }

    /// Opens scripted sessions and counts everything, so a test can assert
    /// how many sessions ever existed and whether the cold path ran.
    struct CountingOpener {
        served: Arc<AtomicUsize>,
        frontend_opens: AtomicUsize,
        backend_opens: AtomicUsize,
        cold_compiles: AtomicUsize,
        cold_generates: AtomicUsize,
        /// Every handle ever handed out, so a test can end one out-of-band.
        handles: Mutex<Vec<SessionHandle>>,
        /// `None` from both opens, simulating a native-direct provider.
        sessionless: bool,
        /// Shut each session down before handing it out, so every invoke
        /// finds the session already gone.
        dead_on_arrival: bool,
        reject_compiles: bool,
    }

    impl CountingOpener {
        fn new() -> Self {
            Self {
                served: Arc::new(AtomicUsize::new(0)),
                frontend_opens: AtomicUsize::new(0),
                backend_opens: AtomicUsize::new(0),
                cold_compiles: AtomicUsize::new(0),
                cold_generates: AtomicUsize::new(0),
                handles: Mutex::new(Vec::new()),
                sessionless: false,
                dead_on_arrival: false,
                reject_compiles: false,
            }
        }

        async fn handle(&self) -> Option<SessionHandle> {
            if self.sessionless {
                return None;
            }
            let handle = scripted_handle(self.served.clone(), self.reject_compiles).await;
            if self.dead_on_arrival {
                let _ = handle.shutdown().await;
            }
            self.handles.lock().await.push(handle.clone());
            Some(handle)
        }
    }

    #[async_trait]
    impl SessionOpener for CountingOpener {
        async fn open_frontend(
            &self,
            _home: &MorphirHome,
            _workspace: &Path,
            _resolved: &ResolvedFrontend,
        ) -> Result<Option<SessionHandle>, CliError> {
            self.frontend_opens.fetch_add(1, Ordering::SeqCst);
            Ok(self.handle().await)
        }

        async fn open_backend(
            &self,
            _home: &MorphirHome,
            _workspace: &Path,
            _resolved: &ResolvedBackend,
        ) -> Result<Option<SessionHandle>, CliError> {
            self.backend_opens.fetch_add(1, Ordering::SeqCst);
            Ok(self.handle().await)
        }

        async fn compile_without_session(
            &self,
            _home: &MorphirHome,
            _workspace: &Path,
            _resolved: &ResolvedFrontend,
            _request: CompileRequest,
        ) -> Result<CompileResult, CliError> {
            self.cold_compiles.fetch_add(1, Ordering::SeqCst);
            Ok(CompileResult {
                success: true,
                ir_version: Some("4.0.0".into()),
                ir: Some(json!({})),
                diagnostics: vec![],
                modules: vec!["cold".into()],
            })
        }

        async fn generate_without_session(
            &self,
            _home: &MorphirHome,
            _workspace: &Path,
            _resolved: &ResolvedBackend,
            _request: GenerateRequest,
        ) -> Result<GenerateResult, CliError> {
            self.cold_generates.fetch_add(1, Ordering::SeqCst);
            Ok(GenerateResult {
                success: true,
                artifacts: vec![],
                diagnostics: vec![],
            })
        }
    }

    struct Fixture {
        home: MorphirHome,
        workspace: tempfile::TempDir,
        frontend: ResolvedFrontend,
        backend: ResolvedBackend,
    }

    fn fixture() -> Fixture {
        let workspace = tempfile::tempdir().unwrap();
        let home = MorphirHome::resolve_from(Some(workspace.path().join("home").as_os_str()), None)
            .unwrap();
        let registry = extension_registry([]).unwrap();
        let frontend = registry
            .resolve_frontend("gleam", "4.0.0", InvocationPolicy::ProtocolOnly)
            .unwrap();
        let backend = registry
            .resolve_backend("gleam", "4.0.0", InvocationPolicy::ProtocolOnly)
            .unwrap();
        Fixture {
            home,
            workspace,
            frontend,
            backend,
        }
    }

    fn compile_request() -> CompileRequest {
        CompileRequest {
            language_id: "gleam".into(),
            documents: vec![],
            package: CompilePackage {
                name: "example/test".into(),
                exposed_modules: vec![],
            },
            dependencies: vec![],
            options: CompileOptions {
                types_only: false,
                ir_version: "4.0.0".into(),
                extra: HashMap::new(),
            },
        }
    }

    fn generate_request() -> GenerateRequest {
        GenerateRequest {
            ir: json!({}),
            target: "gleam".into(),
            options: HashMap::new(),
        }
    }

    // Requirement: this module's whole purpose. Two compiles must ride one
    // session — one open, and the extension's own state carried across calls
    // proves the second request reached the same session, not a lookalike.
    #[tokio::test]
    async fn two_compiles_share_one_session() {
        let fx = fixture();
        let invoker = SessionReuseInvoker::new(CountingOpener::new());

        let first = invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap();
        let second = invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap();

        assert_eq!(first.diagnostics[0].message, "call-1");
        assert_eq!(second.diagnostics[0].message, "call-2");
        assert_eq!(invoker.opener.frontend_opens.load(Ordering::SeqCst), 1);
        assert_eq!(invoker.opener.cold_compiles.load(Ordering::SeqCst), 0);
    }

    // A session belongs to a provider, not to an operation: the generate that
    // follows a compile rides the session the compile opened.
    #[tokio::test]
    async fn a_generate_reuses_the_session_the_compile_opened() {
        let fx = fixture();
        let invoker = SessionReuseInvoker::new(CountingOpener::new());

        invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap();
        let generated = invoker
            .generate(
                &fx.home,
                fx.workspace.path(),
                &fx.backend,
                generate_request(),
            )
            .await
            .unwrap();

        // served=2 on the same counter: the same scripted session answered both.
        assert_eq!(generated.artifacts[0].path, "out-2.gleam");
        assert_eq!(invoker.opener.frontend_opens.load(Ordering::SeqCst), 1);
        assert_eq!(invoker.opener.backend_opens.load(Ordering::SeqCst), 0);
    }

    // Requirement: SessionLost is an eviction signal, not an answer. A session
    // that ended between requests (idle-stopped, crashed) costs the user
    // nothing: the request runs again on a fresh session.
    #[tokio::test]
    async fn a_lost_session_is_evicted_and_the_request_retried_once() {
        let fx = fixture();
        let invoker = SessionReuseInvoker::new(CountingOpener::new());

        invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap();
        // End the cached session out-of-band, as the idle watchdog would.
        invoker.opener.handles.lock().await[0]
            .shutdown()
            .await
            .unwrap();

        let retried = invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap();

        // The shut-down session cannot answer at all, so an answer proves the
        // retry ran on a fresh one — and the second open proves which one.
        assert_eq!(retried.diagnostics[0].message, "call-2");
        assert_eq!(invoker.opener.frontend_opens.load(Ordering::SeqCst), 2);
    }

    // One retry, not a loop: a provider whose sessions die on arrival
    // surfaces as an error, and the dead handle is not left cached to burn
    // the single retry of every later request.
    #[tokio::test]
    async fn a_retry_that_also_loses_its_session_surfaces_and_clears_the_cache() {
        let fx = fixture();
        let mut opener = CountingOpener::new();
        opener.dead_on_arrival = true;
        let invoker = SessionReuseInvoker::new(opener);

        let error = invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap_err();
        assert!(error.to_string().contains("scripted") || error.to_string().contains("gleam"));
        assert_eq!(invoker.opener.frontend_opens.load(Ordering::SeqCst), 2);

        // The cache is empty again: the next request opens fresh rather than
        // finding the dead retry handle.
        let _ = invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await;
        assert_eq!(invoker.opener.frontend_opens.load(Ordering::SeqCst), 4);
    }

    // An extension rejecting one request is the extension answering, not the
    // session dying. The session stays cached and the next request reuses it.
    #[tokio::test]
    async fn a_rejection_surfaces_but_keeps_the_session() {
        let fx = fixture();
        let mut opener = CountingOpener::new();
        opener.reject_compiles = true;
        let invoker = SessionReuseInvoker::new(opener);

        let error = invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap_err();
        assert!(error.to_string().contains("scripted rejection"));

        let error = invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap_err();
        assert!(error.to_string().contains("scripted rejection"));
        assert_eq!(invoker.opener.frontend_opens.load(Ordering::SeqCst), 1);
    }

    // A native-direct provider has no session; the invoker must not invent
    // one, and the request goes down the same one-shot path it always used.
    #[tokio::test]
    async fn a_sessionless_provider_goes_one_shot_every_time() {
        let fx = fixture();
        let mut opener = CountingOpener::new();
        opener.sessionless = true;
        let invoker = SessionReuseInvoker::new(opener);

        let compiled = invoker
            .compile(
                &fx.home,
                fx.workspace.path(),
                &fx.frontend,
                compile_request(),
            )
            .await
            .unwrap();
        let generated = invoker
            .generate(
                &fx.home,
                fx.workspace.path(),
                &fx.backend,
                generate_request(),
            )
            .await
            .unwrap();

        assert_eq!(compiled.modules, vec!["cold".to_string()]);
        assert!(generated.success);
        assert_eq!(invoker.opener.cold_compiles.load(Ordering::SeqCst), 1);
        assert_eq!(invoker.opener.cold_generates.load(Ordering::SeqCst), 1);
    }
}

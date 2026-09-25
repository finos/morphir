//! Compiling source and generating artifacts for the Morphir Playground,
//! entirely in memory.
//!
//! The playground is a scratch surface: someone pastes a module into a
//! browser, compiles it, and downloads what comes back. Nothing it produces
//! belongs on the user's filesystem, so unlike `morphir generate` — which
//! publishes returned artifacts to an output directory — this provider
//! carries every artifact back inside the response and writes no files at
//! all. Keeping that promise here is also what lets a future in-browser
//! implementation behave identically.
//!
//! Provider selection is not this module's business. It builds the same
//! [`Registry`] `morphir compile` and `morphir generate` build, and
//! asks it to resolve a language or a target, so the playground offers
//! exactly what the rest of the CLI offers — built-ins included — and cannot
//! drift onto a private notion of which provider serves what.
//!
//! That includes the project's choice of provider. A workspace that names one
//! in `[frontend.<language>] extension` gets it here too, restricting the
//! registry the way `--extension` does, so a project configured for an opt-in
//! built-in such as `morphir-elm-native` is not quietly compiled by a
//! different provider in the browser than on the command line. There is no
//! flag to override it with: the playground has only the configuration.

use std::collections::HashMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use morphir_common::config::model::FrontendSection;
use morphir_daemon::DaemonError;
use morphir_devkit::{ConfigLoadOptions, discover_config, load_config_context_with};
use morphir_distribution::list_installed;
use morphir_extension_sdk::{
    Artifact, CompileRequest, CompileResult, Diagnostic, DiagnosticSeverity, GenerateRequest,
    GenerateResult, SourceLocation,
};
use morphir_host::{
    CapabilityMetadataScope, InvocationMode, InvocationPolicy, ProviderMetadata, ProviderOrigin,
    Registry, Resolved,
};
use serde_json::Value;

use crate::commands::compile::frontend_extension;
use crate::commands::ui::protocol::{
    PlaygroundArtifact, PlaygroundCatalog, PlaygroundCompileParams, PlaygroundCompileResult,
    PlaygroundDiagnostic, PlaygroundFrontend, PlaygroundGenerateParams, PlaygroundGenerateResult,
    PlaygroundLocation, PlaygroundPosition, PlaygroundProviderOrigin, PlaygroundProviderRef,
    PlaygroundRange, PlaygroundTarget, ProviderKind, ProviderManifest, ProviderStatus,
};
use crate::error::CliError;
use crate::extensions::extension_registry_for;
use crate::home::MorphirHome;

use super::PlaygroundCapability;
use super::native::capability;
use super::pool::PooledInvoker;

/// How long the playground waits for one extension invocation.
///
/// WASM extensions run under resource limits, but a process-backed extension
/// is an ordinary child process that can hang indefinitely. A browser tab
/// waiting forever on a compile is worse than one told the compile gave up,
/// so every invocation is bounded and a lapsed bound is reported as a
/// diagnostic rather than a transport failure.
const INVOCATION_TIMEOUT: Duration = Duration::from_secs(120);

/// Answers "which providers does this session have?".
///
/// The argument is the provider id the request is restricted to, or `None` for
/// every provider this session can reach. It is the same restriction
/// `--extension` applies on the command line, and it is what registers an
/// opt-in built-in at all.
///
/// Injectable so a test can register its own providers without installing an
/// extension into a Morphir home.
type RegistrySource = Arc<dyn Fn(Option<&str>) -> Result<Registry, CliError> + Send + Sync>;

/// How the playground reaches a resolved provider.
///
/// Production is [`PooledInvoker`], which keeps one warm guest per provider
/// and otherwise delegates to the CLI's own extension boundary, the same
/// functions `morphir compile` and `morphir generate` call, so the playground
/// cannot acquire a private invocation path. Injectable so a test can drive
/// an invocation that never answers and observe the timeout without waiting
/// two real minutes.
#[async_trait]
pub(super) trait ExtensionInvoker: Send + Sync {
    async fn compile(
        &self,
        working_directory: &Path,
        resolved: &Resolved,
        request: CompileRequest,
    ) -> Result<CompileResult, CliError>;

    async fn generate(
        &self,
        working_directory: &Path,
        resolved: &Resolved,
        request: GenerateRequest,
    ) -> Result<GenerateResult, CliError>;

    /// Forget any state held for `provider`, after an invocation outlived the
    /// playground's patience.
    ///
    /// A timeout drops the invocation future before any of the invoker's own
    /// error handling can run, so an invoker that caches per-provider state,
    /// such as a guest that may still be wedged on the hung exchange, must
    /// be told out-of-band, or every later request for that provider queues
    /// behind the same hang and times out too. A no-op for invokers that hold
    /// nothing.
    async fn abandon(&self, _provider: &str) {}
}

/// Either the extension answered, or it outlasted the playground's patience.
enum Invocation<R> {
    Answered(R),
    TimedOut,
}

pub struct NativePlaygroundProvider {
    registry: RegistrySource,
    /// The workspace's `[frontend]` section, when one was found and loaded, so
    /// a compile can read the provider the project asked for. `None` when the
    /// playground was launched outside a workspace, or when the configuration
    /// could not be read at all — the playground is a scratch surface and must
    /// still open.
    frontend: Option<FrontendSection>,
    invoker: Arc<dyn ExtensionInvoker>,
    /// Where an installed extension process runs. See
    /// [`extension_working_directory`]: the playground never writes here, it
    /// is only the directory a child process is started in.
    working_directory: PathBuf,
    /// How long one invocation may take. [`INVOCATION_TIMEOUT`] in
    /// production; a test shortens it so it can watch the bound lapse without
    /// waiting two real minutes.
    timeout: Duration,
}

impl NativePlaygroundProvider {
    /// Build a provider that offers the built-in providers plus whatever is
    /// installed in `home`, reading the workspace configuration, if any, from
    /// the directory the CLI was launched in.
    pub fn new(home: MorphirHome) -> Self {
        let workspace = extension_working_directory(&home);
        Self::in_workspace(home, &workspace)
    }

    /// As [`new`](Self::new), for a session that knows its workspace.
    pub fn in_workspace(home: MorphirHome, workspace: &Path) -> Self {
        let working_directory = extension_working_directory(&home);
        Self::with_parts(
            Arc::new(move |only| installed_registry(&home, only)),
            workspace_frontend(workspace),
            // Pooled on purpose: a provider with a guest pays activation and
            // the MEP handshake once per guest instead of once per click. See
            // the pool module for the reuse and eviction rules.
            Arc::new(PooledInvoker::new(crate::commands::extension::host_config())),
            working_directory,
            INVOCATION_TIMEOUT,
        )
    }

    fn with_parts(
        registry: RegistrySource,
        frontend: Option<FrontendSection>,
        invoker: Arc<dyn ExtensionInvoker>,
        working_directory: PathBuf,
        timeout: Duration,
    ) -> Self {
        Self {
            registry,
            frontend,
            invoker,
            working_directory,
            timeout,
        }
    }
}

#[async_trait]
impl PlaygroundCapability for NativePlaygroundProvider {
    fn manifest(&self) -> ProviderManifest {
        ProviderManifest {
            id: "playground".into(),
            name: "Morphir Playground".into(),
            kind: ProviderKind::Connected,
            status: ProviderStatus::Available,
            capabilities: vec![
                capability("morphir/playground/catalog"),
                capability("morphir/playground/compile"),
                capability("morphir/playground/generate"),
            ],
            provenance: None,
        }
    }

    /// The catalog lists every provider this session can reach, unrestricted.
    /// A per-language restriction belongs to one compile, not to the list of
    /// what exists: applying the Elm entry here would drop every other
    /// language's provider from the picker.
    async fn catalog(&self) -> Result<PlaygroundCatalog, CliError> {
        Ok(project_catalog(&(self.registry)(None)?))
    }

    async fn compile(
        &self,
        params: PlaygroundCompileParams,
    ) -> Result<PlaygroundCompileResult, CliError> {
        // The project's choice of provider for this language, read exactly as
        // `morphir compile` reads it. There is no flag to override it here.
        let configured =
            frontend_extension::from_config(self.frontend.as_ref(), &params.language_id)?;
        let registry = (self.registry)(configured.as_deref())?;
        // The registry checks the language, the compile flag, and the IR
        // version together, and reports which providers were considered, so
        // there is nothing left for this layer to re-check.
        let resolved = registry
            .resolve_frontend(
                &params.language_id,
                &params.ir_version,
                InvocationPolicy::PreferDirect,
            )
            .map_err(DaemonError::from)
            .map_err(|error| match configured.as_deref() {
                Some(id) => CliError::Validation {
                    message: format!(
                        "extension '{id}' does not provide language '{}': {error}",
                        params.language_id
                    ),
                },
                None => CliError::Validation {
                    message: format!(
                        "No extension compiles language '{}' at Morphir IR version '{}': {error}",
                        params.language_id, params.ir_version
                    ),
                },
            })?;
        let provider_id = resolved.info().id.clone();
        let request = compile_request(params)?;
        request
            .source_paths()
            .map_err(|error| CliError::Validation {
                message: error.to_string(),
            })?;
        let invocation = self
            .invoker
            .compile(&self.working_directory, &resolved, request);
        match bounded(invocation, self.timeout).await? {
            Invocation::Answered(result) => Ok(PlaygroundCompileResult {
                success: result.success,
                ir_version: result.ir_version,
                ir: result.ir,
                diagnostics: result
                    .diagnostics
                    .iter()
                    .map(playground_diagnostic)
                    .collect(),
                modules: result.modules,
            }),
            Invocation::TimedOut => {
                self.invoker.abandon(&provider_id).await;
                Ok(PlaygroundCompileResult {
                    success: false,
                    ir_version: None,
                    ir: None,
                    diagnostics: vec![timeout_diagnostic(&provider_id, self.timeout)],
                    modules: Vec::new(),
                })
            }
        }
    }

    async fn generate(
        &self,
        params: PlaygroundGenerateParams,
    ) -> Result<PlaygroundGenerateResult, CliError> {
        // A target is a backend, and the key selects a frontend for a source
        // language, so generate resolves against every provider.
        let registry = (self.registry)(None)?;
        let resolved = registry
            .resolve_backend(
                &params.target,
                &params.ir_version,
                InvocationPolicy::PreferDirect,
            )
            .map_err(DaemonError::from)
            .map_err(|error| CliError::Validation {
                message: format!(
                    "No extension generates target '{}' at Morphir IR version '{}': {error}",
                    params.target, params.ir_version
                ),
            })?;
        let provider_id = resolved.info().id.clone();
        let request = GenerateRequest {
            ir: params.ir,
            target: params.target,
            options: generate_options(&params.options),
        };
        // Artifacts stay in the response. Unlike `morphir generate`, nothing
        // is published to an output directory; the web app offers each
        // artifact as a download.
        let invocation = self
            .invoker
            .generate(&self.working_directory, &resolved, request);
        match bounded(invocation, self.timeout).await? {
            Invocation::Answered(result) => Ok(PlaygroundGenerateResult {
                success: result.success,
                artifacts: result.artifacts.iter().map(playground_artifact).collect(),
                diagnostics: result
                    .diagnostics
                    .iter()
                    .map(playground_diagnostic)
                    .collect(),
            }),
            Invocation::TimedOut => {
                self.invoker.abandon(&provider_id).await;
                Ok(PlaygroundGenerateResult {
                    success: false,
                    artifacts: Vec::new(),
                    diagnostics: vec![timeout_diagnostic(&provider_id, self.timeout)],
                })
            }
        }
    }
}

/// Bound one invocation by `timeout`.
///
/// A lapsed bound is `Ok(TimedOut)`, not an error: the caller turns it into a
/// diagnostic on an otherwise well-formed result, because "the compiler gave
/// up" is something the editor shows in its problems list, not a broken
/// connection.
async fn bounded<R>(
    invocation: impl Future<Output = Result<R, CliError>>,
    timeout: Duration,
) -> Result<Invocation<R>, CliError> {
    match tokio::time::timeout(timeout, invocation).await {
        Ok(answered) => answered.map(Invocation::Answered),
        Err(_elapsed) => Ok(Invocation::TimedOut),
    }
}

fn installed_registry(home: &MorphirHome, only: Option<&str>) -> Result<Registry, CliError> {
    let installed = list_installed(home).map_err(|error| CliError::Extension {
        message: format!("Failed to list installed extensions: {error}"),
    })?;
    extension_registry_for(home, installed, only)
}

/// The `[frontend]` section of the workspace's configuration, if it has one.
///
/// The playground opens whether or not there is a project here, and whether or
/// not that project's configuration is readable, so neither is an error: a
/// configuration that cannot be loaded is reported once, as a warning, and the
/// session carries on with no configured provider. A
/// `[frontend.<language>] extension` that is itself malformed is a different
/// matter, and still fails the compile that reads it.
fn workspace_frontend(workspace: &Path) -> Option<FrontendSection> {
    let config_path = match discover_config(workspace) {
        Ok(found) => found?,
        Err(error) => {
            tracing::warn!(
                %error,
                "Unable to look for a Morphir configuration; the playground will use default providers"
            );
            return None;
        }
    };
    match load_config_context_with(&config_path, &ConfigLoadOptions::default()) {
        Ok(context) => context.config.frontend,
        Err(error) => {
            tracing::warn!(
                %error,
                config = %config_path.display(),
                "Unable to load the Morphir configuration; the playground will use default providers"
            );
            None
        }
    }
}

/// Project the registry's provider metadata into the browser-facing catalog.
///
/// Built-ins are listed alongside installed providers, because the registry
/// resolves and invokes both the same way. They are listed *after* them:
/// [`Registry::resolve_frontend`] prefers an installed provider when
/// two offer the same language, and the catalog's first-match-wins lookups
/// have to agree with that or the picker would name a provider the compile
/// would not use.
fn project_catalog(registry: &Registry) -> PlaygroundCatalog {
    let mut providers = registry.providers();
    providers.sort_by_key(|provider| std::cmp::Reverse(provider.origin()));
    let mut frontends = Vec::new();
    let mut targets = Vec::new();
    for provider in &providers {
        let reference = provider_ref(provider);
        if let Some(frontend) = provider.capabilities().frontend.as_ref() {
            let known = capability_metadata_is_complete(provider);
            for language in &frontend.languages {
                frontends.push(PlaygroundFrontend {
                    language_id: language.id.clone(),
                    display_name: provider.info().name.clone(),
                    file_extensions: language.file_extensions.clone(),
                    ir_versions: frontend.ir_versions.clone(),
                    compile: frontend.compile,
                    incremental: known.then_some(frontend.incremental),
                    fragments: known.then_some(frontend.fragments),
                    provider: reference.clone(),
                });
            }
        }
        if let Some(backend) = provider.capabilities().backend.as_ref() {
            for target in &backend.targets {
                targets.push(PlaygroundTarget {
                    target: target.clone(),
                    display_name: provider.info().name.clone(),
                    ir_versions: backend.ir_versions.clone(),
                    generate: backend.generate,
                    provider: reference.clone(),
                });
            }
        }
    }
    PlaygroundCatalog { frontends, targets }
}

/// Whether a provider's capability snapshot represents everything it reports.
///
/// Only [`CapabilityMetadataScope::Complete`] means the flags on the snapshot
/// came from the provider itself. Under
/// [`CapabilityMetadataScope::PersistedFrontendBackend`] the snapshot was
/// rebuilt from installed state, which persists the languages, the IR versions
/// and the compile flag and nothing else — so `incremental` and `fragments`
/// there are defaults, not answers, and the catalog reports them as unknown.
fn capability_metadata_is_complete(provider: &ProviderMetadata) -> bool {
    match provider.capability_metadata_scope() {
        CapabilityMetadataScope::Complete => true,
        // A scope this CLI does not know makes no promise about the flags.
        _ => false,
    }
}

fn provider_ref(provider: &ProviderMetadata) -> PlaygroundProviderRef {
    PlaygroundProviderRef {
        extension_id: provider.info().id.clone(),
        extension_name: provider.info().name.clone(),
        version: provider.info().version.clone(),
        origin: match provider.origin() {
            ProviderOrigin::Builtin => PlaygroundProviderOrigin::Builtin,
            // Anything not built into this CLI came from outside it.
            _ => PlaygroundProviderOrigin::Installed,
        },
        invocation_mode: invocation_mode_name(provider.preferred_invocation_mode()).to_owned(),
    }
}

fn invocation_mode_name(mode: InvocationMode) -> &'static str {
    match mode {
        InvocationMode::NativeDirect => "native-direct",
        InvocationMode::NativeMep => "native-mep",
        InvocationMode::ProcessMep => "process-mep",
        InvocationMode::WasmMep => "wasm-mep",
        _ => "unknown",
    }
}

/// The directory an installed extension process runs in.
///
/// The playground has no workspace, so this is the directory the CLI was
/// launched from, falling back to the Morphir home. It is where the
/// extension runs, not where anything is written: the playground reads every
/// artifact out of the response.
fn extension_working_directory(home: &MorphirHome) -> PathBuf {
    std::env::current_dir().unwrap_or_else(|_| home.root().to_path_buf())
}

/// Translate browser-facing compile params into the extension request.
///
/// The playground compiles one self-contained package, so `dependencies` is
/// always empty.
fn compile_request(params: PlaygroundCompileParams) -> Result<CompileRequest, CliError> {
    // The browser protocol still carries documents and an optional root in its
    // options. The SDK takes only the `sources` envelope, so the root moves out
    // of the options and into the source set here.
    let mut options = compile_options(params.ir_version, &params.options);
    let root = take_source_root(&mut options)?;
    serde_json::from_value(serde_json::json!({
        "languageId": params.language_id,
        "sources": { "root": root, "documents": params.documents },
        "package": params.package,
        "dependencies": [],
        "options": options,
    }))
    .map_err(|error| CliError::Validation {
        message: format!("Invalid playground compile request: {error}"),
    })
}

/// The source root the browser names in its options, as `sourceRootUri` or
/// `sourceRoot`, removed from the options. Two different roots are refused.
fn take_source_root(options: &mut HashMap<String, Value>) -> Result<Option<String>, CliError> {
    let mut root: Option<String> = None;
    for key in ["sourceRootUri", "sourceRoot"] {
        let Some(value) = options.remove(key) else {
            continue;
        };
        let Value::String(text) = value else {
            return Err(CliError::Validation {
                message: format!("Invalid playground compile request: {key} is a string"),
            });
        };
        match &root {
            Some(existing) if *existing != text => {
                return Err(CliError::Validation {
                    message: format!(
                        "Invalid playground compile request: sourceRootUri and sourceRoot name different roots ({existing} and {text})"
                    ),
                });
            }
            _ => root = Some(text),
        }
    }
    Ok(root)
}

/// Prepare the browser options for the SDK's compile-envelope decoder.
///
/// `typesOnly` retains its boolean default, and the request's own `irVersion`
/// is authoritative. The decoder moves the source root into the source set.
fn compile_options(ir_version: String, options: &Value) -> HashMap<String, Value> {
    let mut extra = option_map(options);
    let types_only = extra
        .remove("typesOnly")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    extra.insert("typesOnly".into(), Value::Bool(types_only));
    extra.insert("irVersion".into(), Value::String(ir_version));
    deny_output_options(&mut extra);
    extra
}

fn generate_options(options: &Value) -> HashMap<String, Value> {
    let mut extra = option_map(options);
    deny_output_options(&mut extra);
    extra
}

/// Strip the options that ask a provider to put something on disk.
///
/// The no-write promise is the host's, but the host is what hands providers
/// their options, and two of the ones the CLI passes are requests to write:
/// `outputDir` names a directory to publish into, and `emitParseStage` asks
/// the Gleam frontend to serialize its parse tree there — defaulting to the
/// process working directory when no `outputDir` is given. A browser has no
/// business setting either, and the playground has nowhere for the results
/// to go, so both are removed and `emitParseStage` is pinned off rather than
/// merely absent, since absent means on.
fn deny_output_options(extra: &mut HashMap<String, Value>) {
    extra.remove("outputDir");
    extra.insert("emitParseStage".to_owned(), Value::Bool(false));
}

fn option_map(options: &Value) -> HashMap<String, Value> {
    options
        .as_object()
        .map(|map| {
            map.iter()
                .map(|(key, value)| (key.clone(), value.clone()))
                .collect()
        })
        .unwrap_or_default()
}

fn timeout_diagnostic(extension_id: &str, bound: Duration) -> PlaygroundDiagnostic {
    PlaygroundDiagnostic {
        severity: "error".into(),
        code: None,
        message: format!(
            "Extension '{extension_id}' timed out after {}s",
            bound.as_secs()
        ),
        location: None,
    }
}

fn playground_artifact(artifact: &Artifact) -> PlaygroundArtifact {
    PlaygroundArtifact {
        path: artifact.path.clone(),
        content: artifact.content.clone(),
        binary: artifact.binary,
    }
}

fn playground_diagnostic(diagnostic: &Diagnostic) -> PlaygroundDiagnostic {
    PlaygroundDiagnostic {
        severity: severity_name(diagnostic.severity).to_owned(),
        code: diagnostic.code.clone(),
        message: diagnostic.message.clone(),
        location: diagnostic.location.as_ref().map(playground_location),
    }
}

fn severity_name(severity: DiagnosticSeverity) -> &'static str {
    match severity {
        DiagnosticSeverity::Error => "error",
        DiagnosticSeverity::Warning => "warning",
        DiagnosticSeverity::Info => "info",
        DiagnosticSeverity::Hint => "hint",
    }
}

fn playground_location(location: &SourceLocation) -> PlaygroundLocation {
    PlaygroundLocation {
        uri: location.uri.clone(),
        range: PlaygroundRange {
            start: PlaygroundPosition {
                line: location.range.start.line,
                character: location.range.start.character,
            },
            end: PlaygroundPosition {
                line: location.range.end.line,
                character: location.range.end.character,
            },
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::ui::protocol::{PlaygroundPackage, PlaygroundSourceDocument};
    use morphir_distribution::InstalledExtensionSnapshot;
    use morphir_extension_sdk::{
        Backend, BackendCapability, Extension, ExtensionCapabilities, ExtensionInfo, Frontend,
        FrontendCapability, LanguageCapability, NativeExtension,
    };
    use morphir_host_native::NativeSource;
    use std::sync::{Condvar, Mutex, Mutex as StdMutex};

    /// The one IR release every double in this module speaks. Gleam, the only
    /// built-in, advertises the same one, so a test that registers a double
    /// alongside the built-ins is asking a real question about precedence.
    const IR_VERSION: &str = "4.0.0";

    // ---------------------------------------------------------------- doubles

    /// A frontend that answers every compile with one prepared result.
    struct FixedFrontend {
        response: CompileResult,
    }

    impl Extension for FixedFrontend {
        fn info() -> ExtensionInfo {
            ExtensionInfo {
                id: "example-frontend".into(),
                name: "Example Frontend".into(),
                version: "1.0.0".into(),
                ..Default::default()
            }
        }

        fn capabilities() -> ExtensionCapabilities {
            ExtensionCapabilities {
                frontend: Some(FrontendCapability {
                    languages: vec![LanguageCapability {
                        id: "elm".into(),
                        file_extensions: vec![".elm".into()],
                    }],
                    ir_versions: vec![IR_VERSION.into()],
                    compile: true,
                    incremental: false,
                    fragments: false,
                    multi_document: false,
                }),
                ..Default::default()
            }
        }
    }

    impl Frontend for FixedFrontend {
        fn compile(
            &self,
            _request: CompileRequest,
        ) -> morphir_extension_sdk::Result<CompileResult> {
            Ok(self.response.clone())
        }

        fn supported_languages() -> Vec<String> {
            vec!["elm".into()]
        }

        fn file_extensions() -> Vec<String> {
            vec![".elm".into()]
        }
    }

    /// A latch a test holds closed while it checks something, then opens.
    ///
    /// Blocking on this from a provider is what a runaway parser looks like
    /// from the outside: a thread that is busy and will not yield. The wait
    /// carries its own upper bound so a regression fails the assertion
    /// instead of hanging the suite.
    #[derive(Default)]
    struct Gate {
        open: Mutex<bool>,
        opened: Condvar,
    }

    impl Gate {
        fn wait(&self, bound: Duration) {
            let mut open = self.open.lock().expect("the latch is never poisoned");
            let deadline = std::time::Instant::now() + bound;
            while !*open {
                let remaining = deadline.saturating_duration_since(std::time::Instant::now());
                if remaining.is_zero() {
                    return;
                }
                let (guard, _) = self
                    .opened
                    .wait_timeout(open, remaining)
                    .expect("the latch is never poisoned");
                open = guard;
            }
        }

        fn open(&self) {
            *self.open.lock().expect("the latch is never poisoned") = true;
            self.opened.notify_all();
        }
    }

    /// A built-in frontend whose `compile` occupies its thread and never
    /// yields, the way a pathological input to a real parser would.
    struct BlockingFrontend {
        gate: Arc<Gate>,
    }

    /// The longest a blocked compile stays blocked before giving up on its
    /// own. Only a safety valve: the test opens the latch as soon as it has
    /// what it needs.
    const BLOCKED_COMPILE_BOUND: Duration = Duration::from_secs(10);

    impl Extension for BlockingFrontend {
        fn info() -> ExtensionInfo {
            ExtensionInfo {
                id: "blocking-frontend".into(),
                name: "Blocking Frontend".into(),
                version: "1.0.0".into(),
                ..Default::default()
            }
        }

        fn capabilities() -> ExtensionCapabilities {
            ExtensionCapabilities {
                frontend: Some(FrontendCapability {
                    languages: vec![LanguageCapability {
                        id: "blocking".into(),
                        file_extensions: vec![".blocking".into()],
                    }],
                    ir_versions: vec![IR_VERSION.into()],
                    compile: true,
                    incremental: false,
                    fragments: false,
                    multi_document: false,
                }),
                ..Default::default()
            }
        }
    }

    impl Frontend for BlockingFrontend {
        fn compile(
            &self,
            _request: CompileRequest,
        ) -> morphir_extension_sdk::Result<CompileResult> {
            self.gate.wait(BLOCKED_COMPILE_BOUND);
            Ok(CompileResult {
                success: true,
                ir_version: None,
                ir: None,
                diagnostics: vec![],
                modules: vec![],
                module_results: Vec::new(),
                context_digest: None,
            })
        }

        fn supported_languages() -> Vec<String> {
            vec!["blocking".into()]
        }

        fn file_extensions() -> Vec<String> {
            vec![".blocking".into()]
        }
    }

    /// A backend that answers every generate with one prepared result.
    struct FixedBackend {
        response: GenerateResult,
    }

    impl Extension for FixedBackend {
        fn info() -> ExtensionInfo {
            ExtensionInfo {
                id: "example-backend".into(),
                name: "Example Backend".into(),
                version: "1.0.0".into(),
                ..Default::default()
            }
        }

        fn capabilities() -> ExtensionCapabilities {
            ExtensionCapabilities {
                backend: Some(BackendCapability {
                    targets: vec!["avro".into()],
                    ir_versions: vec![IR_VERSION.into()],
                    generate: true,
                }),
                ..Default::default()
            }
        }
    }

    impl Backend for FixedBackend {
        fn generate(
            &self,
            _request: GenerateRequest,
        ) -> morphir_extension_sdk::Result<GenerateResult> {
            Ok(self.response.clone())
        }

        fn target_languages() -> Vec<String> {
            vec!["avro".into()]
        }
    }

    /// An invoker that delegates to the registry but records the requests it
    /// was handed, so a test can inspect exactly what an extension would see.
    #[derive(Default)]
    struct RecordingInvoker {
        compiles: Mutex<Vec<CompileRequest>>,
        generates: Mutex<Vec<GenerateRequest>>,
    }

    #[async_trait]
    impl ExtensionInvoker for RecordingInvoker {
        async fn compile(
            &self,
            working_directory: &Path,
            resolved: &Resolved,
            request: CompileRequest,
        ) -> Result<CompileResult, CliError> {
            self.compiles
                .lock()
                .expect("the log is never poisoned")
                .push(request.clone());
            crate::extensions::invoke_frontend(working_directory, resolved, request).await
        }

        async fn generate(
            &self,
            working_directory: &Path,
            resolved: &Resolved,
            request: GenerateRequest,
        ) -> Result<GenerateResult, CliError> {
            self.generates
                .lock()
                .expect("the log is never poisoned")
                .push(request.clone());
            crate::extensions::invoke_backend(working_directory, resolved, request).await
        }
    }

    /// An invoker that never answers within the caller's patience, recording
    /// which providers the playground told it to abandon afterwards.
    struct SleepingInvoker {
        delay: Duration,
        abandoned: StdMutex<Vec<String>>,
    }

    impl SleepingInvoker {
        fn new(delay: Duration) -> Self {
            Self {
                delay,
                abandoned: StdMutex::new(Vec::new()),
            }
        }
    }

    #[async_trait]
    impl ExtensionInvoker for SleepingInvoker {
        async fn compile(
            &self,
            _working_directory: &Path,
            _resolved: &Resolved,
            _request: CompileRequest,
        ) -> Result<CompileResult, CliError> {
            tokio::time::sleep(self.delay).await;
            unreachable!("the playground gives up before this invoker answers")
        }

        async fn generate(
            &self,
            _working_directory: &Path,
            _resolved: &Resolved,
            _request: GenerateRequest,
        ) -> Result<GenerateResult, CliError> {
            tokio::time::sleep(self.delay).await;
            unreachable!("the playground gives up before this invoker answers")
        }

        async fn abandon(&self, provider: &str) {
            self.abandoned
                .lock()
                .expect("the log is never poisoned")
                .push(provider.to_owned());
        }
    }

    /// An invoker that fails loudly: tests using it must answer before any
    /// extension is reached.
    struct UnreachableInvoker;

    #[async_trait]
    impl ExtensionInvoker for UnreachableInvoker {
        async fn compile(
            &self,
            _working_directory: &Path,
            resolved: &Resolved,
            _request: CompileRequest,
        ) -> Result<CompileResult, CliError> {
            panic!("invoked frontend '{}' unexpectedly", resolved.info().id)
        }

        async fn generate(
            &self,
            _working_directory: &Path,
            resolved: &Resolved,
            _request: GenerateRequest,
        ) -> Result<GenerateResult, CliError> {
            panic!("invoked backend '{}' unexpectedly", resolved.info().id)
        }
    }

    // ---------------------------------------------------------------- harness

    struct Fixture {
        provider: NativePlaygroundProvider,
        _home_root: tempfile::TempDir,
        working: tempfile::TempDir,
        home_root: PathBuf,
    }

    fn scratch_home() -> (tempfile::TempDir, MorphirHome) {
        let root = tempfile::tempdir().expect("a temporary Morphir home");
        let home = MorphirHome::resolve_from(Some(root.path().as_os_str()), None)
            .expect("an explicit Morphir home resolves");
        (root, home)
    }

    /// Install a real extension into a scratch Morphir home and return the
    /// home and its snapshot.
    ///
    /// Registering a fabricated snapshot would not answer the question these
    /// tests ask: an installed provider's capability metadata is rebuilt from
    /// what the install actually persisted, so the snapshot has to come from
    /// a real index and a real install.
    ///
    /// The returned directory owns the home the snapshot points into and must
    /// outlive it.
    fn installed_snapshot(
        extension_id: &str,
        language: &str,
        target: &str,
    ) -> (tempfile::TempDir, MorphirHome, InstalledExtensionSnapshot) {
        let root = tempfile::tempdir().expect("a temporary install root");
        let (home, snapshot) = crate::extensions::installed_fixture::install_process(
            root.path(),
            serde_json::json!({
                "schemaVersion": "1.0",
                "id": extension_id,
                "name": format!("Installed {extension_id}"),
                "version": "2.0.0",
                "channels": ["stable"],
                "mepVersions": ["0.1"],
                "capabilities": ["frontend", "backend"],
                "frontend": {
                    "languages": [{
                        "id": language,
                        "fileExtensions": [format!(".{language}")]
                    }],
                    "irVersions": [IR_VERSION],
                    "compile": true
                },
                "backend": {
                    "targets": [target],
                    "irVersions": [IR_VERSION],
                    "generate": true
                }
            }),
            b"#!/bin/sh\nexit 0\n",
        );
        (root, home, snapshot)
    }

    /// Build a provider over a registry assembled by `register`, invoking
    /// through `invoker`.
    fn fixture(
        register: impl Fn(&mut Registry) + Send + Sync + 'static,
        invoker: Arc<dyn ExtensionInvoker>,
    ) -> Fixture {
        fixture_bounded_by(register, invoker, INVOCATION_TIMEOUT)
    }

    /// As [`fixture`], with the invocation bound the caller names.
    fn fixture_bounded_by(
        register: impl Fn(&mut Registry) + Send + Sync + 'static,
        invoker: Arc<dyn ExtensionInvoker>,
        timeout: Duration,
    ) -> Fixture {
        let (home_root, _home) = scratch_home();
        let working = tempfile::tempdir().expect("a scratch working directory");
        let root_path = home_root.path().to_path_buf();
        let provider = NativePlaygroundProvider::with_parts(
            Arc::new(move |_only| {
                let mut registry = Registry::new();
                register(&mut registry);
                Ok(registry)
            }),
            None,
            invoker,
            working.path().to_path_buf(),
            timeout,
        );
        Fixture {
            provider,
            _home_root: home_root,
            working,
            home_root: root_path,
        }
    }

    fn with_frontend(response: CompileResult) -> impl Fn(&mut Registry) + Send + Sync {
        move |registry: &mut Registry| {
            registry
                .register(Arc::new(NativeSource::new(
                    NativeExtension::frontend_only(FixedFrontend {
                        response: response.clone(),
                    })
                    .expect("the frontend double is well formed"),
                )))
                .expect("the frontend double registers");
        }
    }

    fn with_backend(response: GenerateResult) -> impl Fn(&mut Registry) + Send + Sync {
        move |registry: &mut Registry| {
            registry
                .register(Arc::new(NativeSource::new(
                    NativeExtension::backend_only(FixedBackend {
                        response: response.clone(),
                    })
                    .expect("the backend double is well formed"),
                )))
                .expect("the backend double registers");
        }
    }

    #[test]
    fn a_request_naming_two_different_source_roots_is_refused() {
        let mut params = compile_params("elm", "module Main exposing (..)");
        params.options = serde_json::json!({
            "sourceRootUri": "file:///src",
            "sourceRoot": "file:///other"
        });

        let error = compile_request(params).expect_err("two roots are refused");

        assert!(
            format!("{error:?}").contains("different roots"),
            "{error:?}"
        );
    }

    #[test]
    fn matching_source_root_aliases_become_one_root() {
        let mut params = compile_params("elm", "module Main exposing (..)");
        params.options = serde_json::json!({
            "sourceRootUri": "file:///src",
            "sourceRoot": "file:///src"
        });

        let request = serde_json::to_value(compile_request(params).unwrap()).unwrap();

        assert_eq!(request["sources"]["root"], "file:///src");
        assert!(request["options"].get("sourceRoot").is_none());
    }

    fn compile_params(language_id: &str, text: &str) -> PlaygroundCompileParams {
        PlaygroundCompileParams {
            language_id: language_id.to_owned(),
            documents: vec![PlaygroundSourceDocument {
                uri: format!("file:///src/Main.{language_id}"),
                language_id: language_id.to_owned(),
                version: 1,
                text: text.to_owned(),
            }],
            package: PlaygroundPackage {
                name: "playground/main".into(),
                exposed_modules: Some(vec!["Main".into()]),
            },
            ir_version: IR_VERSION.into(),
            options: serde_json::json!({}),
        }
    }

    fn generate_params(target: &str, ir_version: &str) -> PlaygroundGenerateParams {
        PlaygroundGenerateParams {
            ir: serde_json::json!({"formatVersion": 4}),
            ir_version: ir_version.to_owned(),
            target: target.to_owned(),
            options: serde_json::json!({}),
        }
    }

    /// Count the files under `root`, ignoring the Morphir home's lock
    /// directory.
    ///
    /// Reading the installed-extension catalog takes a lock in
    /// `<home>/locks`, exactly as `morphir extension list` does. That is the
    /// catalog's own bookkeeping, not the playground putting a user's work
    /// on disk, and the playground cannot read the catalog without it.
    /// Everything else under every watched root counts.
    fn count_files(root: &Path) -> usize {
        walkdir::WalkDir::new(root)
            .into_iter()
            .filter_map(Result::ok)
            .filter(|entry| entry.file_type().is_file())
            .filter(|entry| {
                !entry
                    .path()
                    .components()
                    .any(|component| component.as_os_str() == "locks")
            })
            .count()
    }

    // ------------------------------------------------------------------ tests

    #[tokio::test]
    async fn compiling_returns_diagnostics_rather_than_failing_the_call() {
        let fixture = fixture(
            with_frontend(CompileResult {
                success: false,
                ir_version: None,
                ir: None,
                diagnostics: vec![Diagnostic {
                    severity: DiagnosticSeverity::Error,
                    code: None,
                    message: "Type mismatch".into(),
                    location: None,
                    related: vec![],
                }],
                modules: vec![],
                module_results: Vec::new(),
                context_digest: None,
            }),
            Arc::new(PooledInvoker::new(crate::commands::extension::host_config())),
        );

        let result = fixture
            .provider
            .compile(compile_params("elm", "module Main exposing (..)"))
            .await
            .expect("a compile with errors is a successful call");

        assert!(!result.success);
        assert_eq!(result.diagnostics.len(), 1);
        assert_eq!(result.diagnostics[0].message, "Type mismatch");
        assert!(result.ir.is_none());
    }

    /// The invariant this module exists for: a generate that really reaches
    /// an extension and really returns an artifact leaves the disk alone.
    ///
    /// Every directory the provider could plausibly write to is watched, not
    /// just one: the working directory it was built with (where a publishing
    /// regression would put artifacts), the process working directory (where
    /// a path built from `current_dir()` would land), and the Morphir home.
    /// Watching only an unrelated scratch directory would make this test
    /// unfalsifiable — it would pass whatever `generate` did.
    #[tokio::test]
    async fn generating_returns_artifacts_and_writes_no_files() {
        let fixture = fixture(
            with_backend(GenerateResult {
                success: true,
                artifacts: vec![Artifact {
                    path: "schema.avsc".into(),
                    content: "{}".into(),
                    binary: false,
                }],
                diagnostics: vec![],
            }),
            Arc::new(PooledInvoker::new(crate::commands::extension::host_config())),
        );
        let cwd = std::env::current_dir().unwrap();
        let watched = [
            fixture.working.path().to_path_buf(),
            fixture.home_root.clone(),
            cwd,
        ];
        let before: Vec<usize> = watched.iter().map(|path| count_files(path)).collect();

        let result = fixture
            .provider
            .generate(generate_params("avro", IR_VERSION))
            .await
            .unwrap();

        assert_eq!(result.artifacts.len(), 1);
        assert_eq!(result.artifacts[0].content, "{}");
        let after: Vec<usize> = watched.iter().map(|path| count_files(path)).collect();
        assert_eq!(
            after, before,
            "the playground must not write files; watched {watched:?}"
        );
    }

    #[tokio::test]
    async fn an_unknown_target_is_reported_without_reaching_an_extension() {
        let fixture = fixture(|_registry| {}, Arc::new(UnreachableInvoker));

        let error = fixture
            .provider
            .generate(generate_params("nonexistent", IR_VERSION))
            .await
            .unwrap_err();

        assert!(
            error.to_string().contains("nonexistent"),
            "unexpected error: {error}"
        );
    }

    #[tokio::test]
    async fn an_incompatible_ir_version_is_refused_before_invoking() {
        let fixture = fixture(
            with_backend(GenerateResult {
                success: true,
                artifacts: vec![],
                diagnostics: vec![],
            }),
            Arc::new(UnreachableInvoker),
        );

        let error = fixture
            .provider
            .generate(generate_params("avro", "3.0.0"))
            .await
            .unwrap_err();

        assert!(
            error.to_string().contains("3.0.0"),
            "unexpected error: {error}"
        );
    }

    #[tokio::test(start_paused = true)]
    async fn a_slow_extension_yields_a_timeout_diagnostic() {
        let slow_invoker: Arc<SleepingInvoker>;
        let fixture = fixture(
            with_frontend(CompileResult {
                success: true,
                ir_version: None,
                ir: None,
                diagnostics: vec![],
                modules: vec![],
                module_results: Vec::new(),
                context_digest: None,
            }),
            {
                let sleeping = Arc::new(SleepingInvoker::new(Duration::from_secs(600)));
                slow_invoker = sleeping.clone();
                sleeping
            },
        );

        let result = fixture
            .provider
            .compile(compile_params("elm", "module Main exposing (..)"))
            .await
            .expect("a timeout is reported as a result, not a transport failure");

        assert!(!result.success);
        assert!(
            result
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.message.contains("timed out")),
            "diagnostics: {:?}",
            result.diagnostics
        );
        // The invoker was told to forget the provider: a session-holding
        // invoker may still be wedged on the hung exchange, and without this
        // every later request for the provider queues behind the same hang.
        assert_eq!(
            *slow_invoker
                .abandoned
                .lock()
                .expect("the log is never poisoned"),
            vec!["example-frontend".to_owned()]
        );
    }

    /// The bound has to hold for a built-in too.
    ///
    /// A built-in is invoked through a synchronous call, so a compile that
    /// never returns never yields either, and a timeout wrapped around a
    /// future that is never polled can never fire. The sleeping invoker above
    /// awaits, which proves only the easy half. This one blocks its thread
    /// outright, which is what a runaway parser does, and it must still come
    /// back as a timeout diagnostic rather than wedging the connection.
    #[tokio::test]
    async fn a_blocking_built_in_extension_still_yields_a_timeout_diagnostic() {
        let gate = Arc::new(Gate::default());
        let registered = Arc::clone(&gate);
        let fixture = fixture_bounded_by(
            move |registry: &mut Registry| {
                registry
                    .register(Arc::new(NativeSource::new(
                        NativeExtension::frontend_only(BlockingFrontend {
                            gate: Arc::clone(&registered),
                        })
                        .expect("the blocking frontend double is well formed"),
                    )))
                    .expect("the blocking frontend double registers");
            },
            Arc::new(PooledInvoker::new(crate::commands::extension::host_config())),
            // Real time, not the paused clock the sleeping-invoker test uses:
            // an outstanding blocking task inhibits tokio's auto-advance, so
            // a paused clock would never reach the deadline.
            Duration::from_millis(50),
        );

        let result = fixture
            .provider
            .compile(compile_params("blocking", "anything"))
            .await
            .expect("a timeout is reported as a result, not a transport failure");
        gate.open();

        assert!(!result.success);
        assert!(
            result
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.message.contains("timed out")),
            "diagnostics: {:?}",
            result.diagnostics
        );
    }

    /// What actually goes over the wire to a frontend.
    #[tokio::test]
    async fn the_outgoing_compile_request_carries_what_the_caller_asked_for() {
        let invoker = Arc::new(RecordingInvoker::default());
        let fixture = fixture(
            with_frontend(CompileResult {
                success: true,
                ir_version: None,
                ir: None,
                diagnostics: vec![],
                modules: vec![],
                module_results: Vec::new(),
                context_digest: None,
            }),
            invoker.clone(),
        );
        let mut params = compile_params("elm", "module Main exposing (..)");
        // `typesOnly` is lifted into its typed field, `irVersion` has to be
        // stripped because `CompileOptions` refuses to serialize a reserved
        // key out of `extra`, and `outputDir` is refused outright.
        params.options = serde_json::json!({
            "typesOnly": true,
            "irVersion": "9",
            "outputDir": "/tmp/somewhere",
            "sourceRootUri": "file:///src",
            "strict": true
        });

        fixture
            .provider
            .compile(params)
            .await
            .expect("the double answers");

        let requests = invoker.compiles.lock().unwrap();
        let sent = serde_json::to_value(&requests[0]).expect("the request serializes");
        assert_eq!(sent["languageId"], "elm");
        assert!(sent.get("documents").is_none());
        assert_eq!(sent["sources"]["root"], "file:///src");
        assert!(sent["options"].get("sourceRootUri").is_none());
        assert_eq!(sent["sources"]["documents"].as_array().unwrap().len(), 1);
        assert_eq!(
            sent["sources"]["documents"][0]["uri"],
            "file:///src/Main.elm"
        );
        assert_eq!(
            sent["sources"]["documents"][0]["text"],
            "module Main exposing (..)"
        );
        assert_eq!(sent["sources"]["documents"][0]["version"], 1);
        assert_eq!(sent["package"]["name"], "playground/main");
        assert_eq!(sent["package"]["exposedModules"][0], "Main");
        assert_eq!(
            sent["dependencies"].as_array().unwrap().len(),
            0,
            "the playground compiles one self-contained package"
        );
        assert_eq!(
            sent["options"]["irVersion"], IR_VERSION,
            "the request's own IR version wins"
        );
        assert_eq!(sent["options"]["typesOnly"], true);
        assert_eq!(sent["options"]["strict"], true);
        assert!(
            sent["options"].get("outputDir").is_none(),
            "the playground has no output directory: {sent}"
        );
        assert_eq!(
            sent["options"]["emitParseStage"], false,
            "a parse stage would be written to disk: {sent}"
        );
    }

    /// What goes over the wire to a backend.
    #[tokio::test]
    async fn the_outgoing_generate_request_carries_the_ir_and_target() {
        let invoker = Arc::new(RecordingInvoker::default());
        let fixture = fixture(
            with_backend(GenerateResult {
                success: true,
                artifacts: vec![],
                diagnostics: vec![],
            }),
            invoker.clone(),
        );
        let mut params = generate_params("avro", IR_VERSION);
        params.options = serde_json::json!({"package": "com.example", "outputDir": "/tmp/nope"});

        fixture
            .provider
            .generate(params)
            .await
            .expect("the double answers");

        let requests = invoker.generates.lock().unwrap();
        let sent = serde_json::to_value(&requests[0]).expect("the request serializes");
        assert_eq!(sent["ir"]["formatVersion"], 4);
        assert_eq!(sent["target"], "avro");
        assert_eq!(sent["options"]["package"], "com.example");
        assert!(
            sent["options"].get("outputDir").is_none(),
            "the playground has no output directory: {sent}"
        );
    }

    /// Built-ins are offered, not filtered out. They are registered in the
    /// same registry as installed providers and invoked the same way, so the
    /// playground has no reason to hide them — and a Playground that could
    /// not compile the one language the CLI ships support for would be
    /// useless on a machine with nothing installed.
    #[tokio::test]
    async fn the_catalog_offers_the_built_in_providers() {
        let (_root, home) = scratch_home();
        let provider = NativePlaygroundProvider::new(home);

        let catalog = provider
            .catalog()
            .await
            .expect("an empty home has a catalog");

        let gleam = catalog
            .frontend("gleam")
            .unwrap_or_else(|| panic!("no built-in Gleam frontend: {catalog:?}"));
        assert_eq!(gleam.provider.origin, PlaygroundProviderOrigin::Builtin);
        assert!(gleam.compile);
        assert_eq!(gleam.file_extensions, [".gleam"]);
        assert_eq!(gleam.provider.invocation_mode, "native-direct");
        assert!(
            catalog.target("gleam").is_some(),
            "no built-in Gleam backend: {catalog:?}"
        );
    }

    /// Ordering is load-bearing, not cosmetic.
    ///
    /// [`Registry::resolve_frontend`] prefers an installed provider
    /// over a built-in offering the same language, and the catalog's lookups
    /// take the first match. If the projection listed built-ins first, the
    /// picker would name Gleam's built-in while a compile ran the installed
    /// extension, and the user would be told the wrong thing about their own
    /// output. The installed provider here shadows the one built-in the CLI
    /// ships, at the same IR release, so the two orderings really disagree.
    #[tokio::test]
    async fn an_installed_provider_shadows_the_built_in_it_replaces() {
        let (_root, home, snapshot) = installed_snapshot("installed-gleam", "gleam", "gleam");
        let registry =
            extension_registry_for(&home, vec![snapshot], None).expect("the registry assembles");
        let resolved = registry
            .resolve_frontend("gleam", IR_VERSION, InvocationPolicy::PreferDirect)
            .expect("the registry resolves Gleam");
        assert_eq!(
            resolved.info().id,
            "installed-gleam",
            "this test is only meaningful while the registry prefers the installed provider"
        );

        let catalog = project_catalog(&registry);

        let frontend = catalog
            .frontend("gleam")
            .unwrap_or_else(|| panic!("no Gleam frontend: {catalog:?}"));
        assert_eq!(
            frontend.provider.extension_id,
            resolved.info().id,
            "the catalog names a provider the compile would not use: {catalog:?}"
        );
        assert_eq!(
            frontend.provider.origin,
            PlaygroundProviderOrigin::Installed
        );
        let target = catalog
            .target("gleam")
            .unwrap_or_else(|| panic!("no Gleam target: {catalog:?}"));
        assert_eq!(
            target.provider.origin,
            PlaygroundProviderOrigin::Installed,
            "the catalog names a provider the generate would not use: {catalog:?}"
        );
        assert!(
            catalog
                .frontends
                .iter()
                .any(|entry| entry.provider.origin == PlaygroundProviderOrigin::Builtin),
            "shadowed built-ins stay listed, they just come second: {catalog:?}"
        );
    }

    /// The end of the built-in question: Gleam is not just listed, it runs,
    /// and running it leaves nothing behind.
    ///
    /// The Gleam frontend writes a parse-stage tree into `outputDir` unless
    /// told not to, and `outputDir` defaults to the process working
    /// directory — so this is the test that would catch the playground
    /// forwarding options it should have stripped.
    /// A workspace whose `morphir.toml` names a provider, so the playground
    /// has something to read.
    fn workspace_naming(extension: &str) -> tempfile::TempDir {
        let workspace = tempfile::tempdir().expect("a scratch workspace");
        std::fs::write(
            workspace.path().join("morphir.toml"),
            format!(
                "[project]\n\
                 name = \"example/domain\"\n\
                 version = \"1.0.0\"\n\
                 source_directory = \"src\"\n\
                 \n\
                 [frontend]\n\
                 language = \"elm\"\n\
                 \n\
                 [frontend.elm]\n\
                 extension = \"{extension}\"\n"
            ),
        )
        .expect("the configuration is written");
        workspace
    }

    const ELM_MODULE: &str = "module Main exposing (Currency)\n\n\ntype Currency\n    = Currency\n";

    /// The params an Elm playground compile sends. The native Elm binding
    /// advertises the bare IR releases, not the triplet the Gleam fixtures use.
    fn elm_compile_params() -> PlaygroundCompileParams {
        PlaygroundCompileParams {
            ir_version: "4".into(),
            ..compile_params("elm", ELM_MODULE)
        }
    }

    /// The message a `CliError` carries, including the source a `Config`
    /// error keeps its detail in.
    fn full_message(failure: &CliError) -> String {
        match failure {
            CliError::Config { error } => error.to_string(),
            other => other.to_string(),
        }
    }

    /// Requirement: the playground honours `[frontend.<language>] extension`.
    /// The native Elm provider is opt-in, so it is registered only when
    /// something asks for it by id. On the command line that is `--extension`;
    /// here it is the project's own configuration, and without it a browser
    /// compile would silently use a different provider from the one
    /// `morphir compile` uses in the same directory.
    #[tokio::test]
    async fn a_configured_provider_is_used_for_a_playground_compile() {
        let (_root, home) = scratch_home();
        let workspace = workspace_naming("morphir-elm-native");
        let provider = NativePlaygroundProvider::in_workspace(home, workspace.path());

        let result = provider
            .compile(elm_compile_params())
            .await
            .expect("the configured provider compiles Elm");

        assert!(result.success, "{result:?}");
        assert!(result.ir.is_some(), "{result:?}");
    }

    /// The control for the test above: with no key, Elm resolves against an
    /// unrestricted registry, where the opt-in native provider is absent and
    /// nothing is installed in this home.
    #[tokio::test]
    async fn without_the_key_the_playground_does_not_reach_the_opt_in_provider() {
        let (_root, home) = scratch_home();
        let workspace = tempfile::tempdir().expect("a scratch workspace");
        let provider = NativePlaygroundProvider::in_workspace(home, workspace.path());

        let failure = provider
            .compile(elm_compile_params())
            .await
            .expect_err("an empty home compiles no Elm");

        assert!(
            failure.to_string().contains("No extension compiles"),
            "{failure}"
        );
    }

    /// A configured id that provides some other language fails the same way it
    /// does on the command line, naming the id and the language.
    #[tokio::test]
    async fn a_configured_provider_that_does_not_provide_the_language_is_refused() {
        let (_root, home) = scratch_home();
        let workspace = workspace_naming("morphir-gleam-binding");
        let provider = NativePlaygroundProvider::in_workspace(home, workspace.path());

        let failure = provider
            .compile(elm_compile_params())
            .await
            .expect_err("a Gleam provider compiles no Elm");

        let message = failure.to_string();
        assert!(message.contains("morphir-gleam-binding"), "{message}");
        assert!(
            message.contains("does not provide language 'elm'"),
            "{message}"
        );
    }

    /// A malformed key fails the compile that reads it, naming the key, rather
    /// than being dropped because the playground has no flag to blame.
    #[tokio::test]
    async fn a_malformed_key_fails_a_playground_compile() {
        let (_root, home) = scratch_home();
        let workspace = workspace_naming("   ");
        let provider = NativePlaygroundProvider::in_workspace(home, workspace.path());

        let failure = provider
            .compile(elm_compile_params())
            .await
            .expect_err("a blank provider id is refused");

        assert!(
            full_message(&failure).contains("frontend.elm.extension"),
            "{failure}"
        );
    }

    /// The key is a frontend key for one language, so it never restricts the
    /// catalog, which is the list of everything this session can reach.
    #[tokio::test]
    async fn a_configured_provider_does_not_shrink_the_catalog() {
        let (_root, home) = scratch_home();
        let workspace = workspace_naming("morphir-elm-native");
        let provider = NativePlaygroundProvider::in_workspace(home, workspace.path());

        let catalog = provider.catalog().await.expect("a catalog is projected");

        assert!(
            catalog.frontend("gleam").is_some(),
            "another language's provider is still offered: {catalog:?}"
        );
    }

    #[tokio::test]
    async fn builtin_gleam_compiles_and_generates_without_writing_files() {
        let (root, home) = scratch_home();
        let working = tempfile::tempdir().expect("a scratch working directory");
        let cwd = std::env::current_dir().unwrap();
        let provider = NativePlaygroundProvider::with_parts(
            Arc::new(move |only| installed_registry(&home, only)),
            None,
            Arc::new(PooledInvoker::new(crate::commands::extension::host_config())),
            working.path().to_path_buf(),
            INVOCATION_TIMEOUT,
        );
        let watched = [
            working.path().to_path_buf(),
            root.path().to_path_buf(),
            cwd.clone(),
        ];
        let before: Vec<usize> = watched.iter().map(|path| count_files(path)).collect();

        let mut params = compile_params("gleam", "pub fn hello() {\n  \"world\"\n}\n");
        // Gleam module names are snake_case, unlike the Elm-shaped default.
        params.documents[0].uri = "file:///src/hello.gleam".into();
        params.package.name = "example/hello".into();
        params.package.exposed_modules = Some(vec![]);
        let compiled = provider
            .compile(params)
            .await
            .expect("the built-in Gleam frontend is reachable");
        assert!(
            compiled.success,
            "built-in Gleam compile failed: {:?}",
            compiled.diagnostics
        );
        let ir = compiled.ir.expect("a successful compile carries IR");

        let generated = provider
            .generate(PlaygroundGenerateParams {
                ir,
                ir_version: IR_VERSION.into(),
                target: "gleam".into(),
                options: serde_json::json!({}),
            })
            .await
            .expect("the built-in Gleam backend is reachable");
        assert!(
            generated.success,
            "built-in Gleam generate failed: {:?}",
            generated.diagnostics
        );
        assert!(
            !generated.artifacts.is_empty(),
            "artifacts come back in the response"
        );

        let after: Vec<usize> = watched.iter().map(|path| count_files(path)).collect();
        assert_eq!(
            after, before,
            "the playground must not write files; watched {watched:?}"
        );
    }

    /// An installed provider's capability metadata is rebuilt from what the
    /// install persisted, and the persisted record has no room for
    /// `incremental` or `fragments`. Reporting them as `false` would tell the
    /// picker the extension refuses those capabilities when the truth is that
    /// nobody asked; they go over the wire as `null`.
    #[tokio::test]
    async fn capabilities_the_catalog_cannot_know_are_reported_as_unknown() {
        let (_root, home, snapshot) =
            installed_snapshot("installed-elm", "elm", "installed-target");
        let registry =
            extension_registry_for(&home, vec![snapshot], None).expect("the registry assembles");

        let catalog = project_catalog(&registry);

        let installed = serde_json::to_value(
            catalog
                .frontend("elm")
                .unwrap_or_else(|| panic!("no installed Elm frontend: {catalog:?}")),
        )
        .expect("the catalog entry serializes");
        assert!(
            installed.get("incremental").is_some(),
            "the key stays present so the client can decode it as nullable: {installed}"
        );
        assert!(
            installed["incremental"].is_null(),
            "an unpersisted capability is unknown, not denied: {installed}"
        );
        assert!(
            installed["fragments"].is_null(),
            "an unpersisted capability is unknown, not denied: {installed}"
        );

        let builtin = serde_json::to_value(
            catalog
                .frontend("gleam")
                .unwrap_or_else(|| panic!("no built-in Gleam frontend: {catalog:?}")),
        )
        .expect("the catalog entry serializes");
        assert_eq!(
            builtin["incremental"],
            serde_json::json!(true),
            "a built-in reports its own complete capability metadata: {builtin}"
        );
        assert_eq!(
            builtin["fragments"],
            serde_json::json!(false),
            "a built-in reports its own complete capability metadata: {builtin}"
        );
    }

    #[tokio::test]
    async fn the_manifest_advertises_the_playground_methods() {
        let fixture = fixture(|_registry| {}, Arc::new(UnreachableInvoker));

        let manifest = fixture.provider.manifest();

        assert_eq!(manifest.id, "playground");
        let names: Vec<&str> = manifest
            .capabilities
            .iter()
            .map(|capability| capability.name.as_str())
            .collect();
        assert_eq!(
            names,
            [
                "morphir/playground/catalog",
                "morphir/playground/compile",
                "morphir/playground/generate"
            ]
        );
    }
}

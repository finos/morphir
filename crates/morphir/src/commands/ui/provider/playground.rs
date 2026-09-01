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
//! [`ExtensionRegistry`] `morphir compile` and `morphir generate` build, and
//! asks it to resolve a language or a target, so the playground offers
//! exactly what the rest of the CLI offers — built-ins included — and cannot
//! drift onto a private notion of which provider serves what.

use std::collections::HashMap;
use std::future::Future;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use morphir_daemon::ExtensionRegistry;
use morphir_daemon::extensions::{
    CapabilityMetadataScope, InvocationMode, InvocationPolicy, ProviderMetadata, ProviderOrigin,
    ResolvedBackend, ResolvedFrontend,
};
use morphir_distribution::list_installed;
use morphir_extension_sdk::{
    Artifact, CompileOptions, CompilePackage, CompileRequest, CompileResult, Diagnostic,
    DiagnosticSeverity, GenerateRequest, GenerateResult, SourceDocument, SourceLocation,
};
use serde_json::Value;

use crate::commands::ui::protocol::{
    PlaygroundArtifact, PlaygroundCatalog, PlaygroundCompileParams, PlaygroundCompileResult,
    PlaygroundDiagnostic, PlaygroundFrontend, PlaygroundGenerateParams, PlaygroundGenerateResult,
    PlaygroundLocation, PlaygroundPosition, PlaygroundProviderOrigin, PlaygroundProviderRef,
    PlaygroundRange, PlaygroundTarget, ProviderKind, ProviderManifest, ProviderStatus,
};
use crate::error::CliError;
use crate::extensions::extension_registry;
use crate::home::MorphirHome;

use super::PlaygroundCapability;
use super::native::capability;

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
/// Injectable so a test can register its own providers without installing an
/// extension into a Morphir home.
type RegistrySource = Arc<dyn Fn() -> Result<ExtensionRegistry, CliError> + Send + Sync>;

/// How the playground reaches a resolved provider.
///
/// Production is [`RegistryInvoker`], which delegates to the CLI's own
/// extension boundary — the same functions `morphir compile` and `morphir
/// generate` call — so the playground cannot acquire a private invocation
/// path. Injectable so a test can drive an invocation that never answers and
/// observe the timeout without waiting two real minutes.
#[async_trait]
trait ExtensionInvoker: Send + Sync {
    async fn compile(
        &self,
        home: &MorphirHome,
        working_directory: &Path,
        resolved: &ResolvedFrontend,
        request: CompileRequest,
    ) -> Result<CompileResult, CliError>;

    async fn generate(
        &self,
        home: &MorphirHome,
        working_directory: &Path,
        resolved: &ResolvedBackend,
        request: GenerateRequest,
    ) -> Result<GenerateResult, CliError>;
}

struct RegistryInvoker;

#[async_trait]
impl ExtensionInvoker for RegistryInvoker {
    async fn compile(
        &self,
        home: &MorphirHome,
        working_directory: &Path,
        resolved: &ResolvedFrontend,
        request: CompileRequest,
    ) -> Result<CompileResult, CliError> {
        crate::extensions::invoke_frontend(home, working_directory, resolved, request).await
    }

    async fn generate(
        &self,
        home: &MorphirHome,
        working_directory: &Path,
        resolved: &ResolvedBackend,
        request: GenerateRequest,
    ) -> Result<GenerateResult, CliError> {
        crate::extensions::invoke_backend(home, working_directory, resolved, request).await
    }
}

/// Either the extension answered, or it outlasted the playground's patience.
enum Invocation<R> {
    Answered(R),
    TimedOut,
}

pub struct NativePlaygroundProvider {
    home: MorphirHome,
    registry: RegistrySource,
    invoker: Arc<dyn ExtensionInvoker>,
    /// Where an installed extension process runs. See
    /// [`extension_working_directory`]: the playground never writes here, it
    /// is only the directory a child process is started in.
    working_directory: PathBuf,
}

impl NativePlaygroundProvider {
    /// Build a provider that offers the built-in providers plus whatever is
    /// installed in `home`.
    pub fn new(home: MorphirHome) -> Self {
        let registry_home = home.clone();
        let working_directory = extension_working_directory(&home);
        Self::with_parts(
            home,
            Arc::new(move || installed_registry(&registry_home)),
            Arc::new(RegistryInvoker),
            working_directory,
        )
    }

    fn with_parts(
        home: MorphirHome,
        registry: RegistrySource,
        invoker: Arc<dyn ExtensionInvoker>,
        working_directory: PathBuf,
    ) -> Self {
        Self {
            home,
            registry,
            invoker,
            working_directory,
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

    async fn catalog(&self) -> Result<PlaygroundCatalog, CliError> {
        Ok(project_catalog(&(self.registry)()?))
    }

    async fn compile(
        &self,
        params: PlaygroundCompileParams,
    ) -> Result<PlaygroundCompileResult, CliError> {
        let registry = (self.registry)()?;
        // The registry checks the language, the compile flag, and the IR
        // version together, and reports which providers were considered, so
        // there is nothing left for this layer to re-check.
        let resolved = registry
            .resolve_frontend(
                &params.language_id,
                &params.ir_version,
                InvocationPolicy::PreferDirect,
            )
            .map_err(|error| CliError::Validation {
                message: format!(
                    "No extension compiles language '{}' at Morphir IR version '{}': {error}",
                    params.language_id, params.ir_version
                ),
            })?;
        let provider_id = resolved.info().id.clone();
        let request = compile_request(params);
        let invocation =
            self.invoker
                .compile(&self.home, &self.working_directory, &resolved, request);
        match bounded(invocation).await? {
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
            Invocation::TimedOut => Ok(PlaygroundCompileResult {
                success: false,
                ir_version: None,
                ir: None,
                diagnostics: vec![timeout_diagnostic(&provider_id)],
                modules: Vec::new(),
            }),
        }
    }

    async fn generate(
        &self,
        params: PlaygroundGenerateParams,
    ) -> Result<PlaygroundGenerateResult, CliError> {
        let registry = (self.registry)()?;
        let resolved = registry
            .resolve_backend(
                &params.target,
                &params.ir_version,
                InvocationPolicy::PreferDirect,
            )
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
        let invocation =
            self.invoker
                .generate(&self.home, &self.working_directory, &resolved, request);
        match bounded(invocation).await? {
            Invocation::Answered(result) => Ok(PlaygroundGenerateResult {
                success: result.success,
                artifacts: result.artifacts.iter().map(playground_artifact).collect(),
                diagnostics: result
                    .diagnostics
                    .iter()
                    .map(playground_diagnostic)
                    .collect(),
            }),
            Invocation::TimedOut => Ok(PlaygroundGenerateResult {
                success: false,
                artifacts: Vec::new(),
                diagnostics: vec![timeout_diagnostic(&provider_id)],
            }),
        }
    }
}

/// Bound one invocation by [`INVOCATION_TIMEOUT`].
///
/// A lapsed bound is `Ok(TimedOut)`, not an error: the caller turns it into a
/// diagnostic on an otherwise well-formed result, because "the compiler gave
/// up" is something the editor shows in its problems list, not a broken
/// connection.
async fn bounded<R>(
    invocation: impl Future<Output = Result<R, CliError>>,
) -> Result<Invocation<R>, CliError> {
    match tokio::time::timeout(INVOCATION_TIMEOUT, invocation).await {
        Ok(answered) => answered.map(Invocation::Answered),
        Err(_elapsed) => Ok(Invocation::TimedOut),
    }
}

fn installed_registry(home: &MorphirHome) -> Result<ExtensionRegistry, CliError> {
    let installed = list_installed(home).map_err(|error| CliError::Extension {
        message: format!("Failed to list installed extensions: {error}"),
    })?;
    extension_registry(installed)
}

/// Project the registry's provider metadata into the browser-facing catalog.
///
/// Built-ins are listed alongside installed providers, because the registry
/// resolves and invokes both the same way. They are listed *after* them:
/// [`ExtensionRegistry::resolve_frontend`] prefers an installed provider when
/// two offer the same language, and the catalog's first-match-wins lookups
/// have to agree with that or the picker would name a provider the compile
/// would not use.
fn project_catalog(registry: &ExtensionRegistry) -> PlaygroundCatalog {
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
        CapabilityMetadataScope::PersistedFrontendBackend => false,
    }
}

fn provider_ref(provider: &ProviderMetadata) -> PlaygroundProviderRef {
    PlaygroundProviderRef {
        extension_id: provider.info().id.clone(),
        extension_name: provider.info().name.clone(),
        version: provider.info().version.clone(),
        origin: match provider.origin() {
            ProviderOrigin::Builtin => PlaygroundProviderOrigin::Builtin,
            ProviderOrigin::Installed => PlaygroundProviderOrigin::Installed,
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
fn compile_request(params: PlaygroundCompileParams) -> CompileRequest {
    CompileRequest {
        language_id: params.language_id,
        documents: params
            .documents
            .into_iter()
            .map(|document| SourceDocument {
                uri: document.uri,
                language_id: document.language_id,
                version: document.version,
                text: document.text,
            })
            .collect(),
        package: CompilePackage {
            name: params.package.name,
            exposed_modules: params.package.exposed_modules,
        },
        dependencies: Vec::new(),
        options: compile_options(params.ir_version, &params.options),
    }
}

/// Fold free-form playground options into typed compile options.
///
/// `typesOnly` is lifted into its typed field, and `irVersion` is dropped
/// because the request's own `irVersion` is authoritative; both are reserved
/// keys that `CompileOptions` refuses to serialize from `extra`.
fn compile_options(ir_version: String, options: &Value) -> CompileOptions {
    let mut extra = option_map(options);
    let types_only = extra
        .remove("typesOnly")
        .and_then(|value| value.as_bool())
        .unwrap_or(false);
    extra.remove("irVersion");
    deny_output_options(&mut extra);
    CompileOptions {
        types_only,
        ir_version,
        extra,
    }
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

fn timeout_diagnostic(extension_id: &str) -> PlaygroundDiagnostic {
    PlaygroundDiagnostic {
        severity: "error".into(),
        code: None,
        message: format!(
            "Extension '{extension_id}' timed out after {}s",
            INVOCATION_TIMEOUT.as_secs()
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
    use morphir_distribution::{
        Channel, ExtensionId, ExtensionInstaller, InstalledExtensionSnapshot, LocalIndex, Platform,
        Selection, Sha256Digest,
    };
    use morphir_extension_sdk::{
        Backend, BackendCapability, Extension, ExtensionCapabilities, ExtensionInfo, Frontend,
        FrontendCapability, LanguageCapability, NativeExtension,
    };
    use std::sync::Mutex;

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
            home: &MorphirHome,
            working_directory: &Path,
            resolved: &ResolvedFrontend,
            request: CompileRequest,
        ) -> Result<CompileResult, CliError> {
            self.compiles
                .lock()
                .expect("the log is never poisoned")
                .push(request.clone());
            RegistryInvoker
                .compile(home, working_directory, resolved, request)
                .await
        }

        async fn generate(
            &self,
            home: &MorphirHome,
            working_directory: &Path,
            resolved: &ResolvedBackend,
            request: GenerateRequest,
        ) -> Result<GenerateResult, CliError> {
            self.generates
                .lock()
                .expect("the log is never poisoned")
                .push(request.clone());
            RegistryInvoker
                .generate(home, working_directory, resolved, request)
                .await
        }
    }

    /// An invoker that never answers within the caller's patience.
    struct SleepingInvoker {
        delay: Duration,
    }

    #[async_trait]
    impl ExtensionInvoker for SleepingInvoker {
        async fn compile(
            &self,
            _home: &MorphirHome,
            _working_directory: &Path,
            _resolved: &ResolvedFrontend,
            _request: CompileRequest,
        ) -> Result<CompileResult, CliError> {
            tokio::time::sleep(self.delay).await;
            unreachable!("the playground gives up before this invoker answers")
        }

        async fn generate(
            &self,
            _home: &MorphirHome,
            _working_directory: &Path,
            _resolved: &ResolvedBackend,
            _request: GenerateRequest,
        ) -> Result<GenerateResult, CliError> {
            tokio::time::sleep(self.delay).await;
            unreachable!("the playground gives up before this invoker answers")
        }
    }

    /// An invoker that fails loudly: tests using it must answer before any
    /// extension is reached.
    struct UnreachableInvoker;

    #[async_trait]
    impl ExtensionInvoker for UnreachableInvoker {
        async fn compile(
            &self,
            _home: &MorphirHome,
            _working_directory: &Path,
            resolved: &ResolvedFrontend,
            _request: CompileRequest,
        ) -> Result<CompileResult, CliError> {
            panic!("invoked frontend '{}' unexpectedly", resolved.info().id)
        }

        async fn generate(
            &self,
            _home: &MorphirHome,
            _working_directory: &Path,
            resolved: &ResolvedBackend,
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

    /// Install a real extension into a scratch Morphir home and return its
    /// snapshot.
    ///
    /// Registering a fabricated snapshot would not answer the question these
    /// tests ask: an installed provider's capability metadata is rebuilt from
    /// what the install actually persisted, so the snapshot has to come from
    /// a real index and a real install. This mirrors the `installed` helper in
    /// morphir-daemon's `provider_registry` integration test.
    ///
    /// The returned directory owns the home the snapshot points into and must
    /// outlive it.
    fn installed_snapshot(
        extension_id: &str,
        language: &str,
        target: &str,
    ) -> (tempfile::TempDir, InstalledExtensionSnapshot) {
        let root = tempfile::tempdir().expect("a temporary install root");
        let index = root.path().join("index");
        let artifact = index.join("artifacts").join(extension_id);
        std::fs::create_dir_all(artifact.parent().expect("the artifact has a parent"))
            .expect("the artifact directory is created");
        std::fs::create_dir_all(index.join("extensions")).expect("the index directory is created");
        let bytes = b"#!/bin/sh\nexit 0\n".as_slice();
        std::fs::write(&artifact, bytes).expect("the artifact is written");
        let platform = Platform::current();
        let record = serde_json::json!({
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
            },
            "artifacts": [{
                "runtime": "process",
                "platform": {"os": platform.os(), "arch": platform.arch()},
                "source": {"kind": "local-file", "path": format!("artifacts/{extension_id}")},
                "sha256": Sha256Digest::of_bytes(bytes),
                "filename": extension_id,
                "args": [],
                "executable": true
            }]
        });
        std::fs::write(
            index
                .join("extensions")
                .join(format!("{extension_id}.jsonl")),
            format!("{record}\n"),
        )
        .expect("the index record is written");

        let home = MorphirHome::resolve_from(Some(root.path().join("home").as_os_str()), None)
            .expect("an explicit Morphir home resolves");
        let id = ExtensionId::parse(extension_id).expect("the extension ID parses");
        let selected = LocalIndex::open(&index)
            .expect("the local index opens")
            .resolve(&id, Selection::Channel(Channel::Stable), &platform)
            .expect("the index resolves the extension");
        ExtensionInstaller::new(&home)
            .install(selected)
            .expect("the extension installs");
        let snapshot = list_installed(&home)
            .expect("the installed catalog is readable")
            .pop()
            .expect("exactly one extension was installed");
        (root, snapshot)
    }

    /// Build a provider over a registry assembled by `register`, invoking
    /// through `invoker`.
    fn fixture(
        register: impl Fn(&mut ExtensionRegistry) + Send + Sync + 'static,
        invoker: Arc<dyn ExtensionInvoker>,
    ) -> Fixture {
        let (home_root, home) = scratch_home();
        let working = tempfile::tempdir().expect("a scratch working directory");
        let root_path = home_root.path().to_path_buf();
        let provider = NativePlaygroundProvider::with_parts(
            home,
            Arc::new(move || {
                let mut registry = ExtensionRegistry::new();
                register(&mut registry);
                Ok(registry)
            }),
            invoker,
            working.path().to_path_buf(),
        );
        Fixture {
            provider,
            _home_root: home_root,
            working,
            home_root: root_path,
        }
    }

    fn with_frontend(response: CompileResult) -> impl Fn(&mut ExtensionRegistry) + Send + Sync {
        move |registry: &mut ExtensionRegistry| {
            registry
                .register_builtin(
                    NativeExtension::frontend_only(FixedFrontend {
                        response: response.clone(),
                    })
                    .expect("the frontend double is well formed"),
                )
                .expect("the frontend double registers");
        }
    }

    fn with_backend(response: GenerateResult) -> impl Fn(&mut ExtensionRegistry) + Send + Sync {
        move |registry: &mut ExtensionRegistry| {
            registry
                .register_builtin(
                    NativeExtension::backend_only(FixedBackend {
                        response: response.clone(),
                    })
                    .expect("the backend double is well formed"),
                )
                .expect("the backend double registers");
        }
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
                exposed_modules: vec!["Main".into()],
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
            }),
            Arc::new(RegistryInvoker),
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
            Arc::new(RegistryInvoker),
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
        let fixture = fixture(
            with_frontend(CompileResult {
                success: true,
                ir_version: None,
                ir: None,
                diagnostics: vec![],
                modules: vec![],
            }),
            Arc::new(SleepingInvoker {
                delay: Duration::from_secs(600),
            }),
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
        assert_eq!(sent["documents"].as_array().unwrap().len(), 1);
        assert_eq!(sent["documents"][0]["uri"], "file:///src/Main.elm");
        assert_eq!(sent["documents"][0]["text"], "module Main exposing (..)");
        assert_eq!(sent["documents"][0]["version"], 1);
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

    /// The end of the built-in question: Gleam is not just listed, it runs,
    /// and running it leaves nothing behind.
    ///
    /// The Gleam frontend writes a parse-stage tree into `outputDir` unless
    /// told not to, and `outputDir` defaults to the process working
    /// directory — so this is the test that would catch the playground
    /// forwarding options it should have stripped.
    #[tokio::test]
    async fn builtin_gleam_compiles_and_generates_without_writing_files() {
        let (root, home) = scratch_home();
        let working = tempfile::tempdir().expect("a scratch working directory");
        let cwd = std::env::current_dir().unwrap();
        let provider = NativePlaygroundProvider::with_parts(
            home.clone(),
            Arc::new(move || installed_registry(&home)),
            Arc::new(RegistryInvoker),
            working.path().to_path_buf(),
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
        params.package.exposed_modules = vec![];
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
        let (_root, snapshot) = installed_snapshot("installed-elm", "elm", "installed-target");
        let registry = extension_registry(vec![snapshot]).expect("the registry assembles");

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
            serde_json::json!(false),
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

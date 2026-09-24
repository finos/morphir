//! The one compile route.
//!
//! Every compile entry point — `morphir compile`, `morphir gleam compile` and
//! the compile half of `morphir gleam roundtrip` — produces the same
//! [`PreparedCompile`] through [`prepare_compile`], and [`execute_compile`]
//! runs it. What varies is where the project came from, never which code path
//! compiles it:
//!
//! - **a project**: no `--input`, or a directory `--input` that replaces the
//!   project's source directory. Identity and exposure come from the manifest,
//!   which is found by walking up from the current directory when `--config`
//!   does not name one.
//! - **an explicit selection**: one or more file `--input`s. Only the selected
//!   files are compiled and every module they define is exposed. Identity
//!   comes from a manifest only when `--config` or `--project` loads one, and
//!   otherwise the provider synthesizes it. An ambient manifest is never read.
//!
//! The CLI knows nothing about any language here. The language comes from
//! `--language`, the configuration, or the suffix a provider declares; the
//! module names, package identity and legal names of a selection come from the
//! provider's workspace discovery; and every restriction — IR versions, how
//! many documents one request may carry, whether a provider can synthesize at
//! all — comes from what the provider declares, and a refusal names it.

use super::cache;
use super::elm_modes;
use super::elm_prelude;
use super::frontend_extension;
use super::version::{VersionedIr, selected_ir_version};
use super::{
    CompileOptions, advertised_ir_version, cache_key, cache_write_is_warranted,
    compilation_failure_message, config_warnings, file_uri, prepend_config_warnings,
    provider_supports_incremental, store_compile_results, write_compile_output,
};
use crate::commands::ir_storage::IrStorage;
use crate::commands::out_context::{OutContext, PreparedTask, report_config_warnings};
use crate::error::{CliError, convert_extension_diagnostics};
use crate::home::MorphirHome;
use morphir_common::config::model::MorphirConfig;
use morphir_common::ir_transport::IrVersion;
use morphir_daemon::extensions::{ProcessLaunch, ResolvedFrontend, protocol::methods};
use morphir_devkit::{
    CapturedSelection, ConfigContext, DEFAULT_SOURCE_BYTES, SourceSelectionOptions, TaskId,
    TaskResult, capture_source_selection, discover_config, ensure_morphir_structure,
};
use morphir_distribution::{ExtensionId, InstalledExtensionSnapshot};
use morphir_extension_sdk::{
    CompileOptions as ExtensionCompileOptions, CompilePackage, CompileRequest, CompileResult,
    DiagnosticSeverity, ExtensionType, FrontendCapability, SourceDocument, SourceSet,
};
use morphir_workspace::{DiscoveryResponse, ProjectState};
use std::collections::HashMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// The task-record key that marks a compile of an explicit selection.
///
/// A selection's IR need not match the project's declared exposure, so an
/// implicit `generate` must not consume it believing it is the project.
pub const COMPILE_SCOPE_KEY: &str = "compileScope";

/// A compile with everything settled: configuration, provider, sources and
/// the request itself. Only [`execute_compile`] consumes one.
pub struct PreparedCompile {
    start_dir: PathBuf,
    format: crate::output::OutputFormat,
    install: Option<String>,
    task: TaskId,
    dest: PreparedTask,
    out_module: PathBuf,
    out_root: PathBuf,
    home: MorphirHome,
    workspace: PathBuf,
    provider: Provider,
    request: CompileRequest,
    ir_version: IrVersion,
    storage: IrStorage,
    cache: Option<(cache::CompileCache, cache::CacheKey)>,
    warnings: Vec<String>,
    language: String,
    selection: Option<Vec<String>>,
}

impl std::fmt::Debug for PreparedCompile {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PreparedCompile")
            .field("language", &self.language)
            .field("provider", &self.provider.id())
            .field("ir_version", &self.ir_version)
            .field("selection", &self.selection)
            .finish_non_exhaustive()
    }
}

/// Whether `inputs` select files, which makes the run an explicit selection
/// rather than a project compile. An input that does not exist counts as a
/// file, so capturing it reports it by name.
fn selects_files(inputs: &[String], start_dir: &Path) -> bool {
    !inputs.is_empty()
        && inputs
            .iter()
            .all(|input| !super::absolute_from(start_dir, Path::new(input)).is_dir())
}

/// The provider a compile runs, with what it declares.
enum Provider {
    /// A built-in or installed provider the registry resolved.
    Registered(ResolvedFrontend),
    /// A process `[extensions.<id>] command` configures, which declared its
    /// capabilities when a session was negotiated with it.
    Configured(Box<ConfiguredProvider>),
}

/// What a configured process provider declared about itself.
struct ConfiguredProvider {
    id: String,
    launch: ProcessLaunch,
    frontend: FrontendCapability,
    workspace: bool,
}

impl Provider {
    fn id(&self) -> &str {
        match self {
            Self::Registered(resolved) => resolved.info().id.as_str(),
            Self::Configured(configured) => &configured.id,
        }
    }

    fn capability(&self) -> &FrontendCapability {
        match self {
            Self::Registered(resolved) => resolved.capability(),
            Self::Configured(configured) => &configured.frontend,
        }
    }

    fn supports_workspace_discovery(&self) -> bool {
        match self {
            Self::Registered(resolved) => resolved.supports_workspace_discovery(),
            Self::Configured(configured) => configured.workspace,
        }
    }

    async fn discover(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        request: morphir_workspace::DiscoveryRequest,
    ) -> Result<DiscoveryResponse, CliError> {
        match self {
            Self::Registered(resolved) => {
                crate::extensions::invoke_workspace_discovery(home, workspace, resolved, request)
                    .await
            }
            Self::Configured(configured) => {
                crate::extensions::invoke_process(
                    configured.launch.clone(),
                    &configured.id,
                    methods::WORKSPACE_DISCOVER,
                    request,
                )
                .await
            }
        }
    }

    async fn compile(
        &self,
        home: &MorphirHome,
        workspace: &Path,
        request: CompileRequest,
    ) -> Result<CompileResult, CliError> {
        match self {
            Self::Registered(resolved) => {
                crate::extensions::invoke_frontend(home, workspace, resolved, request).await
            }
            Self::Configured(configured) => {
                crate::extensions::invoke_process(
                    configured.launch.clone(),
                    &configured.id,
                    methods::COMPILE,
                    &request,
                )
                .await
            }
        }
    }
}

/// Settle everything a compile needs, in the order failures must surface.
///
/// The task's previous record is tombstoned as soon as the run knows where
/// its output goes, before any source is read or any provider is asked: a
/// run that fails after that point must never leave the previous success on
/// disk for `generate` to consume.
pub async fn prepare_compile(
    options: CompileOptions,
    roundtrip: bool,
) -> Result<PreparedCompile, CliError> {
    let start_dir = std::env::current_dir().map_err(|error| CliError::FileSystem { error })?;
    let selection = selects_files(&options.input, &start_dir);
    let config = load_configuration(&options, selection, &start_dir)?;
    if roundtrip && selection && config.is_none() {
        return Err(CliError::Validation {
            message: "morphir gleam roundtrip needs a project: its generate half reads the \
                      project's configuration, which a standalone source selection does not \
                      have. Pass --config or --project, or run compile and generate separately"
                .into(),
        });
    }
    if let Some(context) = config.as_ref() {
        report_config_warnings(context);
    }
    if !selection {
        let context = config
            .as_ref()
            .expect("a project compile loads configuration");
        ensure_morphir_structure(&context.morphir_dir)
            .map_err(|error| CliError::Config { error })?;
    }
    let out = OutContext::resolve(config.as_ref(), &options.out, &start_dir);
    let task = TaskId::compile();
    let dest = out.prepare_dest(&task)?;

    let frontend = config
        .as_ref()
        .and_then(|context| context.config.frontend.as_ref());
    let flag_extension = match options.extension.as_deref().map(str::trim) {
        Some("") => {
            return Err(CliError::Validation {
                message: "--extension was given an empty value; pass an extension id such as `morphir-elm-native` or omit the flag".into(),
            });
        }
        Some(id) => {
            ExtensionId::parse(id).map_err(|error| CliError::Extension {
                message: format!("Invalid extension id: {error}"),
            })?;
            Some(id)
        }
        None => None,
    };
    let home = MorphirHome::resolve().map_err(|error| CliError::Config { error })?;
    let installed =
        morphir_distribution::list_installed(&home).map_err(|error| CliError::Extension {
            message: format!("Failed to list installed frontend providers: {error}"),
        })?;
    let workspace = config
        .as_ref()
        .and_then(|context| {
            context
                .project_root
                .clone()
                .or_else(|| context.config_path.parent().map(Path::to_path_buf))
        })
        .unwrap_or_else(|| start_dir.clone());

    let language = match options
        .language
        .as_deref()
        .map(str::trim)
        .filter(|language| !language.is_empty())
    {
        Some(language) => language.to_ascii_lowercase(),
        None if !selection => frontend
            .and_then(|frontend| frontend.language.clone())
            .ok_or_else(|| CliError::Config {
                error: anyhow::anyhow!("Language not specified and not found in config"),
            })?,
        None => {
            infer_language(
                &options.input,
                &start_dir,
                &installed,
                flag_extension,
                config.as_ref(),
                &workspace,
            )
            .await?
        }
    };

    let resolved_extension = frontend_extension::resolve(flag_extension, frontend, &language)?;
    let frontend_extension::Resolved {
        extension: requested_extension,
        warning: extension_warning,
    } = resolved_extension;
    if let Some(warning) = &extension_warning {
        eprintln!("warning: {warning}");
    }
    let requested_extension = requested_extension.map(|id| id.into_owned());

    let (provider, ir_version) = select_provider(
        &language,
        requested_extension.as_deref(),
        options.ir_version,
        selection,
        config.as_ref(),
        installed,
        &workspace,
    )
    .await?;
    let requested_version = match ir_version {
        IrVersion::V3 => "3",
        IrVersion::V4 => "4.0.0",
    };
    let storage = if selection {
        // A selection is not the project's build, so it writes the one
        // storage every consumer reads, whatever `[ir]` says.
        warn_if_ir_storage_settings_are_ignored(config.as_ref());
        IrStorage::from_config(None)?
    } else {
        IrStorage::from_config(
            config
                .as_ref()
                .and_then(|context| context.config.ir.as_ref()),
        )?
    };
    if ir_version == IrVersion::V3 && storage.layout == morphir_devkit::IrLayout::DocumentTree {
        return Err(CliError::Validation {
            message: "IR v3 supports single-file storage; document-tree storage requires IR v4"
                .into(),
        });
    }

    let file_extensions = provider
        .capability()
        .languages
        .iter()
        .find(|candidate| candidate.id == language)
        .map(|candidate| candidate.file_extensions.clone())
        .unwrap_or_default();
    let manifest = if selection {
        manifest_identity(config.as_ref())
    } else {
        None
    };
    let inputs: Vec<PathBuf> = if options.input.is_empty() {
        let context = config
            .as_ref()
            .expect("a project compile loads configuration");
        let project_root = context.project_root.as_deref().ok_or_else(|| CliError::Config {
            error: anyhow::anyhow!("Workspace has no selected project; use --project with a declared member path or exact project name"),
        })?;
        vec![super::absolute_from(
            project_root,
            &configured_source_directory(&context.config),
        )]
    } else {
        options
            .input
            .iter()
            .map(|input| super::absolute_from(&start_dir, Path::new(input)))
            .collect()
    };
    let captured = capture_source_selection(&SourceSelectionOptions {
        inputs: &inputs,
        file_extensions: &file_extensions,
        language_id: &language,
        manifest: manifest.as_ref().map(|(path, _)| path.as_path()),
        byte_limit: DEFAULT_SOURCE_BYTES,
    })
    .map_err(|error| CliError::Validation {
        message: error.to_string(),
    })?;
    // Cardinality is negotiated for a selection of files, which a provider
    // synthesizes and may only take one at a time. A project compile has
    // always submitted its whole source set, and an installed record cannot
    // say whether its provider takes more than one document, so a project is
    // left to the provider.
    if selection && captured.sources.len() > 1 && !provider.capability().multi_document {
        return Err(CliError::Extension {
            message: format!(
                "Provider '{}' compiles one document per request: it does not declare \
                 frontend.multiDocument, and this compile has {} sources. Select one file, or \
                 name a provider that declares multi-document compilation with --extension",
                provider.id(),
                captured.sources.len()
            ),
        });
    }

    let (package, selection_record) = if selection {
        let explicit_name = options
            .package_name
            .clone()
            .or_else(|| manifest.as_ref().map(|(_, name)| name.clone()));
        let package = discover_identity(
            &provider,
            &home,
            &workspace,
            captured.clone(),
            explicit_name,
        )
        .await?;
        let record = captured
            .sources
            .iter()
            .map(|source| source.path.to_string_lossy().into_owned())
            .collect();
        (package, Some(record))
    } else {
        let context = config
            .as_ref()
            .expect("a project compile loads configuration");
        // An explicit name on a project compile is the flag's to set: the
        // project already supplied everything else, and the frontend applies
        // its own package contract at compile.
        let name = options
            .package_name
            .clone()
            .or_else(|| {
                context
                    .current_project
                    .as_ref()
                    .map(|project| project.name.clone())
            })
            .or_else(|| {
                context
                    .config
                    .project
                    .as_ref()
                    .map(|project| project.name.clone())
            })
            .unwrap_or_else(|| "default".into());
        (
            CompilePackage {
                name,
                // The project's declared exposure, when it has one: absent
                // means the compile exposes every module it found, where an
                // empty list would mean a package that exposes nothing.
                exposed_modules: context.exposed_modules().map(<[String]>::to_vec),
            },
            None,
        )
    };

    let mut extra = HashMap::new();
    if !selection {
        let context = config
            .as_ref()
            .expect("a project compile loads configuration");
        let section = context.config.frontend.as_ref();
        extra.insert("outputDir".into(), serde_json::json!(dest.paths.dest));
        extra.insert(
            "emitParseStage".into(),
            serde_json::json!(section.is_none_or(|frontend| frontend.emit_parse_stage)),
        );
        extra.insert(
            "emitParseStageFatal".into(),
            serde_json::json!(section.is_some_and(|frontend| frontend.emit_parse_stage_fatal)),
        );
    }
    // The prelude and the compatibility modes are Elm notions, so they only
    // reach a provider asked to compile Elm.
    let mut mode_warnings = Vec::new();
    if language.eq_ignore_ascii_case("elm") {
        if let Some(prelude) = elm_prelude::from_config(frontend)? {
            extra.insert(elm_prelude::OPTION_KEY.to_owned(), prelude);
        }
        // A mode can come from the command line or the environment, so it
        // applies whether or not a configuration was loaded. With none, there
        // is no loader to merge the environment layer in, so it is read here.
        let from_environment;
        let modes_frontend = match frontend {
            Some(section) => Some(section),
            None => {
                from_environment = elm_modes::environment_frontend();
                from_environment.as_ref()
            }
        };
        mode_warnings = elm_modes::apply(&mut extra, &options.elm_modes, modes_frontend)?;
        for warning in &mode_warnings {
            eprintln!("warning: {warning}");
        }
    }
    let extension_options = ExtensionCompileOptions {
        types_only: options.types_only,
        ir_version: advertised_ir_version(&provider.capability().ir_versions, requested_version),
        extra,
    };

    // A selection compiles what it names and nothing else, so a project's
    // cache of other modules would only be retired by it.
    let cache = match &provider {
        Provider::Registered(resolved)
            if !selection && !options.no_cache && provider_supports_incremental(resolved) =>
        {
            Some((
                cache::CompileCache::open(&workspace, resolved.info().id.as_str(), &package.name),
                cache_key(resolved, &extension_options),
            ))
        }
        _ => None,
    };
    let baseline = cache
        .as_ref()
        .and_then(|(cache, key)| cache.read_baseline(key));

    let documents = captured
        .sources
        .iter()
        .map(|source| {
            Ok(SourceDocument {
                uri: file_uri(&source.path)?,
                language_id: language.clone(),
                version: 1,
                text: source.text.clone(),
            })
        })
        .collect::<Result<Vec<_>, CliError>>()?;
    let request = CompileRequest {
        language_id: language.clone(),
        sources: SourceSet {
            root: Some(file_uri(&captured.selection_root)?),
            documents,
        },
        package,
        dependencies: Vec::new(),
        options: extension_options,
        baseline,
    };

    Ok(PreparedCompile {
        start_dir,
        format: crate::output::OutputFormat::from_flags(options.json, options.json_lines),
        install: options.output,
        task,
        dest,
        out_module: out.module,
        out_root: out.root,
        home,
        workspace,
        provider,
        request,
        ir_version,
        storage,
        cache,
        warnings: config_warnings(extension_warning.as_deref(), &mode_warnings),
        language,
        selection: selection_record,
    })
}

/// Run a prepared compile and publish its result.
pub async fn execute_compile(prepared: PreparedCompile) -> starbase::AppResult<miette::Report> {
    use crate::output::CompileOutput;

    let PreparedCompile {
        start_dir,
        format,
        install,
        task,
        dest,
        out_module,
        out_root,
        home,
        workspace,
        provider,
        request,
        ir_version,
        storage,
        cache,
        warnings,
        language,
        selection,
    } = prepared;
    let result = provider.compile(&home, &workspace, request).await?;
    // The cache records what this run learned whether or not the run as a
    // whole succeeded; see `cache_write_is_warranted`.
    if let Some((cache, key)) = cache.as_ref()
        && cache_write_is_warranted(&result)
    {
        store_compile_results(
            cache,
            key,
            result.context_digest.clone(),
            &result.module_results,
        );
    }
    let mut diagnostics = convert_extension_diagnostics(&result.diagnostics);
    prepend_config_warnings(&mut diagnostics, &warnings, format);
    let has_error = result
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == DiagnosticSeverity::Error);
    let paths = dest.paths;
    if !result.success || has_error {
        let output = CompileOutput {
            success: false,
            ir: None,
            diagnostics,
            modules: vec![],
            // The task's `.dest` directory, not the IR file inside it.
            output_path: paths.dest.to_string_lossy().into_owned(),
            installed_path: None,
        };
        let message = compilation_failure_message(&result);
        write_compile_output(format, &output)?;
        return Err(CliError::Compilation { message }.into());
    }
    let ir_file = VersionedIr::validate(&result, ir_version)?;
    let descriptor = ir_file.write(&paths.dest, &storage)?;
    let mut record = TaskResult::new(&task, &out_module);
    record.language = Some(language);
    record.value = vec![descriptor.path.clone()];
    record.ir = Some(descriptor);
    record.installed = dest.previous_installed;
    if let Some(sources) = selection {
        record.extra.insert(
            COMPILE_SCOPE_KEY.to_owned(),
            serde_json::json!({ "kind": "explicit-selection", "sources": sources }),
        );
    }
    record
        .write(&paths.result)
        .map_err(|error| CliError::Config { error })?;
    let installed_path =
        crate::commands::install::maybe_install(&paths, install.as_deref(), &start_dir, &out_root)?;
    // The task is finished: its record is written and its install is done, so
    // the next run of this task may start.
    drop(dest.lock);
    let output = CompileOutput {
        success: true,
        ir: Some(ir_file.json()?),
        diagnostics,
        modules: result.modules,
        output_path: paths.dest.to_string_lossy().into_owned(),
        installed_path,
    };
    write_compile_output(format, &output)?;
    Ok(None)
}

/// Load the configuration a run asked for.
///
/// A project compile needs one, from `--config` or found by walking up from
/// the current directory. A selection reads one only when `--config` names it
/// or `--project` asks for discovery: a manifest it did not ask for must not
/// change what a standalone compile produces.
fn load_configuration(
    options: &CompileOptions,
    selection: bool,
    start_dir: &Path,
) -> Result<Option<ConfigContext>, CliError> {
    let config_path = match options.config_path.as_deref() {
        Some(path) => Some(super::absolute_from(start_dir, Path::new(path))),
        None if !selection => Some(
            discover_config(start_dir)
                .map_err(|error| CliError::Config { error })?
                .ok_or_else(|| CliError::Config {
                    error: anyhow::anyhow!("No morphir.toml, morphir.yaml, or morphir.json found"),
                })?,
        ),
        None if options.project.is_some() => Some(
            discover_config(start_dir)
                .map_err(|error| CliError::Config { error })?
                .ok_or_else(|| CliError::Config {
                    error: anyhow::anyhow!("--project requires a Morphir configuration"),
                })?,
        ),
        None => None,
    };
    config_path
        .map(|path| {
            morphir_devkit::load_config_context_with(
                &path,
                &morphir_devkit::ConfigLoadOptions {
                    project: options
                        .project
                        .clone()
                        .map(morphir_devkit::config::ProjectSelection::Explicit)
                        .unwrap_or_default(),
                    ..Default::default()
                },
            )
        })
        .transpose()
        .map_err(|error| CliError::Config { error })
}

/// The manifest a selection borrows its identity from: the loaded
/// configuration's file, and the name of the project it selects. A
/// configuration that names no project lends configuration but no identity,
/// so the provider synthesizes one.
fn manifest_identity(config: Option<&ConfigContext>) -> Option<(PathBuf, String)> {
    let context = config?;
    let name = context
        .current_project
        .as_ref()
        .map(|project| project.name.clone())?;
    Some((context.config_path.clone(), name))
}

fn configured_source_directory(config: &MorphirConfig) -> PathBuf {
    config
        .project
        .as_ref()
        .map(|project| PathBuf::from(&project.source_directory))
        .or_else(|| {
            config.frontend.as_ref().and_then(|frontend| {
                frontend
                    .settings
                    .get("source_directory")
                    .and_then(|value| value.as_str())
                    .map(PathBuf::from)
            })
        })
        .unwrap_or_else(|| PathBuf::from("src"))
}

/// Settle the language from the selected files' suffixes, against the
/// suffixes providers declare.
///
/// Only providers this run could use are consulted: the one `--extension`
/// names, or every installed and default provider together with those the
/// configuration names. A suffix no provider claims, or one several
/// languages claim, is an error that says so; the CLI never picks.
async fn infer_language(
    inputs: &[String],
    start_dir: &Path,
    installed: &[InstalledExtensionSnapshot],
    flag_extension: Option<&str>,
    config: Option<&ConfigContext>,
    workspace: &Path,
) -> Result<String, CliError> {
    let frontend = config.and_then(|context| context.config.frontend.as_ref());
    // A provider something names must answer; one that is only launched by
    // `[extensions.<id>] command` may be a backend or be offline, and must not
    // stop a compile it has nothing to do with.
    let selected: Vec<String> = match flag_extension {
        Some(id) => vec![id.to_owned()],
        None => frontend_extension::configured_ids(frontend)?,
    };
    let mut named = selected.clone();
    if flag_extension.is_none() {
        named.extend(configured_command_ids(config));
        named.sort();
        named.dedup();
    }
    // (provider id, language id, suffixes)
    let mut claims: Vec<(String, String, Vec<String>)> = Vec::new();
    let mut add = |id: &str, capability: &FrontendCapability| {
        for language in &capability.languages {
            claims.push((
                id.to_owned(),
                language.id.clone(),
                language.file_extensions.clone(),
            ));
        }
    };
    let registry_ids: Vec<Option<&str>> = match flag_extension {
        Some(id) => vec![Some(id)],
        None => std::iter::once(None)
            .chain(named.iter().map(|id| Some(id.as_str())))
            .collect(),
    };
    for only in registry_ids {
        if let Some(id) = only {
            let required = selected.iter().any(|selected| selected == id);
            let probed = match configured_launch(config, id, workspace) {
                Ok(Some(launch)) => Some(crate::extensions::probe_process(launch, id).await),
                Ok(None) => None,
                Err(error) => Some(Err(error)),
            };
            match probed {
                Some(Ok(negotiated)) => {
                    if let Some(capability) = negotiated.capabilities.frontend.as_ref() {
                        add(id, capability);
                    }
                    continue;
                }
                Some(Err(error)) if required => return Err(error),
                Some(Err(error)) => {
                    skip_unavailable(id, &error);
                    continue;
                }
                None => {}
            }
        }
        let registry = crate::extensions::extension_registry_for(installed.to_vec(), only)?;
        if let Some(id) = flag_extension
            && registry.providers().is_empty()
        {
            return Err(not_installed(id));
        }
        for provider in registry.providers() {
            if let Some(capability) = provider.capabilities().frontend.as_ref() {
                add(provider.info().id.as_str(), capability);
            }
        }
    }
    claims.sort();
    claims.dedup();

    let mut language: Option<String> = None;
    for input in inputs {
        let path = super::absolute_from(start_dir, Path::new(input));
        let suffix = path
            .file_name()
            .and_then(|name| name.to_str())
            .and_then(|name| name.rsplit_once('.').map(|(_, suffix)| suffix.to_owned()))
            .ok_or_else(|| CliError::Validation {
                message: format!(
                    "Cannot tell the language of '{}' from its name; pass --language",
                    path.display()
                ),
            })?;
        let claimants: Vec<&(String, String, Vec<String>)> = claims
            .iter()
            .filter(|(_, _, suffixes)| {
                suffixes.iter().any(|declared| {
                    declared
                        .trim_start_matches('.')
                        .eq_ignore_ascii_case(&suffix)
                })
            })
            .collect();
        let mut languages: Vec<&str> = claimants
            .iter()
            .map(|(_, language, _)| language.as_str())
            .collect();
        languages.sort_unstable();
        languages.dedup();
        let found = match languages.as_slice() {
            [] => {
                let mut available: Vec<&str> = claims
                    .iter()
                    .map(|(_, language, _)| language.as_str())
                    .collect();
                available.sort_unstable();
                available.dedup();
                return Err(CliError::Validation {
                    message: format!(
                        "No provider declares the '.{suffix}' suffix of '{}'; languages available: {}. Pass --language, or install or name a provider with --extension",
                        path.display(),
                        if available.is_empty() {
                            "none".to_owned()
                        } else {
                            available.join(", ")
                        }
                    ),
                });
            }
            [only] => (*only).to_owned(),
            _ => {
                let listed = claimants
                    .iter()
                    .map(|(id, language, _)| format!("{id} ({language})"))
                    .collect::<Vec<_>>()
                    .join(", ");
                return Err(CliError::Validation {
                    message: format!(
                        "The '.{suffix}' suffix is claimed for more than one language: {listed}. Pass --language or --extension to choose"
                    ),
                });
            }
        };
        match &language {
            Some(existing) if existing != &found => {
                return Err(CliError::Validation {
                    message: format!(
                        "The selected sources are in more than one language ({existing} and {found}); a compile takes one language"
                    ),
                });
            }
            Some(_) => {}
            None => language = Some(found),
        }
    }
    language.ok_or_else(|| CliError::Validation {
        message: "no source inputs were given".into(),
    })
}

/// The launch a configuration gives a provider by `[extensions.<id>] command`,
/// when it gives one and the extension is enabled.
fn configured_launch(
    config: Option<&ConfigContext>,
    id: &str,
    workspace: &Path,
) -> Result<Option<ProcessLaunch>, CliError> {
    let Some(context) = config else {
        return Ok(None);
    };
    let Some(spec) = context
        .config
        .extensions
        .get(id)
        .filter(|spec| spec.enabled && spec.command.is_some())
    else {
        return Ok(None);
    };
    let key = format!("[extensions.{id}].command");
    let command = spec
        .command
        .as_deref()
        .map(str::trim)
        .filter(|command| !command.is_empty())
        .ok_or_else(|| CliError::Extension {
            message: format!("Missing configured process extension command; set {key}"),
        })?;
    let config_dir = context.config_path.parent().unwrap_or(workspace);
    let configured_path = PathBuf::from(command);
    let program = if configured_path.is_absolute() {
        configured_path
    } else {
        config_dir.join(configured_path)
    };
    let launch = spec.args.iter().fold(
        ProcessLaunch::new(id, program, config_dir),
        |launch, arg| launch.arg(arg),
    );
    Ok(Some(
        filtered_process_environment()
            .iter()
            .fold(launch, |launch, (key, value)| launch.env(key, value)),
    ))
}

/// Every enabled extension a loaded configuration launches by
/// `[extensions.<id>] command`, in id order.
fn configured_command_ids(config: Option<&ConfigContext>) -> Vec<String> {
    let mut ids: Vec<String> = config
        .map(|context| {
            context
                .config
                .extensions
                .iter()
                .filter(|(_, spec)| spec.enabled && spec.command.is_some())
                .map(|(id, _)| id.clone())
                .collect()
        })
        .unwrap_or_default();
    ids.sort();
    ids
}

/// Report a configured extension that nothing named and that could not be
/// asked what it provides. It is left out of provider selection, not fatal.
fn skip_unavailable(id: &str, error: &CliError) {
    eprintln!("warning: skipping configured extension '{id}' while selecting a frontend: {error}");
}

/// The configured process provider for `language` when nothing names one.
///
/// A configuration that launches an extension by `[extensions.<id>] command`
/// makes that process a provider, overriding an installed extension with the
/// same id. Nothing in the host knows which language it serves, so each one
/// is asked. Exactly one that declares the language is the provider; more
/// than one is refused, naming them, because the host never picks.
async fn unnamed_configured_provider(
    config: Option<&ConfigContext>,
    language: &str,
    workspace: &Path,
) -> Result<Option<(String, ProcessLaunch)>, CliError> {
    let mut serving = Vec::new();
    for id in configured_command_ids(config) {
        // Nothing named this extension, so one that cannot start is skipped:
        // it may be a backend, or offline, and has nothing to do with this
        // compile.
        let launch = match configured_launch(config, &id, workspace) {
            Ok(Some(launch)) => launch,
            Ok(None) => continue,
            Err(error) => {
                skip_unavailable(&id, &error);
                continue;
            }
        };
        let negotiated = match crate::extensions::probe_process(launch.clone(), &id).await {
            Ok(negotiated) => negotiated,
            Err(error) => {
                skip_unavailable(&id, &error);
                continue;
            }
        };
        let declares = negotiated
            .capabilities
            .frontend
            .as_ref()
            .is_some_and(|frontend| {
                frontend.compile
                    && frontend
                        .languages
                        .iter()
                        .any(|candidate| candidate.id == language)
            });
        if declares {
            serving.push((id, launch));
        }
    }
    match serving.len() {
        0 => Ok(None),
        1 => Ok(serving.pop()),
        _ => Err(CliError::Extension {
            message: format!(
                "More than one configured extension provides language '{language}': {}. Name one with --extension or [frontend.{language}] extension",
                serving
                    .iter()
                    .map(|(id, _)| id.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
        }),
    }
}

fn filtered_process_environment() -> Vec<(OsString, OsString)> {
    [
        "HOME",
        "USERPROFILE",
        "TMPDIR",
        "TMP",
        "TEMP",
        "SystemRoot",
        "WINDIR",
        "LANG",
        "LC_ALL",
    ]
    .into_iter()
    .filter_map(|key| std::env::var_os(key).map(|value| (key.into(), value)))
    .collect()
}

/// Settle the provider and the IR version it will produce.
///
/// A project asks for the version `--ir-version` or `[ir]` names, v4 by
/// default. A selection asks for `--ir-version` when given, and otherwise for
/// the oldest release its provider serves: that keeps the classic IR a
/// single-file compile has always written, from whichever provider, and a
/// newer release stays one flag away wherever the provider serves it.
async fn select_provider(
    language: &str,
    requested: Option<&str>,
    explicit_version: Option<IrVersion>,
    selection: bool,
    config: Option<&ConfigContext>,
    installed: Vec<InstalledExtensionSnapshot>,
    workspace: &Path,
) -> Result<(Provider, IrVersion), CliError> {
    let versions: Vec<IrVersion> = match (explicit_version, selection) {
        (Some(version), _) => vec![version],
        (None, true) => vec![IrVersion::V3, IrVersion::V4],
        (None, false) => vec![selected_ir_version(
            None,
            config.and_then(|context| context.config.ir.as_ref()),
        )?],
    };

    let configured = match requested {
        Some(id) => configured_launch(config, id, workspace)?.map(|launch| (id.to_owned(), launch)),
        None => unnamed_configured_provider(config, language, workspace).await?,
    };
    if let Some((id, launch)) = configured {
        let id = id.as_str();
        let negotiated = crate::extensions::probe_process(launch.clone(), id).await?;
        let frontend = negotiated
            .capabilities
            .frontend
            .clone()
            .filter(|frontend| {
                negotiated.info.types.contains(&ExtensionType::Frontend)
                    && frontend.compile
                    && frontend
                        .languages
                        .iter()
                        .any(|candidate| candidate.id == language)
            })
            .ok_or_else(|| CliError::Extension {
                message: format!("extension '{id}' does not provide language '{language}'"),
            })?;
        let version = versions
            .iter()
            .copied()
            .find(|version| advertises(&frontend, *version))
            .ok_or_else(|| CliError::Extension {
                message: format!(
                    "extension '{id}' does not produce the requested Morphir IR version; it declares {}",
                    frontend.ir_versions.join(", ")
                ),
            })?;
        let workspace = negotiated.info.types.contains(&ExtensionType::Workspace)
            && negotiated
                .capabilities
                .workspace
                .as_ref()
                .is_some_and(|workspace| {
                    workspace.discover
                        && workspace
                            .protocol_versions
                            .iter()
                            .any(morphir_workspace::speaks_workspace_discovery_protocol)
                });
        return Ok((
            Provider::Configured(Box::new(ConfiguredProvider {
                id: id.to_owned(),
                launch,
                frontend,
                workspace,
            })),
            version,
        ));
    }

    let registry = crate::extensions::extension_registry_for(installed, requested)?;
    let mut last_error = None;
    for version in &versions {
        let text = match version {
            IrVersion::V3 => "3",
            IrVersion::V4 => "4.0.0",
        };
        match registry.resolve_frontend(
            language,
            text,
            morphir_daemon::InvocationPolicy::PreferDirect,
        ) {
            Ok(resolved) => return Ok((Provider::Registered(resolved), *version)),
            Err(error) => last_error = Some(error),
        }
    }
    let error = last_error.expect("at least one version was tried");
    Err(match requested {
        Some(id) => CliError::Extension {
            message: format!("extension '{id}' does not provide language '{language}': {error}"),
        },
        None => CliError::Extension {
            message: format!(
                "Failed to resolve frontend for '{language}': {error}. Install the \
                 'morphir-{language}' extension, or name another provider with --extension"
            ),
        },
    })
}

fn not_installed(id: &str) -> CliError {
    CliError::Extension {
        message: format!(
            "extension {id} is not installed; install it with `morphir extension install {id}`, or name another provider with --extension"
        ),
    }
}

fn advertises(frontend: &FrontendCapability, version: IrVersion) -> bool {
    let wanted = match version {
        IrVersion::V3 => 3,
        IrVersion::V4 => 4,
    };
    frontend.ir_versions.iter().any(|advertised| {
        super::normalize_ir_version_text(advertised)
            .is_some_and(|normalized| normalized.release.major() == wanted)
    })
}

/// Ask the provider for a selection's package identity and exposure.
async fn discover_identity(
    provider: &Provider,
    home: &MorphirHome,
    workspace: &Path,
    captured: CapturedSelection,
    explicit_name: Option<String>,
) -> Result<CompilePackage, CliError> {
    if !provider.supports_workspace_discovery() {
        return Err(CliError::Extension {
            message: format!(
                "Provider '{}' cannot compile a selection of source files: it does not declare \
                 workspace discovery, which is how a provider names the modules and package a \
                 selection defines. Compile the project instead, or name a provider that \
                 declares workspace discovery with --extension",
                provider.id()
            ),
        });
    }
    let mut request = captured.request;
    if let Some(name) = explicit_name {
        request.cli_overlay = serde_json::json!({ "project": { "name": name } });
    }
    let snapshot = match provider.discover(home, workspace, request).await? {
        DiscoveryResponse::Success { snapshot } => snapshot,
        DiscoveryResponse::Failure { error } => {
            return Err(CliError::Validation {
                message: format!(
                    "Provider '{}' refused the source selection: {}: {}",
                    provider.id(),
                    error.code,
                    error.message
                ),
            });
        }
    };
    let project = snapshot
        .projects
        .into_iter()
        .next()
        .ok_or_else(|| CliError::Extension {
            message: format!(
                "Provider '{}' discovered no project for the source selection",
                provider.id()
            ),
        })?;
    if project.state == ProjectState::Error {
        let reasons = project
            .diagnostics
            .iter()
            .map(|diagnostic| format!("{}: {}", diagnostic.code, diagnostic.message))
            .collect::<Vec<_>>()
            .join("; ");
        return Err(CliError::Validation {
            message: format!(
                "Provider '{}' could not name the selected sources: {reasons}",
                provider.id()
            ),
        });
    }
    if project.name.is_empty() {
        return Err(CliError::Extension {
            message: format!(
                "Provider '{}' did not name the project for the source selection",
                provider.id()
            ),
        });
    }
    Ok(CompilePackage {
        name: project.name,
        exposed_modules: project.exposed_modules,
    })
}

/// Warn when a loaded configuration's `[ir]` asks for storage a selection
/// does not write. A selection always writes single-file JSON, so that a
/// narrowed result never lands in a project's document tree.
fn warn_if_ir_storage_settings_are_ignored(config: Option<&ConfigContext>) {
    let Some(ir) = config.and_then(|context| context.config.ir.as_ref()) else {
        return;
    };
    if ir.layout == "single-file" && ir.format == "json" {
        return;
    }
    eprintln!(
        "warning: a compile of selected source files always writes single-file JSON; \
         the [ir] layout/format settings do not apply to it"
    );
}

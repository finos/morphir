//! Compile command for compiling source code to Morphir IR

use crate::error::CliError;
use crate::error::convert_extension_diagnostics;
use crate::output::Diagnostic;
use morphir_common::config::model::MorphirConfig;
use morphir_daemon::DaemonError;
use morphir_daemon::extensions::{
    InvokeOutcome, MepTransport, ProcessLaunch, Ready, Session, SpawnedProcessSession,
    protocol::methods,
};
use morphir_devkit::{
    discover_config, ensure_morphir_structure, load_config_context, resolve_compile_output,
    resolve_path_relative_to_config,
};
use morphir_extension_sdk::{
    CompileOptions as ExtensionCompileOptions, CompilePackage, CompileRequest, CompileResult,
    DiagnosticSeverity, ExtensionType, SourceDocument,
    protocol::{InitializeParams, MEP_VERSION, PeerInfo},
};
use starbase::AppResult;
use std::collections::HashMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// Options for the compile command
#[derive(Debug, Default)]
pub struct CompileOptions {
    /// Language to compile (e.g., "gleam", "elm")
    pub language: Option<String>,
    /// Input path or directory
    pub input: Option<String>,
    /// Output path
    pub output: Option<String>,
    /// Package name override
    pub package_name: Option<String>,
    /// Path to configuration file
    pub config_path: Option<String>,
    /// Project name (currently unused)
    pub project: Option<String>,
    /// Output JSON format
    pub json: bool,
    /// Output JSON lines format
    pub json_lines: bool,
}

/// Run the compile command
pub async fn run_compile(options: CompileOptions) -> AppResult<miette::Report> {
    if should_use_single_file_process(&options) {
        return run_single_file_compile(options).await;
    }

    run_legacy_compile(options).await
}

fn should_use_single_file_process(options: &CompileOptions) -> bool {
    if options.config_path.is_none() {
        return false;
    }
    let Some(input) = options.input.as_deref() else {
        return false;
    };
    if let Some(language) = options
        .language
        .as_deref()
        .map(str::trim)
        .filter(|language| !language.is_empty())
    {
        return language.eq_ignore_ascii_case("elm");
    }
    has_elm_extension(Path::new(input))
}

#[derive(Debug)]
struct SingleFileCompileContext {
    language_id: String,
    document: SourceDocument,
    package: CompilePackage,
    output_path: PathBuf,
}

fn has_elm_extension(input: &Path) -> bool {
    input
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| extension.eq_ignore_ascii_case("elm"))
}

fn infer_language(input: &Path, override_value: Option<&str>) -> Result<String, CliError> {
    if let Some(language) = override_value
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return Ok(language.to_ascii_lowercase());
    }

    if has_elm_extension(input) {
        Ok("elm".into())
    } else {
        Err(CliError::Validation {
            message: format!(
                "Cannot infer a source language from '{}'; pass --language",
                input.display()
            ),
        })
    }
}

fn elm_module_name(source: &str) -> Result<String, CliError> {
    let mut offset = skip_elm_trivia(source, 0).ok_or_else(|| CliError::Validation {
        message: "Elm source starts with an unterminated block comment".into(),
    })?;

    let declaration_kind = if let Some(end) = elm_keyword_end(source, offset, "port") {
        offset = skip_elm_trivia(source, end).ok_or_else(|| CliError::Validation {
            message: "Elm module declaration contains an unterminated block comment".into(),
        })?;
        "port"
    } else if let Some(end) = elm_keyword_end(source, offset, "effect") {
        offset = skip_elm_trivia(source, end).ok_or_else(|| CliError::Validation {
            message: "Elm module declaration contains an unterminated block comment".into(),
        })?;
        "effect"
    } else {
        "module"
    };

    let module_end =
        elm_keyword_end(source, offset, "module").ok_or_else(|| CliError::Validation {
            message: "Elm source must start with a module declaration".into(),
        })?;
    offset = skip_elm_trivia(source, module_end).ok_or_else(|| CliError::Validation {
        message: "Elm module declaration contains an unterminated block comment".into(),
    })?;

    let (module_name, module_end) =
        elm_module_path(source, offset).ok_or_else(|| CliError::Validation {
            message: "Elm module declaration is missing a valid module name".into(),
        })?;
    offset = skip_elm_trivia(source, module_end).ok_or_else(|| CliError::Validation {
        message: "Elm module declaration contains an unterminated block comment".into(),
    })?;
    let required_suffix = if declaration_kind == "effect" {
        "where"
    } else {
        "exposing"
    };
    if elm_keyword_end(source, offset, required_suffix).is_none() {
        return Err(CliError::Validation {
            message: format!("Elm module declaration must include '{required_suffix}'"),
        });
    }

    Ok(module_name)
}

fn skip_elm_trivia(source: &str, start: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut offset = start;
    while offset < bytes.len() {
        if source[offset..].starts_with('\u{feff}') {
            offset += '\u{feff}'.len_utf8();
        } else if bytes[offset].is_ascii_whitespace() {
            offset += 1;
        } else if source[offset..].starts_with("--") {
            offset = source[offset + 2..]
                .find('\n')
                .map_or(bytes.len(), |line_end| offset + 2 + line_end + 1);
        } else if source[offset..].starts_with("{-") {
            let mut depth = 1_u32;
            offset += 2;
            while offset < bytes.len() && depth > 0 {
                if source[offset..].starts_with("{-") {
                    depth += 1;
                    offset += 2;
                } else if source[offset..].starts_with("-}") {
                    depth -= 1;
                    offset += 2;
                } else {
                    offset += source[offset..].chars().next()?.len_utf8();
                }
            }
            if depth != 0 {
                return None;
            }
        } else {
            break;
        }
    }
    Some(offset)
}

fn elm_keyword_end(source: &str, offset: usize, keyword: &str) -> Option<usize> {
    let end = offset.checked_add(keyword.len())?;
    if !source.get(offset..)?.starts_with(keyword)
        || source[end..]
            .chars()
            .next()
            .is_some_and(is_elm_identifier_character)
    {
        return None;
    }
    Some(end)
}

fn is_elm_identifier_character(character: char) -> bool {
    character.is_ascii_alphanumeric() || character == '_'
}

fn elm_module_path(source: &str, start: usize) -> Option<(String, usize)> {
    let mut offset = start;
    let mut segments = Vec::new();
    loop {
        let first = source[offset..].chars().next()?;
        if !first.is_ascii_uppercase() {
            return None;
        }
        let segment_start = offset;
        offset += first.len_utf8();
        while let Some(character) = source[offset..].chars().next() {
            if !is_elm_identifier_character(character) {
                break;
            }
            offset += character.len_utf8();
        }
        segments.push(&source[segment_start..offset]);
        if !source[offset..].starts_with('.') {
            break;
        }
        offset += 1;
    }
    Some((segments.join("."), offset))
}

fn prepare_single_file_context(
    inputs: &[PathBuf],
    source: &str,
    language_override: Option<&str>,
    package_override: Option<&str>,
    output_path: PathBuf,
) -> Result<SingleFileCompileContext, CliError> {
    let [input] = inputs else {
        return Err(CliError::Validation {
            message: format!(
                "The configured process compiler requires exactly one source file, received {}",
                inputs.len()
            ),
        });
    };
    let language_id = infer_language(input, language_override)?;
    if language_id != "elm" {
        return Err(CliError::Validation {
            message: format!("Single-file process compilation does not support '{language_id}'"),
        });
    }
    let module_name = elm_module_name(source).unwrap_or_else(|_| fallback_elm_module_name(input));
    let package_name = package_override
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_owned)
        .unwrap_or_else(|| {
            format!(
                "local/{}",
                module_name.to_ascii_lowercase().replace('.', "-")
            )
        });

    Ok(SingleFileCompileContext {
        language_id: language_id.clone(),
        document: SourceDocument {
            uri: file_uri(input)?,
            language_id,
            version: 1,
            text: source.into(),
        },
        package: CompilePackage {
            name: package_name,
            exposed_modules: vec![module_name],
        },
        output_path,
    })
}

fn fallback_elm_module_name(input: &Path) -> String {
    input
        .file_stem()
        .and_then(|stem| stem.to_str())
        .and_then(|candidate| {
            elm_module_path(candidate, 0)
                .filter(|(_, end)| *end == candidate.len())
                .map(|(module_name, _)| module_name)
        })
        .unwrap_or_else(|| "Main".into())
}

fn file_uri(path: &Path) -> Result<String, CliError> {
    let text = path.to_str().ok_or_else(|| CliError::Validation {
        message: format!("Source path is not valid UTF-8: '{}'", path.display()),
    })?;
    if cfg!(windows) {
        windows_file_uri(text)
    } else {
        unix_file_uri(text)
    }
}

fn unix_file_uri(path: &str) -> Result<String, CliError> {
    if !path.starts_with('/') {
        return Err(relative_file_uri_error(path));
    }
    Ok(format!("file://{}", percent_encode_path(path, false)))
}

fn windows_file_uri(path: &str) -> Result<String, CliError> {
    let normalized = path.replace('\\', "/");
    if let Some(network_path) = normalized.strip_prefix("//") {
        let (authority, path) = network_path
            .split_once('/')
            .filter(|(authority, path)| !authority.is_empty() && !path.is_empty())
            .ok_or_else(|| relative_file_uri_error(path))?;
        return Ok(format!(
            "file://{}/{}",
            percent_encode_authority(authority),
            percent_encode_path(path, false)
        ));
    }

    let bytes = normalized.as_bytes();
    if bytes.len() < 3 || !bytes[0].is_ascii_alphabetic() || bytes[1] != b':' || bytes[2] != b'/' {
        return Err(relative_file_uri_error(path));
    }
    Ok(format!(
        "file:///{}",
        percent_encode_path(&normalized, true)
    ))
}

fn percent_encode_authority(value: &str) -> String {
    percent_encode(value, false, false)
}

fn percent_encode_path(value: &str, keep_colon: bool) -> String {
    percent_encode(value, true, keep_colon)
}

fn percent_encode(value: &str, keep_slash: bool, keep_colon: bool) -> String {
    value.bytes().fold(String::new(), |mut result, byte| {
        if byte.is_ascii_alphanumeric()
            || matches!(byte, b'-' | b'.' | b'_' | b'~')
            || (keep_slash && byte == b'/')
            || (keep_colon && byte == b':')
        {
            result.push(char::from(byte));
        } else {
            use std::fmt::Write as _;
            write!(result, "%{byte:02X}").expect("writing to a string cannot fail");
        }
        result
    })
}

fn relative_file_uri_error(path: &str) -> CliError {
    CliError::Validation {
        message: format!("Source path must be absolute: '{path}'"),
    }
}

fn configured_process(
    config: &MorphirConfig,
    language: &str,
    config_dir: &Path,
    environment: &[(OsString, OsString)],
) -> Result<ProcessLaunch, CliError> {
    let extension_id = format!("morphir-{language}");
    let key = format!("[extensions.{extension_id}].command");
    let spec = config
        .extensions
        .get(&extension_id)
        .filter(|spec| spec.enabled)
        .ok_or_else(|| CliError::Extension {
            message: format!("Missing configured process extension; set {key}"),
        })?;
    let command = spec
        .command
        .as_deref()
        .map(str::trim)
        .filter(|command| !command.is_empty())
        .ok_or_else(|| CliError::Extension {
            message: format!("Missing configured process extension command; set {key}"),
        })?;
    let configured_path = PathBuf::from(command);
    let program = if configured_path.is_absolute() {
        configured_path
    } else {
        config_dir.join(configured_path)
    };
    let launch = spec.args.iter().fold(
        ProcessLaunch::new(extension_id, program, config_dir),
        |launch, arg| launch.arg(arg),
    );
    Ok(environment
        .iter()
        .fold(launch, |launch, (key, value)| launch.env(key, value)))
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

async fn run_single_file_compile(options: CompileOptions) -> AppResult<miette::Report> {
    use crate::output::{CompileOutput, OutputFormat};

    let start_dir = std::env::current_dir().map_err(|error| CliError::FileSystem { error })?;
    let input_value = options
        .input
        .as_deref()
        .ok_or_else(|| CliError::Validation {
            message: "Single-file compilation requires --input".into(),
        })?;
    let input_path = absolute_from(&start_dir, Path::new(input_value));
    let config_value = options
        .config_path
        .as_deref()
        .ok_or_else(|| CliError::Config {
            error: anyhow::anyhow!("Single-file process compilation requires --config"),
        })?;
    let config_path = absolute_from(&start_dir, Path::new(config_value));
    let config_context =
        load_config_context(&config_path).map_err(|error| CliError::Config { error })?;
    let config_dir = config_path.parent().ok_or_else(|| CliError::Config {
        error: anyhow::anyhow!(
            "Config file has no parent directory: {}",
            config_path.display()
        ),
    })?;
    let source = read_single_source(&input_path)?;
    let output_path = options
        .output
        .as_deref()
        .map(Path::new)
        .map(|path| absolute_from(&start_dir, path))
        .unwrap_or_else(|| start_dir.join("morphir-ir.json"));
    let context = prepare_single_file_context(
        std::slice::from_ref(&input_path),
        &source,
        options.language.as_deref(),
        options.package_name.as_deref(),
        output_path,
    )?;
    let environment = filtered_process_environment();
    let launch = configured_process(
        &config_context.config,
        &context.language_id,
        config_dir,
        &environment,
    )?;
    let compile_result = invoke_frontend(launch, &context).await?;
    let diagnostics = convert_extension_diagnostics(&compile_result.diagnostics);
    let format = OutputFormat::from_flags(options.json, options.json_lines);

    if !compile_result.success {
        if !compile_result
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.severity == DiagnosticSeverity::Error)
        {
            return Err(CliError::Extension {
                message: "Morphir Elm reported compilation failure without an error diagnostic"
                    .into(),
            }
            .into());
        }
        let output = CompileOutput {
            success: false,
            ir: None,
            diagnostics,
            modules: Vec::new(),
            output_path: context.output_path.to_string_lossy().into_owned(),
        };
        write_compile_output(format, &output)?;
        return Ok(Some(1));
    }

    let distribution = validate_compile_success(&context, &compile_result)?;
    write_distribution(&context.output_path, &distribution)?;
    let typed_ir = serde_json::to_value(&distribution).map_err(|error| CliError::Extension {
        message: format!("Failed to serialize validated classic Morphir IR: {error}"),
    })?;
    let output = CompileOutput {
        success: true,
        ir: Some(typed_ir),
        diagnostics,
        modules: compile_result.modules,
        output_path: context.output_path.to_string_lossy().into_owned(),
    };
    write_compile_output(format, &output)?;
    Ok(None)
}

fn validate_compile_success(
    context: &SingleFileCompileContext,
    result: &CompileResult,
) -> Result<morphir_core::ir::classic::Distribution, CliError> {
    if !result.success {
        return Err(CliError::Extension {
            message: "Expected a successful Morphir Elm compile result".into(),
        });
    }
    if result
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == DiagnosticSeverity::Error)
    {
        return Err(CliError::Extension {
            message: "Morphir Elm returned success with an error diagnostic".into(),
        });
    }
    let missing_modules = context
        .package
        .exposed_modules
        .iter()
        .filter(|expected| !result.modules.contains(expected))
        .cloned()
        .collect::<Vec<_>>();
    if !missing_modules.is_empty() {
        return Err(CliError::Extension {
            message: format!(
                "Morphir Elm did not report expected module(s) {}; reported module(s): {}",
                missing_modules.join(", "),
                if result.modules.is_empty() {
                    "<none>".into()
                } else {
                    result.modules.join(", ")
                }
            ),
        });
    }
    if result.ir_version.as_deref() != Some("3") {
        return Err(CliError::Extension {
            message: "Morphir Elm returned a successful result without Morphir IR version 3".into(),
        });
    }
    let ir = result.ir.as_ref().ok_or_else(|| CliError::Extension {
        message: "Morphir Elm returned a successful result without IR".into(),
    })?;
    let distribution: morphir_core::ir::classic::Distribution = serde_json::from_value(ir.clone())
        .map_err(|error| CliError::Extension {
            message: format!("Morphir Elm returned invalid classic Morphir IR: {error}"),
        })?;
    validate_distribution_identity(context, result, &distribution)?;
    Ok(distribution)
}

fn validate_distribution_identity(
    context: &SingleFileCompileContext,
    result: &CompileResult,
    distribution: &morphir_core::ir::classic::Distribution,
) -> Result<(), CliError> {
    use morphir_core::ir::classic::{DistributionBody, Name, Path};

    fn path_from_string(value: &str, separator: char) -> Path {
        Path::new(value.split(separator).map(Name::from_str).collect())
    }

    let DistributionBody::Library(package_path, _, package) = &distribution.distribution;
    let expected_package_path = path_from_string(&context.package.name, '/');
    if package_path != &expected_package_path {
        return Err(CliError::Extension {
            message: format!(
                "Morphir Elm returned classic Morphir IR for package '{}' instead of '{}'",
                package_path, context.package.name
            ),
        });
    }

    let ir_module_paths = package
        .modules
        .iter()
        .map(|module| &module.path)
        .collect::<Vec<_>>();
    let missing_modules = context
        .package
        .exposed_modules
        .iter()
        .filter(|module| {
            let expected_path = path_from_string(module, '.');
            !ir_module_paths.contains(&&expected_path)
        })
        .cloned()
        .collect::<Vec<_>>();
    if !missing_modules.is_empty() {
        return Err(CliError::Extension {
            message: format!(
                "Morphir Elm returned classic Morphir IR without expected module(s) {}",
                missing_modules.join(", ")
            ),
        });
    }

    let reported_module_paths = result
        .modules
        .iter()
        .map(|module| path_from_string(module, '.'))
        .collect::<Vec<_>>();
    let metadata_matches_ir = reported_module_paths.len() == ir_module_paths.len()
        && reported_module_paths
            .iter()
            .all(|reported| ir_module_paths.contains(&reported))
        && ir_module_paths
            .iter()
            .all(|ir_module| reported_module_paths.contains(ir_module));
    if !metadata_matches_ir {
        let ir_modules = ir_module_paths
            .iter()
            .map(ToString::to_string)
            .collect::<Vec<_>>();
        return Err(CliError::Extension {
            message: format!(
                "Morphir Elm module metadata does not match classic Morphir IR; reported module(s): {}; IR module path(s): {}",
                if result.modules.is_empty() {
                    "<none>".into()
                } else {
                    result.modules.join(", ")
                },
                if ir_modules.is_empty() {
                    "<none>".into()
                } else {
                    ir_modules.join(", ")
                }
            ),
        });
    }

    Ok(())
}

fn absolute_from(base: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        base.join(path)
    }
}

fn read_single_source(input_path: &Path) -> Result<String, CliError> {
    let metadata = std::fs::metadata(input_path).map_err(|error| CliError::FileSystem { error })?;
    if !metadata.is_file() {
        return Err(CliError::Validation {
            message: format!(
                "The configured process compiler requires a single source file, not '{}'",
                input_path.display()
            ),
        });
    }
    std::fs::read_to_string(input_path).map_err(|error| CliError::FileSystem { error })
}

async fn invoke_frontend(
    launch: ProcessLaunch,
    context: &SingleFileCompileContext,
) -> Result<CompileResult, CliError> {
    let loaded = SpawnedProcessSession::spawn_typestate(launch)
        .await
        .map_err(|error| CliError::Extension {
            message: error.to_string(),
        })?;
    let ready = loaded
        .initialize(InitializeParams {
            protocol_versions: vec![MEP_VERSION.into()],
            host: PeerInfo {
                name: "morphir-cli".into(),
                version: env!("CARGO_PKG_VERSION").into(),
            },
        })
        .await
        .map_err(|failure| CliError::Extension {
            message: failure.error().to_string(),
        })?;
    let ready = validate_frontend_session(ready, &context.language_id).await?;

    let request = CompileRequest {
        language_id: context.language_id.clone(),
        documents: vec![context.document.clone()],
        package: context.package.clone(),
        dependencies: Vec::new(),
        options: ExtensionCompileOptions {
            types_only: false,
            ir_version: "3".into(),
            extra: HashMap::new(),
        },
    };
    match ready
        .invoke::<CompileResult>(methods::COMPILE, request)
        .await
    {
        InvokeOutcome::Success(session, result) => {
            shutdown_frontend(session).await?;
            Ok(result)
        }
        InvokeOutcome::Rejected(session, error) => {
            let original = error.to_string();
            shutdown_frontend(session)
                .await
                .map_err(|cleanup| CliError::Extension {
                    message: format!("{original}; extension shutdown also failed: {cleanup}"),
                })?;
            Err(CliError::Extension { message: original })
        }
        InvokeOutcome::Failed(failure) => Err(CliError::Extension {
            message: failure.error().to_string(),
        }),
    }
}

async fn validate_frontend_session<T: MepTransport>(
    session: Session<T, Ready>,
    language: &str,
) -> Result<Session<T, Ready>, CliError> {
    let validation = validate_frontend_capabilities(&session, language);
    match validation {
        Ok(()) => Ok(session),
        Err(error) => match session.shutdown().await {
            Ok(_) => Err(error),
            Err(cleanup) => Err(append_shutdown_failure(error, cleanup.error())),
        },
    }
}

fn append_shutdown_failure(error: CliError, cleanup: &DaemonError) -> CliError {
    let original = match error {
        CliError::Extension { message } => message,
        other => other.to_string(),
    };
    CliError::Extension {
        message: format!("{original}; extension shutdown also failed: {cleanup}"),
    }
}

fn validate_frontend_capabilities<T: MepTransport>(
    session: &Session<T, Ready>,
    language: &str,
) -> Result<(), CliError> {
    let negotiation = session.negotiated();
    if !negotiation
        .extension()
        .types
        .contains(&ExtensionType::Frontend)
    {
        return Err(CliError::Extension {
            message: "Configured Morphir Elm extension is not a frontend".into(),
        });
    }
    let frontend = negotiation
        .capabilities()
        .frontend
        .as_ref()
        .ok_or_else(|| CliError::Extension {
            message: "Configured Morphir Elm extension did not advertise frontend details".into(),
        })?;
    if !frontend.compile
        || !frontend
            .languages
            .iter()
            .any(|candidate| candidate.id == language)
        || !frontend.ir_versions.iter().any(|version| version == "3")
    {
        return Err(CliError::Extension {
            message: format!(
                "Configured Morphir Elm extension must advertise {} compilation to Morphir IR 3",
                display_language(language)
            ),
        });
    }
    Ok(())
}

fn display_language(language: &str) -> String {
    let mut characters = language.chars();
    characters.next().map_or_else(String::new, |first| {
        first.to_uppercase().chain(characters).collect()
    })
}

async fn shutdown_frontend(
    session: morphir_daemon::extensions::Session<
        morphir_daemon::extensions::SpawnedProcessTransport,
        morphir_daemon::extensions::Ready,
    >,
) -> Result<(), CliError> {
    session
        .shutdown()
        .await
        .map(|_| ())
        .map_err(|failure| CliError::Extension {
            message: failure.error().to_string(),
        })
}

fn write_distribution(
    output_path: &Path,
    distribution: &morphir_core::ir::classic::Distribution,
) -> Result<(), CliError> {
    if let Some(parent) = output_path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        std::fs::create_dir_all(parent).map_err(|error| CliError::FileSystem { error })?;
    }
    let bytes = serde_json::to_vec_pretty(distribution).map_err(|error| CliError::Extension {
        message: format!("Failed to serialize validated classic Morphir IR: {error}"),
    })?;
    std::fs::write(output_path, bytes).map_err(|error| CliError::FileSystem { error })
}

fn write_compile_output(
    format: crate::output::OutputFormat,
    output: &crate::output::CompileOutput,
) -> Result<(), CliError> {
    use crate::output::{OutputFormat, write_output};

    match format {
        OutputFormat::Human => {
            if output.success {
                eprintln!("Compilation successful");
                eprintln!("Output: {}", output.output_path);
            }
            for diagnostic in &output.diagnostics {
                let location = diagnostic
                    .uri
                    .as_deref()
                    .map(|uri| format!("{uri}: "))
                    .unwrap_or_default();
                eprintln!("{}: {location}{}", diagnostic.level, diagnostic.message);
            }
            Ok(())
        }
        OutputFormat::Json | OutputFormat::JsonLines => {
            write_output(format, output).map_err(CliError::from)
        }
    }
}

async fn run_legacy_compile(options: CompileOptions) -> AppResult<miette::Report> {
    let CompileOptions {
        language,
        input,
        output,
        package_name,
        config_path,
        project: _project,
        json,
        json_lines,
    } = options;
    use crate::output::{CompileOutput, OutputFormat, write_output};
    // Discover config if not provided
    let start_dir = std::env::current_dir().map_err(|e| CliError::FileSystem { error: e })?;

    let config_file = if let Some(cfg) = config_path {
        PathBuf::from(cfg)
    } else {
        discover_config(&start_dir)
            .map_err(|error| CliError::Config { error })?
            .ok_or_else(|| CliError::Config {
                error: anyhow::anyhow!("No morphir.toml, morphir.yaml, or morphir.json found"),
            })?
    };

    // Load config context
    let ctx = load_config_context(&config_file).map_err(|e| CliError::Config { error: e })?;

    // Ensure .morphir/ structure exists
    ensure_morphir_structure(&ctx.morphir_dir).map_err(|e| CliError::Config { error: e })?;

    // Determine language (from CLI or config)
    let lang = language
        .or_else(|| {
            ctx.config
                .frontend
                .as_ref()
                .and_then(|f| f.language.clone())
        })
        .ok_or_else(|| CliError::Config {
            error: anyhow::anyhow!("Language not specified and not found in config"),
        })?;

    // Determine project name
    let proj_name = package_name
        .or_else(|| ctx.current_project.as_ref().map(|p| p.name.clone()))
        .or_else(|| ctx.config.project.as_ref().map(|p| p.name.clone()))
        .unwrap_or_else(|| "default".to_string());

    // Determine input path (resolve relative to config file location)
    let input_path = if let Some(inp) = input {
        // CLI-provided input is resolved relative to current working directory
        let inp_path = PathBuf::from(inp);
        if inp_path.is_absolute() {
            inp_path
        } else {
            start_dir.join(inp_path)
        }
    } else {
        // Config-provided source_directory is resolved relative to config file
        let raw_path = ctx
            .config
            .project
            .as_ref()
            .map(|p| PathBuf::from(&p.source_directory))
            .or_else(|| {
                ctx.config.frontend.as_ref().and_then(|f| {
                    f.settings
                        .get("source_directory")
                        .and_then(|v| v.as_str())
                        .map(PathBuf::from)
                })
            })
            .unwrap_or_else(|| PathBuf::from("src"));

        resolve_path_relative_to_config(&raw_path, &ctx.config_path)
    };

    // Determine output path
    let output_path = if let Some(out) = output {
        PathBuf::from(out)
    } else {
        resolve_compile_output(&proj_name, &lang, &ctx.morphir_dir)
    };

    // Create extension registry
    let registry = morphir_daemon::extensions::registry::ExtensionRegistry::new(
        ctx.project_root
            .unwrap_or_else(|| ctx.config_path.parent().unwrap().to_path_buf()),
        output_path.clone(),
    )
    .map_err(|e| CliError::Extension {
        message: format!("Failed to create extension registry: {}", e),
    })?;

    // Register builtin extensions
    let builtins = morphir_devkit::discover_builtin_extensions();
    for builtin in builtins {
        if let Some(path) = builtin.path {
            registry
                .register_builtin(&builtin.id, path)
                .await
                .map_err(|e| CliError::Extension {
                    message: format!("Failed to register builtin extension {}: {}", builtin.id, e),
                })?;
        }
    }

    // Find and load extension by language
    let extension = registry
        .find_extension_by_language(&lang)
        .await
        .ok_or_else(|| CliError::Extension {
            message: format!("No extension found for language: {}", lang),
        })?;

    // Collect source files
    let source_files =
        collect_source_files(&input_path, &lang).map_err(|e| CliError::FileSystem {
            error: std::io::Error::other(e),
        })?;

    // Get emit_parse_stage setting from config (default: true)
    let emit_parse_stage = ctx
        .config
        .frontend
        .as_ref()
        .map(|f| f.emit_parse_stage)
        .unwrap_or(true);

    // Get emit_parse_stage_fatal setting from config (default: false)
    let emit_parse_stage_fatal = ctx
        .config
        .frontend
        .as_ref()
        .map(|f| f.emit_parse_stage_fatal)
        .unwrap_or(false);

    // Call extension's compile method
    let compile_params = serde_json::json!({
        "input": input_path.to_string_lossy(),
        "output": output_path.to_string_lossy(),
        "package_name": proj_name,
        "files": source_files,
        "emitParseStage": emit_parse_stage,
        "emitParseStageFatal": emit_parse_stage_fatal,
    });

    let result: serde_json::Value = extension
        .call("morphir.frontend.compile", compile_params)
        .await
        .map_err(|e| CliError::Extension {
            message: format!("Extension compile call failed: {}", e),
        })?;

    let format = OutputFormat::from_flags(json, json_lines);

    // Extract diagnostics and modules from result
    let diagnostics: Vec<Diagnostic> = result
        .get("diagnostics")
        .and_then(|d| serde_json::from_value(d.clone()).ok())
        .unwrap_or_default();

    let modules: Vec<String> = result
        .get("modules")
        .and_then(|m| serde_json::from_value(m.clone()).ok())
        .unwrap_or_default();

    let success = result
        .get("success")
        .and_then(|s| s.as_bool())
        .unwrap_or(true);

    if !success {
        let error_msg = result
            .get("error")
            .and_then(|e| e.as_str())
            .unwrap_or("Compilation failed");

        if format != OutputFormat::Human {
            let output = CompileOutput {
                success: false,
                ir: None,
                diagnostics: diagnostics.clone(),
                modules: vec![],
                output_path: output_path.to_string_lossy().to_string(),
            };
            write_output(format, &output).map_err(CliError::from)?;
        } else {
            let err = CliError::Compilation {
                message: error_msg.to_string(),
            };
            err.report();
        }
        return Err(CliError::Compilation {
            message: error_msg.to_string(),
        }
        .into());
    }

    if format != OutputFormat::Human {
        let output = CompileOutput {
            success: true,
            ir: result.get("ir").cloned(),
            diagnostics,
            modules,
            output_path: output_path.to_string_lossy().to_string(),
        };
        write_output(format, &output).map_err(CliError::from)?;
    } else {
        println!("Compilation successful!");
        println!("Output: {:?}", output_path);
        if !diagnostics.is_empty() {
            println!("\nDiagnostics:");
            for diag in &diagnostics {
                println!("  {}: {}", diag.level, diag.message);
            }
        }
    }

    Ok(None)
}

/// Collect source files from input directory
fn collect_source_files(input_path: &Path, language: &str) -> anyhow::Result<Vec<String>> {
    let mut files = Vec::new();

    if !input_path.exists() {
        return Ok(files);
    }

    if input_path.is_file() {
        files.push(input_path.to_string_lossy().to_string());
        return Ok(files);
    }

    // Determine file extension based on language
    let ext = match language {
        "gleam" => "gleam",
        "elm" => "elm",
        "python" => "py",
        _ => {
            return Err(CliError::Validation {
                message: format!("Unknown language: {}", language),
            }
            .into());
        }
    };

    // Walk directory and collect files
    for entry in walkdir::WalkDir::new(input_path) {
        let entry = entry?;
        if entry.file_type().is_file()
            && let Some(file_ext) = entry.path().extension()
            && file_ext == ext
        {
            files.push(entry.path().to_string_lossy().to_string());
        }
    }

    Ok(files)
}

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use morphir_common::config::model::MorphirConfig;
    use morphir_daemon::DaemonError;
    use morphir_daemon::extensions::{
        ExpectedExtension, MepTransport, Session, TransportError, TransportState,
        protocol::{ExtensionRequest, ExtensionResponse, InitializeResult},
    };
    use morphir_extension_sdk::{
        Diagnostic as ExtensionDiagnostic, ExtensionCapabilities, ExtensionInfo,
        FrontendCapability, LanguageCapability,
    };
    use std::sync::{Arc, Mutex};
    use tempfile::TempDir;

    const ELM_SOURCE: &str = "module Example exposing (add)\n\nadd left right = left + right\n";

    #[test]
    fn infers_elm_from_the_input_extension() {
        assert_eq!(
            infer_language(Path::new("Example.elm"), None).unwrap(),
            "elm"
        );
    }

    #[test]
    fn an_explicit_language_takes_precedence_over_the_extension() {
        assert_eq!(
            infer_language(Path::new("Example.txt"), Some("elm")).unwrap(),
            "elm"
        );
    }

    #[test]
    fn dispatcher_keeps_explicit_gleam_on_the_legacy_path_despite_elm_suffix() {
        let options = CompileOptions {
            language: Some("gleam".into()),
            input: Some("Example.elm".into()),
            config_path: Some("morphir.toml".into()),
            ..CompileOptions::default()
        };

        assert!(!should_use_single_file_process(&options));
    }

    #[test]
    fn dispatcher_normalizes_explicit_elm_and_ignores_the_input_suffix() {
        let options = CompileOptions {
            language: Some(" Elm ".into()),
            input: Some("Example.txt".into()),
            config_path: Some("morphir.toml".into()),
            ..CompileOptions::default()
        };

        assert!(should_use_single_file_process(&options));
    }

    #[test]
    fn uppercase_elm_extension_routes_and_prepares_without_a_language_override() {
        let input = std::env::current_dir().unwrap().join("Example.ELM");
        let options = CompileOptions {
            input: Some(input.display().to_string()),
            config_path: Some("morphir.toml".into()),
            ..CompileOptions::default()
        };

        assert!(should_use_single_file_process(&options));

        let context = prepare_single_file_context(
            std::slice::from_ref(&input),
            ELM_SOURCE,
            None,
            None,
            PathBuf::from("morphir-ir.json"),
        )
        .unwrap();

        assert_eq!(context.language_id, "elm");
        assert_eq!(context.document.language_id, "elm");
    }

    #[test]
    fn extracts_plain_port_and_effect_module_declarations_after_nested_comments() {
        let cases = [
            (
                "{- outer {- nested -} comment -}\nmodule Example.Core exposing (add)\n",
                "Example.Core",
            ),
            (
                "-- generated\nport {- bridge -} module App.Ports exposing (send)\n",
                "App.Ports",
            ),
            (
                "{- generated -}\neffect module App.Effect where { command = Command } exposing (..)",
                "App.Effect",
            ),
        ];

        for (source, expected) in cases {
            assert_eq!(elm_module_name(source).unwrap(), expected);
        }
    }

    #[test]
    fn prepares_a_single_file_with_synthesized_package_and_file_uri() {
        let input = std::env::current_dir().unwrap().join("Example.elm");
        let output = PathBuf::from("out/morphir-ir.json");

        let context = prepare_single_file_context(
            std::slice::from_ref(&input),
            ELM_SOURCE,
            None,
            None,
            output.clone(),
        )
        .unwrap();

        assert_eq!(context.language_id, "elm");
        assert_eq!(context.document.language_id, "elm");
        assert_eq!(context.document.version, 1);
        assert_eq!(context.document.text, ELM_SOURCE);
        assert!(context.document.uri.starts_with("file://"));
        assert!(context.document.uri.ends_with("/Example.elm"));
        assert_eq!(context.package.name, "local/example");
        assert_eq!(context.package.exposed_modules, ["Example"]);
        assert_eq!(context.output_path, output);
    }

    #[test]
    fn windows_drive_file_uri_is_absolute_and_percent_encoded() {
        assert_eq!(
            windows_file_uri(r"C:\Work Files\Example.elm").unwrap(),
            "file:///C:/Work%20Files/Example.elm"
        );
    }

    #[test]
    fn windows_unc_file_uri_uses_the_server_as_authority() {
        assert_eq!(
            windows_file_uri(r"\\server\shared files\Example.elm").unwrap(),
            "file://server/shared%20files/Example.elm"
        );
    }

    #[test]
    fn unix_file_uri_preserves_root_and_percent_encodes_segments() {
        assert_eq!(
            unix_file_uri("/work files/Example.elm").unwrap(),
            "file:///work%20files/Example.elm"
        );
    }

    #[test]
    fn explicit_package_name_overrides_the_synthesized_name() {
        let input = std::env::current_dir().unwrap().join("Example.elm");
        let context = prepare_single_file_context(
            &[input],
            ELM_SOURCE,
            Some("elm"),
            Some("acme/orders"),
            PathBuf::from("morphir-ir.json"),
        )
        .unwrap();

        assert_eq!(context.package.name, "acme/orders");
    }

    #[test]
    fn writes_a_typed_classic_distribution_that_round_trips() {
        let directory = TempDir::new().unwrap();
        let output_path = directory.path().join("nested/morphir-ir.json");
        let distribution: morphir_core::ir::classic::Distribution =
            serde_json::from_value(serde_json::json!({
                "formatVersion": 3,
                "distribution": [
                    "Library",
                    [["local"], ["example"]],
                    [],
                    {"modules": []}
                ]
            }))
            .unwrap();

        write_distribution(&output_path, &distribution).unwrap();

        let decoded: morphir_core::ir::classic::Distribution =
            serde_json::from_slice(&std::fs::read(output_path).unwrap()).unwrap();
        assert_eq!(decoded, distribution);
    }

    #[test]
    fn successful_result_rejects_error_diagnostics() {
        let directory = TempDir::new().unwrap();
        let context = example_context_with_output(directory.path().join("morphir-ir.json"));
        let mut result = example_compile_result(vec!["Example".into()]);
        result.diagnostics.push(ExtensionDiagnostic {
            severity: DiagnosticSeverity::Error,
            code: Some("elm.error".into()),
            message: "not actually successful".into(),
            location: None,
            related: Vec::new(),
        });

        let error = validate_compile_success(&context, &result).unwrap_err();

        assert!(error.to_string().contains("error diagnostic"));
        assert!(!context.output_path.exists());
    }

    #[test]
    fn successful_result_requires_the_expected_module() {
        let directory = TempDir::new().unwrap();
        let context = example_context_with_output(directory.path().join("morphir-ir.json"));
        let result = example_compile_result(Vec::new());

        let error = validate_compile_success(&context, &result).unwrap_err();

        assert!(error.to_string().contains("Example"));
        assert!(!context.output_path.exists());
    }

    #[test]
    fn successful_result_rejects_a_misreported_module() {
        let directory = TempDir::new().unwrap();
        let context = example_context_with_output(directory.path().join("morphir-ir.json"));
        let result = example_compile_result(vec!["Other".into()]);

        let error = validate_compile_success(&context, &result).unwrap_err();

        assert!(error.to_string().contains("Example"));
        assert!(error.to_string().contains("Other"));
        assert!(!context.output_path.exists());
    }

    #[test]
    fn successful_result_rejects_reported_module_absent_from_typed_ir() {
        let directory = TempDir::new().unwrap();
        let context = example_context_with_output(directory.path().join("morphir-ir.json"));
        let mut result = example_compile_result(vec!["Example".into()]);
        result.ir.as_mut().unwrap()["distribution"][3]["modules"] = serde_json::json!([]);

        let error = validate_compile_success(&context, &result).unwrap_err();

        assert!(error.to_string().contains("Example"));
        assert!(error.to_string().contains("IR"));
        assert!(!context.output_path.exists());
    }

    #[test]
    fn successful_result_rejects_reported_modules_not_present_in_typed_ir() {
        let directory = TempDir::new().unwrap();
        let context = example_context_with_output(directory.path().join("morphir-ir.json"));
        let result = example_compile_result(vec!["Example".into(), "Other".into()]);

        let error = validate_compile_success(&context, &result).unwrap_err();

        assert!(error.to_string().contains("Other"));
        assert!(error.to_string().contains("IR"));
        assert!(!context.output_path.exists());
    }

    #[test]
    fn successful_result_rejects_a_typed_ir_package_mismatch() {
        let directory = TempDir::new().unwrap();
        let context = example_context_with_output(directory.path().join("morphir-ir.json"));
        let mut result = example_compile_result(vec!["Example".into()]);
        result.ir.as_mut().unwrap()["distribution"][1] =
            serde_json::json!([["stale"], ["package"]]);

        let error = validate_compile_success(&context, &result).unwrap_err();

        assert!(error.to_string().contains("local/example"));
        assert!(error.to_string().contains("stale.package"));
        assert!(!context.output_path.exists());
    }

    #[tokio::test]
    async fn invalid_frontend_capabilities_trigger_orderly_shutdown() {
        let state = Arc::new(Mutex::new(MockTransportState::default()));
        let transport = CapabilityTransport {
            state: Arc::clone(&state),
            fail_termination: false,
        };
        let ready = Session::loaded(transport)
            .initialize(initialize_params())
            .await
            .unwrap_or_else(|failure| panic!("initialization failed: {}", failure.error()));

        let error = validate_frontend_session(ready, "elm")
            .await
            .err()
            .expect("Gleam-only capability should fail");

        assert!(error.to_string().contains("advertise Elm"));
        let state = state.lock().unwrap();
        assert_eq!(
            state.methods,
            [
                methods::INITIALIZE.to_string(),
                methods::SHUTDOWN.to_string()
            ]
        );
        assert!(state.terminated);
    }

    #[tokio::test]
    async fn capability_error_retains_cleanup_failure_context() {
        let state = Arc::new(Mutex::new(MockTransportState::default()));
        let transport = CapabilityTransport {
            state,
            fail_termination: true,
        };
        let ready = Session::loaded(transport)
            .initialize(initialize_params())
            .await
            .unwrap_or_else(|failure| panic!("initialization failed: {}", failure.error()));

        let error = validate_frontend_session(ready, "elm")
            .await
            .err()
            .expect("Gleam-only capability should fail");
        let message = error.to_string();

        assert!(message.contains("advertise Elm"));
        assert!(message.contains("shutdown also failed"));
        assert!(message.contains("mock termination failed"));
    }

    #[test]
    fn rejects_directories_and_multiple_inputs_in_the_single_file_slice() {
        let directory = TempDir::new().unwrap();
        let directory_error = read_single_source(directory.path()).unwrap_err();
        assert!(directory_error.to_string().contains("single source file"));

        let multiple_error = prepare_single_file_context(
            &[PathBuf::from("One.elm"), PathBuf::from("Two.elm")],
            ELM_SOURCE,
            Some("elm"),
            None,
            PathBuf::from("morphir-ir.json"),
        )
        .unwrap_err();
        assert!(multiple_error.to_string().contains("exactly one"));
    }

    #[test]
    fn resolves_the_configured_command_and_arguments_against_the_config_directory() {
        let directory = TempDir::new().unwrap();
        let config: MorphirConfig = toml::from_str(
            r#"
[extensions.morphir-elm]
command = "bin/morphir-elm-extension"
args = ["--stdio"]
enabled = true
"#,
        )
        .unwrap();
        let config_dir = directory.path();
        let expected_program = config_dir.join("bin/morphir-elm-extension");

        let environment = [(
            OsString::from("TASK10_TEST_ENV"),
            OsString::from("explicit-value"),
        )];
        let process = configured_process(&config, "elm", config_dir, &environment).unwrap();
        let debug = format!("{process:?}");

        assert!(debug.contains("morphir-elm"));
        assert!(debug.contains(&expected_program.to_string_lossy().into_owned()));
        assert!(debug.contains("--stdio"));
        assert!(debug.contains(&config_dir.to_string_lossy().into_owned()));
        assert!(debug.contains("TASK10_TEST_ENV"));
        assert!(debug.contains("explicit-value"));
    }

    #[test]
    fn missing_configured_command_names_the_required_config_key() {
        let config = MorphirConfig::default();

        let error =
            configured_process(&config, "elm", Path::new("/workspace/project"), &[]).unwrap_err();

        assert!(
            error
                .to_string()
                .contains("[extensions.morphir-elm].command")
        );
    }

    #[test]
    fn enabled_extension_without_a_command_names_the_required_config_key() {
        let config: MorphirConfig = toml::from_str(
            r#"
[extensions.morphir-elm]
enabled = true
"#,
        )
        .unwrap();

        let error =
            configured_process(&config, "elm", Path::new("/workspace/project"), &[]).unwrap_err();

        assert!(
            error
                .to_string()
                .contains("[extensions.morphir-elm].command")
        );
    }

    #[test]
    fn enabled_extension_with_a_blank_command_names_the_required_config_key() {
        let config: MorphirConfig = toml::from_str(
            r#"
[extensions.morphir-elm]
command = "   "
enabled = true
"#,
        )
        .unwrap();

        let error =
            configured_process(&config, "elm", Path::new("/workspace/project"), &[]).unwrap_err();

        assert!(
            error
                .to_string()
                .contains("[extensions.morphir-elm].command")
        );
    }

    fn example_context_with_output(output_path: PathBuf) -> SingleFileCompileContext {
        SingleFileCompileContext {
            language_id: "elm".into(),
            document: SourceDocument {
                uri: "file:///work/Example.elm".into(),
                language_id: "elm".into(),
                version: 1,
                text: ELM_SOURCE.into(),
            },
            package: CompilePackage {
                name: "local/example".into(),
                exposed_modules: vec!["Example".into()],
            },
            output_path,
        }
    }

    fn example_compile_result(modules: Vec<String>) -> CompileResult {
        CompileResult {
            success: true,
            ir_version: Some("3".into()),
            ir: Some(serde_json::json!({
                "formatVersion": 3,
                "distribution": [
                    "Library",
                    [["local"], ["example"]],
                    [],
                    {
                        "modules": [
                            [
                                [["example"]],
                                {
                                    "access": "Public",
                                    "value": {
                                        "types": [],
                                        "values": []
                                    }
                                }
                            ]
                        ]
                    }
                ]
            })),
            diagnostics: Vec::new(),
            modules,
        }
    }

    #[derive(Default)]
    struct MockTransportState {
        methods: Vec<String>,
        terminated: bool,
    }

    struct CapabilityTransport {
        state: Arc<Mutex<MockTransportState>>,
        fail_termination: bool,
    }

    #[async_trait]
    impl MepTransport for CapabilityTransport {
        fn expected_extension(&self) -> ExpectedExtension {
            ExpectedExtension::identified("morphir-elm")
        }

        async fn exchange(
            &mut self,
            request: ExtensionRequest,
        ) -> std::result::Result<ExtensionResponse, TransportError> {
            self.state
                .lock()
                .unwrap()
                .methods
                .push(request.method.clone());
            let result = match request.method.as_str() {
                methods::INITIALIZE => serde_json::to_value(InitializeResult {
                    protocol_version: MEP_VERSION.into(),
                    extension: ExtensionInfo {
                        id: "morphir-elm".into(),
                        name: "Mock frontend".into(),
                        version: "1.0.0".into(),
                        types: vec![ExtensionType::Frontend],
                        ..ExtensionInfo::default()
                    },
                    capabilities: ExtensionCapabilities {
                        frontend: Some(FrontendCapability {
                            languages: vec![LanguageCapability {
                                id: "gleam".into(),
                                file_extensions: vec![".gleam".into()],
                            }],
                            ir_versions: vec!["3".into()],
                            compile: true,
                            incremental: false,
                            fragments: false,
                        }),
                        ..ExtensionCapabilities::default()
                    },
                })
                .unwrap(),
                methods::SHUTDOWN => serde_json::Value::Null,
                method => panic!("unexpected mock method {method}"),
            };
            Ok(ExtensionResponse::success(request.id, result).unwrap())
        }

        async fn terminate(&mut self) -> std::result::Result<TransportState, TransportError> {
            if self.fail_termination {
                return Err(TransportError::new(
                    DaemonError::Extension("mock termination failed".into()),
                    TransportState::Indeterminate,
                ));
            }
            self.state.lock().unwrap().terminated = true;
            Ok(TransportState::Stopped)
        }
    }

    fn initialize_params() -> InitializeParams {
        InitializeParams {
            protocol_versions: vec![MEP_VERSION.into()],
            host: PeerInfo {
                name: "test-host".into(),
                version: "1.0.0".into(),
            },
        }
    }
}

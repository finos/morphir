//! Compile command for compiling source code to Morphir IR

use crate::commands::out_context::{OutContext, OutOverrides, report_config_warnings};
use crate::error::CliError;
use crate::error::convert_extension_diagnostics;
use crate::home::MorphirHome;
use morphir_common::config::model::MorphirConfig;
use morphir_core::format_version::{
    NormalizedFormatVersion, ReleaseTriplet, ScalarValue, SupportTable,
};
use morphir_daemon::DaemonError;
use morphir_daemon::extensions::{
    InvokeOutcome, MepTransport, PersistedExtensionCapabilities, ProcessLaunch, Ready, Session,
    SpawnedProcessSession, protocol::methods,
};
use morphir_devkit::{
    TaskId, TaskResult, discover_config, ensure_morphir_structure, load_config_context,
    resolve_path_relative_to_config,
};
use morphir_distribution::{ExtensionId, VerifiedExtensionArtifact, activate_installed};
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
    /// Extension provider id for single-file Elm compilation. Defaults to morphir- followed by the language name.
    pub extension: Option<String>,
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
    /// Out root overrides.
    pub out: OutOverrides,
}

/// Run the compile command
pub async fn run_compile(options: CompileOptions) -> AppResult<miette::Report> {
    if should_use_single_file_process(&options) {
        return run_single_file_compile(options).await;
    }

    if options.extension.is_some() {
        return Err(CliError::Validation {
            message: "Explicit extension selection currently requires single-file Elm compilation"
                .into(),
        }
        .into());
    }

    run_provider_compile(options).await
}

fn should_use_single_file_process(options: &CompileOptions) -> bool {
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

fn resolve_extension_id(language: &str, explicit: Option<&str>) -> Result<ExtensionId, CliError> {
    let value = explicit
        .map(str::to_owned)
        .unwrap_or_else(|| format!("morphir-{language}"));
    ExtensionId::parse(value).map_err(|error| CliError::Extension {
        message: format!("Invalid extension id: {error}"),
    })
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
    let normalized = if let Some(network_path) = path.strip_prefix(r"\\?\UNC\") {
        format!("//{}", network_path.replace('\\', "/"))
    } else if let Some(drive_path) = path.strip_prefix(r"\\?\") {
        drive_path.replace('\\', "/")
    } else {
        path.replace('\\', "/")
    };
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
    extension_id: &ExtensionId,
    config_dir: &Path,
    environment: &[(OsString, OsString)],
) -> Result<ProcessLaunch, CliError> {
    let key = format!("[extensions.{extension_id}].command");
    let spec = config
        .extensions
        .get(extension_id.as_str())
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
        ProcessLaunch::new(extension_id.as_str(), program, config_dir),
        |launch, arg| launch.arg(arg),
    );
    Ok(environment
        .iter()
        .fold(launch, |launch, (key, value)| launch.env(key, value)))
}

fn installed_process(
    home: &MorphirHome,
    id: &ExtensionId,
    working_directory: &Path,
    environment: &[(OsString, OsString)],
) -> Result<ProcessLaunch, CliError> {
    let artifact = activate_installed(home, id).map_err(|error| CliError::Extension {
        message: format!("Failed to activate installed extension '{id}': {error}"),
    })?;
    let process = match artifact {
        VerifiedExtensionArtifact::Process(process) => process,
        VerifiedExtensionArtifact::Wasm(_) => {
            return Err(CliError::Extension {
                message: format!(
                    "Installed WASM extension '{id}' cannot compile through the process runtime"
                ),
            });
        }
    };
    let capabilities = process.extension_capabilities();
    let persisted_capabilities =
        PersistedExtensionCapabilities::new(capabilities.frontend, capabilities.backend);
    let launch = if process.frontend().is_some() || process.backend().is_some() {
        ProcessLaunch::from_verified_bytes_with_persisted_capabilities_in(
            process.extension_info().clone(),
            persisted_capabilities,
            process.filename(),
            process.bytes(),
            process.staging_directory(),
            working_directory,
        )
    } else {
        ProcessLaunch::from_verified_bytes_in(
            process.extension_info().clone(),
            process.filename(),
            process.bytes(),
            process.staging_directory(),
            working_directory,
        )
    };
    let launch = process
        .args()
        .iter()
        .fold(launch, |launch, argument| launch.arg(argument));
    Ok(environment
        .iter()
        .fold(launch, |launch, (key, value)| launch.env(key, value)))
}

fn compile_process(
    config: Option<(&MorphirConfig, &Path)>,
    extension_id: &ExtensionId,
    working_directory: &Path,
    home: &MorphirHome,
    environment: &[(OsString, OsString)],
) -> Result<ProcessLaunch, CliError> {
    if let Some((config, config_dir)) = config
        && config
            .extensions
            .get(extension_id.as_str())
            .is_some_and(|spec| spec.enabled && spec.command.is_some())
    {
        return configured_process(config, extension_id, config_dir, environment);
    }
    installed_process(home, extension_id, working_directory, environment)
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
    let config_path = options
        .config_path
        .as_deref()
        .map(Path::new)
        .map(|path| absolute_from(&start_dir, path));
    let config_context = config_path
        .as_deref()
        .map(load_config_context)
        .transpose()
        .map_err(|error| CliError::Config { error })?;
    let config_dir = config_path.as_deref().and_then(Path::parent);
    let source = read_single_source(&input_path)?;
    if let Some(context) = config_context.as_ref() {
        report_config_warnings(context);
    }
    let out = OutContext::resolve(config_context.as_ref(), &options.out, &start_dir);
    let task = TaskId::compile();
    let prepared = out.prepare_dest(&task)?;
    let paths = prepared.paths;
    let output_path = paths.dest.join("morphir-ir.json");
    let context = prepare_single_file_context(
        std::slice::from_ref(&input_path),
        &source,
        options.language.as_deref(),
        options.package_name.as_deref(),
        output_path,
    )?;
    let environment = filtered_process_environment();
    let home = MorphirHome::resolve().map_err(|error| CliError::Config { error })?;
    let extension_id = resolve_extension_id(&context.language_id, options.extension.as_deref())?;
    let launch = compile_process(
        config_context
            .as_ref()
            .zip(config_dir)
            .map(|(context, directory)| (&context.config, directory)),
        &extension_id,
        config_dir.unwrap_or(&start_dir),
        &home,
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
            ejected_path: None,
        };
        write_compile_output(format, &output)?;
        return Ok(Some(1));
    }

    let distribution = validate_compile_success(&context, &compile_result)?;
    write_distribution(&context.output_path, &distribution)?;
    let typed_ir = serde_json::to_value(&distribution).map_err(|error| CliError::Extension {
        message: format!("Failed to serialize validated classic Morphir IR: {error}"),
    })?;
    let mut record = TaskResult::new(&task, &out.module);
    record.language = Some(context.language_id.clone());
    let descriptor = crate::commands::ir_storage::v3_json_descriptor();
    record.value = vec![descriptor.path.clone()];
    record.ir = Some(descriptor);
    record.ejected = prepared.previous_ejected;
    record
        .write(&paths.result)
        .map_err(|error| CliError::Config { error })?;
    let ejected_path =
        crate::commands::eject::maybe_eject(&paths, options.output.as_deref(), &start_dir)?;
    let output = CompileOutput {
        success: true,
        ir: Some(typed_ir),
        diagnostics,
        modules: compile_result.modules,
        output_path: context.output_path.to_string_lossy().into_owned(),
        ejected_path,
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
                if let Some(ejected) = &output.ejected_path {
                    eprintln!("Ejected: {ejected}");
                }
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

async fn run_provider_compile(options: CompileOptions) -> AppResult<miette::Report> {
    use crate::output::{CompileOutput, OutputFormat};

    let CompileOptions {
        language,
        extension: _,
        input,
        output,
        package_name,
        config_path,
        project: _project,
        json,
        json_lines,
        out: out_overrides,
    } = options;
    let start_dir = std::env::current_dir().map_err(|error| CliError::FileSystem { error })?;
    let config_file = if let Some(config) = config_path {
        PathBuf::from(config)
    } else {
        discover_config(&start_dir)
            .map_err(|error| CliError::Config { error })?
            .ok_or_else(|| CliError::Config {
                error: anyhow::anyhow!("No morphir.toml, morphir.yaml, or morphir.json found"),
            })?
    };
    let context = load_config_context(&config_file).map_err(|error| CliError::Config { error })?;
    ensure_morphir_structure(&context.morphir_dir).map_err(|error| CliError::Config { error })?;
    let language = language
        .or_else(|| {
            context
                .config
                .frontend
                .as_ref()
                .and_then(|frontend| frontend.language.clone())
        })
        .ok_or_else(|| CliError::Config {
            error: anyhow::anyhow!("Language not specified and not found in config"),
        })?;
    let package_name = package_name
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
    let input_path = if let Some(input) = input {
        absolute_from(&start_dir, Path::new(&input))
    } else {
        let configured = context
            .config
            .project
            .as_ref()
            .map(|project| PathBuf::from(&project.source_directory))
            .or_else(|| {
                context.config.frontend.as_ref().and_then(|frontend| {
                    frontend
                        .settings
                        .get("source_directory")
                        .and_then(|value| value.as_str())
                        .map(PathBuf::from)
                })
            })
            .unwrap_or_else(|| PathBuf::from("src"));
        resolve_path_relative_to_config(&configured, &context.config_path)
    };
    report_config_warnings(&context);
    let out = OutContext::resolve(Some(&context), &out_overrides, &start_dir);
    let task = TaskId::compile();
    let prepared = out.prepare_dest(&task)?;
    let paths = prepared.paths;
    let storage = crate::commands::ir_storage::IrStorage::from_config(context.config.ir.as_ref())?;
    let output_path = paths.dest.join(storage.relative_path());
    let (documents, source_root_uri) = collect_source_documents(&input_path, &language)?;
    let emit_parse_stage = context
        .config
        .frontend
        .as_ref()
        .map(|frontend| frontend.emit_parse_stage)
        .unwrap_or(true);
    let emit_parse_stage_fatal = context
        .config
        .frontend
        .as_ref()
        .map(|frontend| frontend.emit_parse_stage_fatal)
        .unwrap_or(false);
    let home = MorphirHome::resolve().map_err(|error| CliError::Config { error })?;
    let installed =
        morphir_distribution::list_installed(&home).map_err(|error| CliError::Extension {
            message: format!("Failed to list installed frontend providers: {error}"),
        })?;
    let registry = crate::extensions::extension_registry(installed)?;
    let resolved = registry
        .resolve_frontend(
            &language,
            "4.0.0",
            morphir_daemon::InvocationPolicy::PreferDirect,
        )
        .map_err(|error| CliError::Extension {
            message: format!("Failed to resolve frontend for '{language}': {error}"),
        })?;
    let language_name = language.clone();
    let request = CompileRequest {
        language_id: language,
        documents,
        package: CompilePackage {
            name: package_name,
            exposed_modules: vec![],
        },
        dependencies: vec![],
        options: ExtensionCompileOptions {
            types_only: false,
            ir_version: "4.0.0".into(),
            extra: HashMap::from([
                ("outputDir".into(), serde_json::json!(paths.dest)),
                ("sourceRootUri".into(), serde_json::json!(source_root_uri)),
                ("emitParseStage".into(), serde_json::json!(emit_parse_stage)),
                (
                    "emitParseStageFatal".into(),
                    serde_json::json!(emit_parse_stage_fatal),
                ),
            ]),
        },
    };
    let workspace = context
        .project_root
        .as_deref()
        .or_else(|| context.config_path.parent())
        .unwrap_or(&start_dir);
    let result = crate::extensions::invoke_frontend(&home, workspace, &resolved, request).await?;
    let diagnostics = convert_extension_diagnostics(&result.diagnostics);
    let format = OutputFormat::from_flags(json, json_lines);
    let has_error = result
        .diagnostics
        .iter()
        .any(|diagnostic| diagnostic.severity == DiagnosticSeverity::Error);
    if !result.success || has_error {
        let output = CompileOutput {
            success: false,
            ir: None,
            diagnostics,
            modules: vec![],
            output_path: output_path.to_string_lossy().into_owned(),
            ejected_path: None,
        };
        let message = compilation_failure_message(&result);
        write_compile_output(format, &output)?;
        return Err(CliError::Compilation { message }.into());
    }
    let ir_file = validate_v4_compile_result(&result)?;
    let descriptor = crate::commands::ir_storage::write_v4(&paths.dest, &storage, &ir_file)?;
    let mut record = TaskResult::new(&task, &out.module);
    record.language = Some(language_name);
    record.value = vec![descriptor.path.clone()];
    record.ir = Some(descriptor);
    record.ejected = prepared.previous_ejected;
    record
        .write(&paths.result)
        .map_err(|error| CliError::Config { error })?;
    let ejected_path = crate::commands::eject::maybe_eject(&paths, output.as_deref(), &start_dir)?;
    let ir = serde_json::to_value(&ir_file).map_err(|error| CliError::Extension {
        message: format!("Failed to serialize validated Morphir IR v4: {error}"),
    })?;
    let output = CompileOutput {
        success: true,
        ir: Some(ir),
        diagnostics,
        modules: result.modules,
        output_path: output_path.to_string_lossy().into_owned(),
        ejected_path,
    };
    write_compile_output(format, &output)?;
    Ok(None)
}

fn collect_source_documents(
    input_path: &Path,
    language: &str,
) -> Result<(Vec<SourceDocument>, String), CliError> {
    let extension = language_file_extension(language)?;
    let input_error = |error: std::io::Error| match error.kind() {
        std::io::ErrorKind::NotFound => CliError::Validation {
            message: format!("Source input '{}' does not exist", input_path.display()),
        },
        _ => CliError::FileSystem { error },
    };
    let metadata = std::fs::metadata(input_path).map_err(input_error)?;
    let canonical_input = input_path.canonicalize().map_err(input_error)?;
    let source_root = if metadata.is_file() {
        canonical_input
            .parent()
            .ok_or_else(|| CliError::Validation {
                message: format!(
                    "Source file '{}' has no parent directory",
                    input_path.display()
                ),
            })?
    } else if metadata.is_dir() {
        canonical_input.as_path()
    } else {
        return Err(CliError::Validation {
            message: format!(
                "Source input '{}' must be a file or directory",
                input_path.display()
            ),
        });
    };
    let mut paths = if metadata.is_file() {
        canonical_input
            .extension()
            .is_some_and(|candidate| candidate == extension)
            .then_some(canonical_input.clone())
            .into_iter()
            .collect::<Vec<_>>()
    } else {
        walkdir::WalkDir::new(&canonical_input)
            .into_iter()
            .map(|entry| entry.map_err(std::io::Error::other))
            .collect::<Result<Vec<_>, _>>()?
            .into_iter()
            .filter(|entry| entry.file_type().is_file())
            .filter(|entry| {
                entry
                    .path()
                    .extension()
                    .is_some_and(|candidate| candidate == extension)
            })
            .map(|entry| {
                entry
                    .path()
                    .canonicalize()
                    .map_err(|error| CliError::FileSystem { error })
            })
            .collect::<Result<Vec<_>, _>>()?
    };
    paths.sort();
    if paths.is_empty() {
        return Err(CliError::Validation {
            message: format!(
                "The {language} source set is empty below '{}'",
                input_path.display()
            ),
        });
    }
    let documents = paths
        .into_iter()
        .map(|path| {
            let text =
                std::fs::read_to_string(&path).map_err(|error| CliError::FileSystem { error })?;
            Ok(SourceDocument {
                uri: file_uri(&path)?,
                language_id: language.to_owned(),
                version: 1,
                text,
            })
        })
        .collect::<Result<Vec<_>, CliError>>()?;
    Ok((documents, file_uri(source_root)?))
}

fn language_file_extension(language: &str) -> Result<&'static str, CliError> {
    match language {
        "gleam" => Ok("gleam"),
        "elm" => Ok("elm"),
        "python" => Ok("py"),
        _ => Err(CliError::Validation {
            message: format!("Unknown language: {language}"),
        }),
    }
}

fn compilation_failure_message(result: &CompileResult) -> String {
    let messages = result
        .diagnostics
        .iter()
        .filter(|diagnostic| diagnostic.severity == DiagnosticSeverity::Error)
        .map(|diagnostic| diagnostic.message.as_str())
        .collect::<Vec<_>>();
    if messages.is_empty() {
        "Compilation failed".into()
    } else {
        messages.join("; ")
    }
}

fn validate_v4_compile_result(
    result: &CompileResult,
) -> Result<morphir_core::ir::v4::IRFile, CliError> {
    let version = result
        .ir_version
        .as_deref()
        .ok_or_else(|| CliError::Compilation {
            message: "Frontend returned successful compilation without an IR version".into(),
        })?;
    if !is_semantic_v4(version) {
        return Err(CliError::Compilation {
            message: format!("Frontend returned unsupported Morphir IR version '{version}'"),
        });
    }
    let result_release = ReleaseTriplet::new(4, 0, 0);
    let ir = result.ir.as_ref().ok_or_else(|| CliError::Compilation {
        message: "Frontend returned successful compilation without Morphir IR".into(),
    })?;
    let ir_file: morphir_core::ir::v4::IRFile =
        serde_json::from_value(ir.clone()).map_err(|error| CliError::Compilation {
            message: format!("Frontend returned invalid Morphir IR v4: {error}"),
        })?;
    let embedded = ir_file
        .format_version
        .normalize()
        .map_err(|error| CliError::Compilation {
            message: format!("Frontend returned invalid embedded Morphir IR version: {error}"),
        })?;
    if !embedded.is_supported() {
        return Err(CliError::Compilation {
            message: format!(
                "Frontend returned unsupported embedded Morphir IR version '{}'",
                embedded.release
            ),
        });
    }
    if embedded.release != result_release {
        return Err(CliError::Compilation {
            message: format!(
                "Frontend returned embedded Morphir IR version '{}' did not match result/request version '{}'",
                embedded.release, result_release
            ),
        });
    }
    Ok(ir_file)
}

fn is_semantic_v4(version: &str) -> bool {
    normalize_ir_version_text(version).is_some_and(|normalized| {
        normalized.is_supported() && normalized.release == ReleaseTriplet::new(4, 0, 0)
    })
}

fn normalize_ir_version_text(version: &str) -> Option<NormalizedFormatVersion> {
    let scalar = if !version.is_empty() && version.bytes().all(|byte| byte.is_ascii_digit()) {
        ScalarValue::Integer(version.parse().ok()?)
    } else {
        ScalarValue::String(version.to_owned())
    };
    NormalizedFormatVersion::from_scalar(&scalar, &SupportTable::reference()).ok()
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
    fn compile_result_version_accepts_only_supported_v4_spellings() {
        assert!(is_semantic_v4("4"));
        assert!(is_semantic_v4("4.0.0"));
        assert!(!is_semantic_v4("4.0"));
        assert!(!is_semantic_v4("4.0.1"));
    }

    fn v4_compile_result(
        result_version: &str,
        embedded_version: serde_json::Value,
    ) -> CompileResult {
        CompileResult {
            success: true,
            ir_version: Some(result_version.into()),
            ir: Some(serde_json::json!({
                "formatVersion": embedded_version,
                "distribution": {
                    "Library": {
                        "packageName": "example/package",
                        "dependencies": {},
                        "def": {"modules": {}}
                    }
                }
            })),
            diagnostics: Vec::new(),
            modules: Vec::new(),
        }
    }

    #[test]
    fn direct_compile_accepts_numeric_and_canonical_embedded_v4_versions() {
        for embedded_version in [serde_json::json!(4), serde_json::json!("4.0.0")] {
            validate_v4_compile_result(&v4_compile_result("4", embedded_version))
                .expect("numeric and canonical embedded v4 versions are equivalent");
        }
    }

    #[test]
    fn direct_compile_rejects_an_unsupported_embedded_v4_revision() {
        let error =
            validate_v4_compile_result(&v4_compile_result("4.0.0", serde_json::json!("4.1.0")))
                .expect_err("unsupported embedded revisions must fail direct validation");

        assert!(
            error
                .to_string()
                .contains("unsupported embedded Morphir IR version '4.1.0'"),
            "{error}"
        );
    }

    #[test]
    fn direct_compile_rejects_an_embedded_version_mismatch() {
        let error = validate_v4_compile_result(&v4_compile_result("4.0.0", serde_json::json!(3)))
            .expect_err("embedded v3 must not pass as a v4 compile result");

        assert!(
            error
                .to_string()
                .contains("embedded Morphir IR version '3.0.0' did not match"),
            "{error}"
        );
    }

    fn extension_id(value: &str) -> ExtensionId {
        ExtensionId::parse(value).unwrap()
    }

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
    fn defaults_the_provider_to_the_language_extension() {
        let provider = resolve_extension_id("elm", None).unwrap();

        assert_eq!(provider.as_str(), "morphir-elm");
    }

    #[test]
    fn accepts_an_explicit_provider_distinct_from_the_language() {
        let provider = resolve_extension_id("elm", Some("morphir-scala-elm")).unwrap();

        assert_eq!(provider.as_str(), "morphir-scala-elm");
    }

    #[test]
    fn rejects_an_invalid_explicit_provider() {
        let error = resolve_extension_id("elm", Some("Morphir Scala Elm")).unwrap_err();

        assert!(
            error.to_string().contains("Invalid extension id"),
            "{error}"
        );
    }

    #[test]
    fn rejects_surrounding_whitespace_in_an_explicit_provider() {
        let error = resolve_extension_id("elm", Some(" morphir-scala-elm ")).unwrap_err();

        assert!(
            error.to_string().contains("Invalid extension id"),
            "{error}"
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
    fn dispatcher_routes_an_elm_file_without_project_metadata_to_the_installed_process() {
        let options = CompileOptions {
            input: Some("Example.elm".into()),
            ..CompileOptions::default()
        };

        assert!(should_use_single_file_process(&options));
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
    fn windows_verbatim_drive_file_uri_discards_the_verbatim_prefix() {
        assert_eq!(
            windows_file_uri(r"\\?\C:\Work Files\Example.elm").unwrap(),
            "file:///C:/Work%20Files/Example.elm"
        );
    }

    #[test]
    fn windows_verbatim_unc_file_uri_uses_the_server_as_authority() {
        assert_eq!(
            windows_file_uri(r"\\?\UNC\server\shared files\Example.elm").unwrap(),
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
        let process = configured_process(
            &config,
            &extension_id("morphir-elm"),
            config_dir,
            &environment,
        )
        .unwrap();
        let debug = format!("{process:?}");

        assert!(debug.contains("morphir-elm"));
        assert!(debug.contains(&format!("{expected_program:?}")));
        assert!(debug.contains("--stdio"));
        assert!(debug.contains(&format!("{config_dir:?}")));
        assert!(debug.contains("TASK10_TEST_ENV"));
        assert!(debug.contains("explicit-value"));
    }

    #[test]
    fn resolves_an_explicit_configured_provider_by_its_exact_id() {
        let directory = TempDir::new().unwrap();
        let config: MorphirConfig = toml::from_str(
            r#"
[extensions.morphir-scala-elm]
command = "bin/morphir-scala-elm"
enabled = true
"#,
        )
        .unwrap();

        let process = configured_process(
            &config,
            &extension_id("morphir-scala-elm"),
            directory.path(),
            &[],
        )
        .unwrap();
        let debug = format!("{process:?}");

        assert!(debug.contains("morphir-scala-elm"), "{debug}");
        assert!(debug.contains("bin/morphir-scala-elm"), "{debug}");
    }

    fn install_test_process_with_id(
        directory: &Path,
        extension_id: &str,
    ) -> (MorphirHome, PathBuf) {
        install_test_process_with_metadata(
            directory,
            extension_id,
            b"test process bytes",
            "elm",
            ".elm",
            "3",
        )
    }

    fn install_test_process_with_metadata(
        directory: &Path,
        extension_id: &str,
        bytes: &[u8],
        language: &str,
        file_extension: &str,
        ir_version: &str,
    ) -> (MorphirHome, PathBuf) {
        let home_path = directory.join("home");
        let home = MorphirHome::resolve_from(Some(home_path.as_os_str()), None).unwrap();
        let index_root = directory.join("index");
        let source_path = index_root.join("artifacts").join(extension_id);
        std::fs::create_dir_all(source_path.parent().unwrap()).unwrap();
        std::fs::create_dir_all(index_root.join("extensions")).unwrap();
        std::fs::write(&source_path, bytes).unwrap();
        let digest = morphir_distribution::Sha256Digest::of_bytes(bytes);
        let record = serde_json::json!({
            "schemaVersion": "1.0",
            "id": extension_id,
            "name": "Test Elm frontend",
            "version": "2.100.0",
            "channels": ["stable"],
            "mepVersions": ["0.1"],
            "capabilities": ["frontend"],
            "frontend": {
                "languages": [{"id": language, "fileExtensions": [file_extension]}],
                "irVersions": [ir_version],
                "compile": true,
            },
            "artifacts": [{
                "runtime": "process",
                "platform": {
                    "os": std::env::consts::OS,
                    "arch": std::env::consts::ARCH,
                },
                "source": {"kind": "local-file", "path": format!("artifacts/{extension_id}")},
                "sha256": digest.to_string(),
                "filename": extension_id,
                "executable": true,
            }],
        });
        std::fs::write(
            index_root
                .join("extensions")
                .join(format!("{extension_id}.jsonl")),
            format!("{record}\n"),
        )
        .unwrap();
        let id = morphir_distribution::ExtensionId::parse(extension_id).unwrap();
        let selected = morphir_distribution::LocalIndex::open(&index_root)
            .unwrap()
            .resolve(
                &id,
                morphir_distribution::Selection::Channel(morphir_distribution::Channel::Stable),
                &morphir_distribution::Platform::current(),
            )
            .unwrap();
        let installed = morphir_distribution::ExtensionInstaller::new(&home)
            .install(selected)
            .unwrap();
        (home.clone(), home.root().join(installed.store_path()))
    }

    #[cfg(unix)]
    fn elm_process_script(method_log: &Path) -> String {
        let python = std::process::Command::new("sh")
            .args(["-c", "command -v python3"])
            .output()
            .unwrap();
        assert!(python.status.success(), "python3 is required for this test");
        let python = String::from_utf8(python.stdout).unwrap();
        let initialize = serde_json::json!({
            "protocolVersion": "0.1",
            "extension": {
                "id": "morphir-elm",
                "name": "Test Elm frontend",
                "version": "2.100.0",
                "types": ["frontend"],
            },
            "capabilities": {
                "frontend": {
                    "languages": [{"id": "elm", "fileExtensions": [".elm"]}],
                    "irVersions": ["3"],
                    "compile": true,
                    "incremental": false,
                    "fragments": false,
                }
            },
        });
        let compile = serde_json::to_value(example_compile_result(vec!["Example".into()])).unwrap();
        let method_log = serde_json::to_string(&method_log.to_string_lossy()).unwrap();
        let initialize = serde_json::to_string(&initialize.to_string()).unwrap();
        let compile = serde_json::to_string(&compile.to_string()).unwrap();
        format!(
            r#"#!{python}
import json
import sys

METHOD_LOG = {method_log}
INITIALIZE_RESULT = json.loads({initialize})
COMPILE_RESULT = json.loads({compile})

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

def send(identifier, result):
    body = json.dumps(
        {{"jsonrpc": "2.0", "id": identifier, "result": result}},
        separators=(",", ":"),
    ).encode()
    sys.stdout.buffer.write(
        b"Content-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body
    )
    sys.stdout.buffer.flush()

while True:
    request = receive()
    method = request["method"]
    with open(METHOD_LOG, "a", encoding="utf-8") as log:
        log.write(method + "\n")
    if method == "morphir.initialize":
        result = INITIALIZE_RESULT
    elif method == "morphir.frontend.compile":
        result = COMPILE_RESULT
    elif method == "morphir.shutdown":
        result = {{}}
    elif method == "morphir.exit":
        break
    else:
        raise RuntimeError("unexpected method " + method)
    if "id" in request:
        send(request["id"], result)
"#,
            python = python.trim()
        )
    }

    fn install_test_process(directory: &Path) -> (MorphirHome, PathBuf) {
        install_test_process_with_id(directory, "morphir-elm")
    }

    fn install_test_wasm(directory: &Path) -> MorphirHome {
        let extension_id = "morphir-elm";
        let home_path = directory.join("home");
        let home = MorphirHome::resolve_from(Some(home_path.as_os_str()), None).unwrap();
        let index_root = directory.join("index");
        let source_path = index_root.join("artifacts/morphir-elm.wasm");
        std::fs::create_dir_all(source_path.parent().unwrap()).unwrap();
        std::fs::create_dir_all(index_root.join("extensions")).unwrap();
        let bytes = b"test wasm bytes";
        std::fs::write(&source_path, bytes).unwrap();
        let digest = morphir_distribution::Sha256Digest::of_bytes(bytes);
        let record = serde_json::json!({
            "schemaVersion": "1.0",
            "id": extension_id,
            "name": "Test Elm WASM frontend",
            "version": "2.100.0",
            "channels": ["stable"],
            "mepVersions": ["0.1"],
            "capabilities": ["frontend"],
            "frontend": {
                "languages": [{"id": "elm", "fileExtensions": [".elm"]}],
                "irVersions": ["3"]
            },
            "artifacts": [{
                "runtime": "wasm",
                "source": {"kind": "local-file", "path": "artifacts/morphir-elm.wasm"},
                "sha256": digest.to_string(),
                "filename": "morphir-elm.wasm",
            }],
        });
        std::fs::write(
            index_root.join("extensions/morphir-elm.jsonl"),
            format!("{record}\n"),
        )
        .unwrap();
        let id = morphir_distribution::ExtensionId::parse(extension_id).unwrap();
        let selected = morphir_distribution::LocalIndex::open(&index_root)
            .unwrap()
            .resolve(
                &id,
                morphir_distribution::Selection::Channel(morphir_distribution::Channel::Stable),
                &morphir_distribution::Platform::current(),
            )
            .unwrap();
        morphir_distribution::ExtensionInstaller::new(&home)
            .install(selected)
            .unwrap();
        home
    }

    #[test]
    fn installed_process_launch_carries_exact_discovered_metadata() {
        let directory = TempDir::new().unwrap();
        let (home, _) = install_test_process(directory.path());

        let process =
            installed_process(&home, &extension_id("morphir-elm"), directory.path(), &[]).unwrap();
        let debug = format!("{process:?}");

        assert!(debug.contains("discovered: Some"), "{debug}");
        assert!(debug.contains("morphir-elm"), "{debug}");
        assert!(debug.contains("2.100.0"), "{debug}");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn installed_process_rejects_persisted_frontend_drift_before_compile() {
        let directory = TempDir::new().unwrap();
        let method_log = directory.path().join("methods.log");
        let script = elm_process_script(&method_log);
        let (home, _) = install_test_process_with_metadata(
            directory.path(),
            "morphir-elm",
            script.as_bytes(),
            "test",
            ".test",
            "4",
        );
        let launch =
            installed_process(&home, &extension_id("morphir-elm"), directory.path(), &[]).unwrap();

        let error = invoke_frontend(
            launch,
            &example_context_with_output(directory.path().join("morphir-ir.json")),
        )
        .await
        .expect_err("persisted frontend drift must reject initialization");

        assert!(
            error
                .to_string()
                .contains("frontend capabilities disagreed with discovery"),
            "{error}"
        );
        let methods = std::fs::read_to_string(&method_log).unwrap();
        assert!(methods.contains("morphir.initialize"), "{methods}");
        assert!(!methods.contains("morphir.frontend.compile"), "{methods}");
    }

    #[cfg(unix)]
    #[tokio::test]
    async fn installed_process_accepts_exact_persisted_elm_frontend_metadata() {
        let directory = TempDir::new().unwrap();
        let method_log = directory.path().join("methods.log");
        let script = elm_process_script(&method_log);
        let (home, _) = install_test_process_with_metadata(
            directory.path(),
            "morphir-elm",
            script.as_bytes(),
            "elm",
            ".elm",
            "3",
        );
        let launch =
            installed_process(&home, &extension_id("morphir-elm"), directory.path(), &[]).unwrap();

        let result = invoke_frontend(
            launch,
            &example_context_with_output(directory.path().join("morphir-ir.json")),
        )
        .await
        .expect("matching persisted Elm metadata should compile");

        assert!(result.success);
        assert_eq!(result.modules, vec!["Example"]);
        let methods = std::fs::read_to_string(&method_log).unwrap();
        assert!(methods.contains("morphir.initialize"), "{methods}");
        assert!(methods.contains("morphir.frontend.compile"), "{methods}");
    }

    #[test]
    fn installed_process_activates_an_explicit_provider_by_its_exact_id() {
        let directory = TempDir::new().unwrap();
        let (home, _) = install_test_process_with_id(directory.path(), "morphir-scala-elm");

        let process = installed_process(
            &home,
            &extension_id("morphir-scala-elm"),
            directory.path(),
            &[],
        )
        .unwrap();
        let debug = format!("{process:?}");

        assert!(debug.contains("discovered: Some"), "{debug}");
        assert!(debug.contains("morphir-scala-elm"), "{debug}");
    }

    #[test]
    fn installed_process_rehashes_bytes_before_returning_a_launch() {
        let directory = TempDir::new().unwrap();
        let (home, installed_path) = install_test_process(directory.path());
        std::fs::write(installed_path, b"tampered after installation").unwrap();

        let error = installed_process(&home, &extension_id("morphir-elm"), directory.path(), &[])
            .unwrap_err();

        assert!(error.to_string().contains("digest"), "{error}");
    }

    #[test]
    fn installed_process_rejects_a_wasm_frontend() {
        let directory = TempDir::new().unwrap();
        let home = install_test_wasm(directory.path());

        let error = installed_process(&home, &extension_id("morphir-elm"), directory.path(), &[])
            .unwrap_err();

        assert!(
            error
                .to_string()
                .contains("cannot compile through the process runtime"),
            "{error}"
        );
    }

    #[test]
    fn explicit_configured_command_overrides_installed_discovery() {
        let directory = TempDir::new().unwrap();
        let config: MorphirConfig = toml::from_str(
            r#"
[extensions.morphir-elm]
command = "dev/morphir-elm-extension"
enabled = true
"#,
        )
        .unwrap();
        let home_path = directory.path().join("empty-home");
        let home = MorphirHome::resolve_from(Some(home_path.as_os_str()), None).unwrap();

        let process = compile_process(
            Some((&config, directory.path())),
            &extension_id("morphir-elm"),
            directory.path(),
            &home,
            &[],
        )
        .unwrap();
        let debug = format!("{process:?}");

        assert!(debug.contains("dev/morphir-elm-extension"), "{debug}");
        assert!(debug.contains("discovered: None"), "{debug}");
    }

    #[test]
    fn compile_process_selects_one_configured_provider_side_by_side() {
        let directory = TempDir::new().unwrap();
        let config: MorphirConfig = toml::from_str(
            r#"
[extensions.morphir-elm]
command = "dev/morphir-elm"
enabled = true

[extensions.morphir-scala-elm]
command = "dev/morphir-scala-elm"
enabled = true
"#,
        )
        .unwrap();
        let home =
            MorphirHome::resolve_from(Some(directory.path().join("empty-home").as_os_str()), None)
                .unwrap();

        let process = compile_process(
            Some((&config, directory.path())),
            &extension_id("morphir-scala-elm"),
            directory.path(),
            &home,
            &[],
        )
        .unwrap();
        let debug = format!("{process:?}");

        assert!(debug.contains("dev/morphir-scala-elm"), "{debug}");
        assert!(!debug.contains("program: \"dev/morphir-elm\""), "{debug}");
    }

    #[test]
    fn missing_configured_command_names_the_required_config_key() {
        let config = MorphirConfig::default();

        let error = configured_process(
            &config,
            &extension_id("morphir-elm"),
            Path::new("/workspace/project"),
            &[],
        )
        .unwrap_err();

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

        let error = configured_process(
            &config,
            &extension_id("morphir-elm"),
            Path::new("/workspace/project"),
            &[],
        )
        .unwrap_err();

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

        let error = configured_process(
            &config,
            &extension_id("morphir-elm"),
            Path::new("/workspace/project"),
            &[],
        )
        .unwrap_err();

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

//! Compile command for compiling source code to Morphir IR

mod cache;
mod elm_modes;
pub use elm_modes::Flags as ElmModeFlags;
mod elm_prelude;
/// Shared with the UI playground, which selects a provider from the same
/// configuration key but has no `--extension` flag to override it with.
pub(crate) mod frontend_extension;
mod frontend_settings;
mod prepare;
pub use prepare::{COMPILE_SCOPE_KEY, PreparedCompile, execute_compile, prepare_compile};

use crate::error::CliError;
use morphir_core::format_version::{
    NormalizedFormatVersion, ReleaseTriplet, ScalarValue, SupportTable,
};
use morphir_extension_sdk::{
    CompileOptions as ExtensionCompileOptions, CompileResult, DiagnosticSeverity,
};
use starbase::AppResult;
use std::path::{Path, PathBuf};

mod version;
#[cfg(test)]
use morphir_common::config::model::IrSection;
use morphir_common::ir_transport::IrVersion;
pub use version::parse_ir_version;
#[cfg(test)]
use version::selected_ir_version;

/// Options for the compile command
#[derive(Debug, Default)]
pub struct CompileOptions {
    /// Language to compile (e.g., "gleam", "elm")
    pub language: Option<String>,
    /// Extension id that provides the language (for example `morphir-elm-native`);
    /// overrides `[frontend.<language>] extension`, and defaults to the
    /// language's default provider
    pub extension: Option<String>,
    /// Source inputs: files select exactly those sources, a directory replaces
    /// the project's source directory.
    pub input: Vec<String>,
    /// Output path
    pub output: Option<String>,
    /// Package name override
    pub package_name: Option<String>,
    /// Path to configuration file
    pub config_path: Option<String>,
    /// Declared workspace-relative member path or exact project name
    pub project: Option<String>,
    /// Override the project's IR format version.
    pub ir_version: Option<IrVersion>,
    /// Output JSON format
    pub json: bool,
    /// Output JSON lines format
    pub json_lines: bool,
    /// Ignore the workspace's incremental compile cache for this run.
    pub no_cache: bool,
    /// Elm compatibility modes from the command line, which override
    /// `[frontend.elm]` and the environment. See [`elm_modes`].
    pub elm_modes: elm_modes::Flags,
    /// Out root overrides.
    pub out: crate::commands::out_context::OutOverrides,
}

/// Run the compile the session's `startup` phase prepared.
pub async fn run_compile(ready: &crate::SessionReady) -> AppResult<miette::Report> {
    let prepared = ready.take_compile().ok_or_else(|| CliError::Config {
        error: anyhow::anyhow!("compile ran without a compile prepared by the startup phase"),
    })?;
    execute_compile(prepared).await
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

pub(crate) fn absolute_from(base: &Path, path: &Path) -> PathBuf {
    if path.is_absolute() {
        path.to_path_buf()
    } else {
        base.join(path)
    }
}

/// Carries a `--extension`-overriding-a-malformed-key warning into the
/// output's diagnostics, for `--json` and `--json-lines`, which have no other
/// place for the CLI to say anything: their stdout is the envelope, so a
/// warning that only went to stderr would be invisible to a caller that reads
/// JSON. The human format has no such gap — [`write_compile_output`] already
/// writes every diagnostic to stderr — so nothing is added there, or this
/// warning would print twice.
fn prepend_config_warnings(
    diagnostics: &mut Vec<crate::output::Diagnostic>,
    warnings: &[String],
    format: crate::output::OutputFormat,
) {
    use crate::output::{Diagnostic, OutputFormat};

    // A human run has already read these on stderr, where warnings belong;
    // repeating them in the rendered output would say everything twice.
    if warnings.is_empty() || matches!(format, OutputFormat::Human) {
        return;
    }
    for (index, warning) in warnings.iter().enumerate() {
        diagnostics.insert(
            index,
            Diagnostic {
                level: "warning".to_string(),
                message: warning.clone(),
                code: None,
                related: Vec::new(),
                file: None,
                line: None,
                column: None,
                uri: None,
                range: None,
            },
        );
    }
}

/// Every configuration warning a run raised, in the order a reader meets
/// them: the provider it chose, then the modes it compiled under.
fn config_warnings(extension: Option<&str>, modes: &[String]) -> Vec<String> {
    extension
        .map(str::to_owned)
        .into_iter()
        .chain(modes.iter().cloned())
        .collect()
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
                if let Some(installed) = &output.installed_path {
                    eprintln!("Installed: {installed}");
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

/// Whether the resolved provider accepts `CompileRequest.baseline` and answers
/// with `CompileResult.moduleResults`.
///
/// The registry normalizes one frontend capability per resolved provider from
/// whichever source describes it — a builtin's [`NativeExtension`] metadata for
/// a native-direct provider, the discovered and persisted metadata an installed
/// MEP provider was registered with — so both kinds are read the same way here,
/// exactly as `validate_frontend_capabilities` reads the negotiated capability
/// once a session exists.
///
/// [`NativeExtension`]: morphir_extension_sdk::NativeExtension
fn provider_supports_incremental(resolved: &morphir_daemon::ResolvedFrontend) -> bool {
    resolved.capability().incremental
}

/// The key this run's results are cached under.
///
/// The compile context — IR version, `typesOnly`, prelude, and dependency
/// interfaces — is no longer part of the key: an incremental extension now
/// computes its own digest of that context and returns it as
/// `CompileResult.context_digest`, which the cache stores and echoes back as
/// `CompileBaseline.context_digest`. The extension, not the CLI, decides
/// whether a baseline's context digest still matches, so the key here only
/// needs to name the provider and the shape of what it was asked for.
fn cache_key(
    resolved: &morphir_daemon::ResolvedFrontend,
    options: &ExtensionCompileOptions,
) -> cache::CacheKey {
    cache::CacheKey {
        extension_id: resolved.info().id.clone(),
        extension_version: resolved.info().version.clone(),
        ir_version: options.ir_version.clone(),
        types_only: options.types_only,
    }
}

/// Whether this run's result is worth writing to the cache.
///
/// A run that reported success, or that reported at least one module result,
/// learned something worth remembering. A whole-request rejection — the
/// provider's `validate()`-style refusal of the request itself, such as an
/// unrecognised package name — reports neither: `success: false` and an empty
/// `module_results`. That combination carries no information about any
/// module, so writing it would empty a cache that a previous, genuinely
/// productive run had built, and the next run would recompile everything for
/// no reason connected to the sources at all.
fn cache_write_is_warranted(result: &morphir_extension_sdk::CompileResult) -> bool {
    result.success || !result.module_results.is_empty()
}

/// Record a compile's per-module results, reporting a cache that could not be
/// written rather than failing the compile over it.
///
/// A cache only exists for a provider that was sent a baseline. An empty
/// result list here means every module the run considered dropped out —
/// never that the run found no modules at all, since an empty source set is
/// refused before a provider is ever invoked (see `collect_source_documents`).
/// Writing it empties the cache, which is the point: a baseline for modules
/// the sources no longer hold would resurrect them on the next run. The
/// caller only reaches this function when the run reported success, or
/// reported at least one module result, so a whole-request rejection (no
/// modules, no success) never empties a previously good cache.
fn store_compile_results(
    cache: &cache::CompileCache,
    key: &cache::CacheKey,
    context_digest: Option<String>,
    results: &[morphir_extension_sdk::ModuleResult],
) {
    if let Err(error) = cache.write_results(key, context_digest, results) {
        tracing::debug!(
            root = %cache.root().display(),
            %error,
            "the incremental compile cache could not be written"
        );
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

/// The requested IR release, spelled the way this provider advertises it.
///
/// This is a temporary CLI-side shim, not the intended design. The registry
/// matches advertised versions by normalized release, so two providers can both
/// serve Morphir IR 4 while spelling it `"4"` and `"4.0.0"` — but each frontend
/// then compares `options.irVersion` against its own spelling as a string and
/// rejects the other. Restating the release in the provider's own terms keeps
/// both working until the bindings accept every spelling that normalizes to the
/// same release (a part-1 follow-up), at which point this can go. An
/// unrecognised release is passed through, and the provider rejects it.
fn advertised_ir_version(advertised: &[String], requested: &str) -> String {
    let release = normalize_ir_version_text(requested).map(|version| version.release);
    advertised
        .iter()
        .find(|candidate| {
            release.is_some()
                && normalize_ir_version_text(candidate).map(|version| version.release) == release
        })
        .cloned()
        .unwrap_or_else(|| requested.to_owned())
}

#[cfg(test)]
mod incremental_tests {
    use super::{cache_key, cache_write_is_warranted, provider_supports_incremental};
    use morphir_extension_sdk::{CompileOptions as ExtensionCompileOptions, CompileResult};

    fn resolve(language: &str, extension: &str) -> morphir_daemon::ResolvedFrontend {
        crate::extensions::extension_registry_for([], Some(extension))
            .unwrap()
            .resolve_frontend(
                language,
                "4.0.0",
                morphir_daemon::InvocationPolicy::PreferDirect,
            )
            .unwrap()
    }

    fn options() -> ExtensionCompileOptions {
        ExtensionCompileOptions {
            types_only: false,
            ir_version: "4.0.0".into(),
            extra: std::collections::HashMap::new(),
        }
    }

    // Requirement: only a provider that advertises `frontend.incremental` is
    // sent a baseline. A provider that compiles everything every time has
    // nothing to remember, and offering it a baseline would be a request it
    // never agreed to answer.
    #[test]
    fn only_an_incremental_provider_is_cached() {
        assert!(provider_supports_incremental(&resolve(
            "elm",
            "morphir-elm-native"
        )));
        assert!(provider_supports_incremental(&resolve(
            "gleam",
            "morphir-gleam"
        )));
    }

    // The key names the provider and the shape of what it was asked for. The
    // compile context itself — including the prelude — is no longer part of
    // it: an incremental extension computes its own digest of that context
    // and returns it in the result, which the cache stores and echoes back as
    // the next baseline's `contextDigest` instead.
    #[test]
    fn the_key_names_the_provider_and_the_request_shape() {
        let resolved = resolve("elm", "morphir-elm-native");
        let key = cache_key(&resolved, &options());

        assert_eq!(key.extension_id, "morphir-elm-native");
        assert_eq!(key.extension_version, resolved.info().version);
        assert_eq!(key.ir_version, "4.0.0");
        assert!(!key.types_only);
    }

    // `cache_key` is a pure function of `(resolved, options)`: a non-Elm
    // provider is keyed exactly the same way, since neither carries a
    // prelude any more.
    #[test]
    fn a_non_elm_provider_is_keyed_the_same_way() {
        let resolved = resolve("gleam", "morphir-gleam-binding");
        let key = cache_key(&resolved, &options());

        assert_eq!(key.extension_id, "morphir-gleam");
        assert_eq!(key.ir_version, "4.0.0");
        assert!(!key.types_only);
    }

    fn compile_result(
        success: bool,
        module_results: Vec<morphir_extension_sdk::ModuleResult>,
    ) -> CompileResult {
        CompileResult {
            success,
            ir_version: None,
            ir: None,
            diagnostics: Vec::new(),
            modules: Vec::new(),
            module_results,
            context_digest: None,
        }
    }

    // Requirement: a whole-request rejection — `success: false` and no module
    // results at all — carries no information about any module, so it must
    // not be written: writing it would empty a cache a previous, genuinely
    // productive run had built.
    #[test]
    fn a_whole_request_rejection_does_not_warrant_a_cache_write() {
        assert!(!cache_write_is_warranted(&compile_result(false, vec![])));
    }

    // Requirement: a partial failure still teaches the cache something — the
    // modules that did compile should not compile again once the broken one
    // is fixed — so it is written even though the run overall failed.
    #[test]
    fn a_partial_failure_still_warrants_a_cache_write() {
        use morphir_extension_sdk::{ModuleResult, ModuleStatus};
        let results = vec![ModuleResult {
            name: "My.Other".into(),
            uri: "file:///src/My/Other.elm".into(),
            status: ModuleStatus::Compiled,
            source_digest: Some("sha256:source".into()),
            interface_digest: Some("sha256:interface".into()),
            depends_on: Vec::new(),
            ir: Some(serde_json::json!({ "module": "My.Other" })),
            diagnostics: Vec::new(),
        }];
        assert!(cache_write_is_warranted(&compile_result(false, results)));
    }

    // Requirement: an ordinary successful run always warrants a write, even in
    // the edge case where it reports no modules of its own (nothing else about
    // it says "rejected").
    #[test]
    fn a_successful_run_always_warrants_a_cache_write() {
        assert!(cache_write_is_warranted(&compile_result(true, vec![])));
    }
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

    /// A `--json` client reads the result envelope, not stderr, so a warning
    /// that only went to stderr is invisible to it. The extension warning has
    /// always been in `diagnostics`; the mode warnings must be too, and in the
    /// order a reader meets them.
    #[test]
    fn config_warnings_reach_the_diagnostics_of_a_machine_format_in_order() {
        use crate::output::OutputFormat;

        let warnings = super::config_warnings(
            Some("extension is broken"),
            &[
                "doc_comments is broken".to_owned(),
                "ordering is broken".to_owned(),
            ],
        );
        let mut diagnostics = vec![crate::output::Diagnostic {
            level: "error".to_string(),
            message: "from the compile".to_string(),
            code: None,
            related: Vec::new(),
            file: None,
            line: None,
            column: None,
            uri: None,
            range: None,
        }];

        super::prepend_config_warnings(&mut diagnostics, &warnings, OutputFormat::Json);

        let messages: Vec<&str> = diagnostics
            .iter()
            .map(|diagnostic| diagnostic.message.as_str())
            .collect();
        assert_eq!(
            messages,
            vec![
                "extension is broken",
                "doc_comments is broken",
                "ordering is broken",
                "from the compile",
            ]
        );
        assert!(
            diagnostics[..3]
                .iter()
                .all(|diagnostic| diagnostic.level == "warning")
        );
    }

    /// A human run already read them on stderr, so repeating them in the
    /// rendered output would say everything twice.
    #[test]
    fn config_warnings_stay_out_of_a_human_format() {
        use crate::output::OutputFormat;

        let mut diagnostics = Vec::new();

        super::prepend_config_warnings(
            &mut diagnostics,
            &["ordering is broken".to_owned()],
            OutputFormat::Human,
        );

        assert!(diagnostics.is_empty());
    }

    /// No warning, no change: a clean run's diagnostics are the compile's own.
    #[test]
    fn no_config_warning_leaves_the_diagnostics_alone() {
        use crate::output::OutputFormat;

        assert_eq!(super::config_warnings(None, &[]), Vec::<String>::new());

        let mut diagnostics = Vec::new();
        super::prepend_config_warnings(&mut diagnostics, &[], OutputFormat::Json);
        assert!(diagnostics.is_empty());
    }

    #[test]
    fn compile_version_uses_cli_then_project_then_v4_default() {
        use morphir_common::ir_transport::IrVersion;
        let configured: IrSection =
            serde_json::from_value(serde_json::json!({"format_version": 3})).unwrap();
        assert_eq!(selected_ir_version(None, None).unwrap(), IrVersion::V4);
        assert_eq!(
            selected_ir_version(None, Some(&configured)).unwrap(),
            IrVersion::V3
        );
        assert_eq!(
            selected_ir_version(Some(IrVersion::V4), Some(&configured)).unwrap(),
            IrVersion::V4
        );
        let invalid: IrSection =
            serde_json::from_value(serde_json::json!({"format_version": 2})).unwrap();
        assert!(selected_ir_version(None, Some(&invalid)).is_err());
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

    /// Discovery walks up from the start directory. Pinned before the lookup
    /// moves into the session's startup phase, so the move can be checked
    /// rather than trusted.
    #[test]
    fn configuration_is_discovered_by_walking_up_from_the_start_directory() {
        let root = tempfile::tempdir().expect("temp dir");
        std::fs::write(
            root.path().join("morphir.toml"),
            "[frontend]\nlanguage = \"elm\"\n",
        )
        .expect("write config");
        let nested = root.path().join("a").join("b");
        std::fs::create_dir_all(&nested).expect("create nested");

        let found = morphir_devkit::discover_config(&nested).expect("discovery succeeds");

        assert_eq!(
            found.as_deref().and_then(std::path::Path::file_name),
            Some(std::ffi::OsStr::new("morphir.toml"))
        );
    }

    /// A directory with no configuration above it discovers nothing, and that
    /// is not an error. This is the case GH #887 turned into a silent defect,
    /// so it is pinned explicitly.
    #[test]
    fn a_tree_without_configuration_discovers_nothing_without_failing() {
        let root = tempfile::tempdir().expect("temp dir");

        let found = morphir_devkit::discover_config(root.path()).expect("discovery succeeds");

        assert_eq!(found, None);
    }
}

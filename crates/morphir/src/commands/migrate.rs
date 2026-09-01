//! Convert concrete Morphir IR versions, serialization profiles, and layouts.

mod format;
mod publication;
mod report;

use std::fs::File;
use std::io::BufReader;
use std::path::{Path, PathBuf};

use format::{InputSelection, resolve_input, resolve_output_format};
use morphir_common::ir_transport::{
    ClassicToV4, CodecOptions, CodecRegistry, DocumentTreeSink, DocumentTreeSource, EventSink,
    FormatId, IrVersion, Layout, Pipeline, Stage, TransportDiagnostic,
};
use morphir_common::remote::{RemoteSource, RemoteSourceResolver, ResolveOptions};
use morphir_core::ir::v4::{TypeEncoding, with_type_encoding};
use morphir_core::migration::{MigrationOptions, V4Encoding};
use morphir_core::traversal::IrCursor;
use publication::{write_file_atomically, write_stdout_atomically, write_tree_atomically};
use starbase::AppResult;

#[derive(Clone, Copy, Debug, Eq, PartialEq, clap::ValueEnum)]
pub enum OutputLayout {
    SingleFile,
    Vfs,
}

/// Options selected by the migrate CLI command.
pub struct MigrateCommandOptions {
    pub output: Option<PathBuf>,
    pub target_version: String,
    pub force_refresh: bool,
    pub no_cache: bool,
    pub json: bool,
    pub expanded: bool,
    pub allow_partial: bool,
    pub output_layout: Option<OutputLayout>,
    pub input_format: Option<FormatId>,
    pub output_format: Option<FormatId>,
}

/// Run the migrate command.
pub fn run_migrate(input: String, options: MigrateCommandOptions) -> AppResult<miette::Report> {
    let output_name = options
        .output
        .as_ref()
        .map(|path| path.display().to_string())
        .unwrap_or_else(|| "<stdout>".to_owned());
    match migrate(&input, &options) {
        Ok((source, target, warnings)) => {
            report::success(
                options.json,
                options.output.is_some(),
                &input,
                &output_name,
                &source,
                &target,
                &warnings,
            );
            Ok(None)
        }
        Err(error) => {
            let diagnostic = error.to_string();
            report::error(options.json, &input, &output_name, &diagnostic);
            Err(miette::miette!(diagnostic))
        }
    }
}

fn migrate(
    input: &str,
    options: &MigrateCommandOptions,
) -> Result<(String, String, Vec<String>), TransportDiagnostic> {
    let local_path = resolve_source(input, options.force_refresh, options.no_cache)?;
    let input_selection = resolve_input(&local_path, options.input_format.clone())?;
    let target_version = resolve_target_version(&options.target_version)?;
    let output_layout = inferred_output_layout(options.output_layout, &options.output);
    if output_layout == Layout::DocumentTree && options.output.is_none() {
        return Err(command_error(
            "morphir::ir::cli::tree_requires_output",
            Stage::Detection,
            "document-tree output requires --output <directory>",
            "provide an output directory or select --output-layout single-file",
        ));
    }
    if target_version == IrVersion::V3 && input_selection.version == IrVersion::V4 {
        return Err(command_error(
            "morphir::ir::migration::unsupported_v4_downgrade",
            Stage::Migration,
            "v4 to Classic v3 conversion is not defined for all v4 constructs",
            "select --target-version v4; downgrade remains unavailable until lossless rules are specified",
        ));
    }
    if target_version == IrVersion::V3 && output_layout == Layout::DocumentTree {
        return Err(command_error(
            "morphir::ir::document_tree::version_unsupported",
            Stage::Detection,
            "the granular document-tree layout is defined for v4",
            "select a single-file v3 output or migrate to v4",
        ));
    }
    let output_format = resolve_output_format(
        options.output_format.clone(),
        options.output.as_deref(),
        output_layout,
        options.json,
    )?;
    let migration_options = MigrationOptions {
        allow_partial: options.allow_partial,
        encoding: if options.expanded {
            V4Encoding::Expanded
        } else {
            V4Encoding::Compact
        },
    };
    let type_encoding = if options.expanded {
        TypeEncoding::Expanded
    } else {
        TypeEncoding::Compact
    };
    let warnings = with_type_encoding(type_encoding, || match output_layout {
        Layout::SingleFile => write_single_file(
            &local_path,
            &input_selection,
            target_version,
            output_format.clone(),
            options.output.as_deref(),
            migration_options,
        ),
        Layout::DocumentTree => write_tree(
            &local_path,
            &input_selection,
            target_version,
            output_format.clone(),
            options.output.as_deref().unwrap(),
            migration_options,
        ),
    })?;
    Ok((
        selection_name(
            input_selection.version,
            &input_selection.format,
            input_selection.layout,
        ),
        selection_name(target_version, &output_format, output_layout),
        warnings,
    ))
}

fn write_single_file(
    input: &Path,
    input_selection: &InputSelection,
    target_version: IrVersion,
    output_format: FormatId,
    output: Option<&Path>,
    migration_options: MigrationOptions,
) -> Result<Vec<String>, TransportDiagnostic> {
    let registry = CodecRegistry::with_builtins();
    let output_options =
        CodecOptions::new(target_version, Layout::SingleFile, output_format.clone());
    let codec = registry.codec(&output_format).ok_or_else(|| {
        command_error(
            "morphir::ir::codec::unknown_output_format",
            Stage::Detection,
            format!("no codec is registered for '{output_format}'"),
            "select json or yaml, or register the requested codec",
        )
    })?;
    let mut warnings = Vec::new();
    let mut encode = |writer: &mut dyn std::io::Write| {
        let mut sink = codec.encoder(writer, &output_options)?;
        warnings = run_events(
            input,
            input_selection,
            target_version,
            sink.as_mut(),
            migration_options,
        )?;
        Ok(())
    };
    match output {
        Some(path) => write_file_atomically(path, &mut encode)?,
        None => write_stdout_atomically(&mut encode)?,
    }
    Ok(warnings)
}

fn write_tree(
    input: &Path,
    input_selection: &InputSelection,
    target_version: IrVersion,
    output_format: FormatId,
    output: &Path,
    migration_options: MigrationOptions,
) -> Result<Vec<String>, TransportDiagnostic> {
    let tree_options = CodecOptions::new(target_version, Layout::DocumentTree, output_format);
    let mut warnings = Vec::new();
    write_tree_atomically(output, |root| {
        let mut sink = DocumentTreeSink::new(root, tree_options)?;
        warnings = run_events(
            input,
            input_selection,
            target_version,
            &mut sink,
            migration_options,
        )?;
        Ok(())
    })?;
    Ok(warnings)
}

fn run_events(
    input: &Path,
    input_selection: &InputSelection,
    target_version: IrVersion,
    output: &mut dyn EventSink,
    migration_options: MigrationOptions,
) -> Result<Vec<String>, TransportDiagnostic> {
    let registry = CodecRegistry::with_builtins();
    let input_options = CodecOptions::new(
        input_selection.version,
        input_selection.layout,
        input_selection.format.clone(),
    );
    let mut pipeline = Pipeline::new();
    let report = if input_selection.version == IrVersion::V3 && target_version == IrVersion::V4 {
        let transform = ClassicToV4::new(migration_options);
        let report = transform.report_handle();
        pipeline.push(transform);
        Some(report)
    } else {
        None
    };
    match input_selection.layout {
        Layout::SingleFile => {
            let codec = registry.codec(&input_selection.format).ok_or_else(|| {
                command_error(
                    "morphir::ir::codec::unknown_input_format",
                    Stage::Detection,
                    format!("no codec is registered for '{}'", input_selection.format),
                    "select json or yaml, or register the requested codec",
                )
            })?;
            let file = File::open(input).map_err(|error| {
                command_error(
                    "morphir::ir::cli::input_open_failed",
                    Stage::Syntax,
                    format!("failed to open {}: {error}", input.display()),
                    "verify that the input exists and is readable",
                )
            })?;
            let mut reader = BufReader::new(file);
            let mut sink = pipeline.sink(output)?;
            codec.decode(&mut reader, &input_options, &mut sink)?;
        }
        Layout::DocumentTree => {
            let mut source =
                DocumentTreeSource::open(morphir_common::vfs::physical_root(input), input_options)?;
            pipeline.run(&mut source, output)?;
        }
    }
    let Some(report) = report else {
        return Ok(Vec::new());
    };
    let report = report.get().ok_or_else(|| {
        command_error(
            "morphir::ir::migration::missing_report",
            Stage::Migration,
            "the migration pipeline ended without a report",
            "retry the migration and report this internal pipeline error",
        )
    })?;
    if !report.can_publish() {
        return Err(command_error(
            "morphir::ir::migration::publication_blocked",
            Stage::Migration,
            "migration diagnostics contain errors that prevent publication",
            "correct the reported IR gaps; --allow-partial applies only to explicitly recoverable target nodes",
        ));
    }
    Ok(report
        .diagnostics()
        .iter()
        .map(|diagnostic| {
            let help = diagnostic
                .help
                .as_deref()
                .map(|help| format!(" Help: {help}"))
                .unwrap_or_default();
            format!(
                "[{}] at {}: {}{}",
                diagnostic.code, diagnostic.path, diagnostic.message, help
            )
        })
        .collect())
}

fn resolve_source(
    input: &str,
    force_refresh: bool,
    no_cache: bool,
) -> Result<PathBuf, TransportDiagnostic> {
    let source = RemoteSource::parse(input).map_err(|error| {
        command_error(
            "morphir::ir::source::invalid",
            Stage::Detection,
            error.to_string(),
            "provide a local path, supported URL, or configured remote source",
        )
    })?;
    if source.is_local() {
        return Ok(PathBuf::from(input));
    }
    let mut resolver = RemoteSourceResolver::with_defaults().map_err(|error| {
        command_error(
            "morphir::ir::source::resolver_failed",
            Stage::Detection,
            error.to_string(),
            "verify remote-source and cache configuration",
        )
    })?;
    if !resolver.is_allowed(&source) {
        return Err(command_error(
            "morphir::ir::source::not_allowed",
            Stage::Detection,
            format!("source '{input}' is not allowed by configuration"),
            "use an allowed source or update the remote-source policy",
        ));
    }
    let resolve_options = if no_cache {
        ResolveOptions::no_cache()
    } else if force_refresh {
        ResolveOptions::force_refresh()
    } else {
        ResolveOptions::new()
    };
    resolver
        .resolve(&source, &resolve_options)
        .map_err(|error| {
            command_error(
                "morphir::ir::source::resolve_failed",
                Stage::Detection,
                error.to_string(),
                "verify network access and the remote source, then retry",
            )
        })
}

fn inferred_output_layout(requested: Option<OutputLayout>, output: &Option<PathBuf>) -> Layout {
    match requested {
        Some(OutputLayout::SingleFile) => Layout::SingleFile,
        Some(OutputLayout::Vfs) => Layout::DocumentTree,
        None => output
            .as_ref()
            .filter(|path| {
                let text = path.as_os_str().to_string_lossy();
                path.is_dir()
                    || text.ends_with('/')
                    || text.ends_with('\\')
                    || path
                        .file_name()
                        .and_then(|name| name.to_str())
                        .is_some_and(|name| name.ends_with(".morphir-dist"))
            })
            .map(|_| Layout::DocumentTree)
            .unwrap_or(Layout::SingleFile),
    }
}

fn resolve_target_version(value: &str) -> Result<IrVersion, TransportDiagnostic> {
    match value.to_ascii_lowercase().as_str() {
        "latest" | "v4" | "4" => Ok(IrVersion::V4),
        "classic" | "v3" | "3" => Ok(IrVersion::V3),
        "v2" | "2" | "v1" | "1" => Err(command_error(
            "morphir::ir::migration::unsupported_target_version",
            Stage::Migration,
            format!("target version '{value}' is not implemented by the concrete converter"),
            "select concrete v3 or v4 output",
        )),
        _ => Err(command_error(
            "morphir::ir::migration::invalid_target_version",
            Stage::Detection,
            format!("invalid target version '{value}'"),
            "select latest, v4, 4, classic, v3, or 3",
        )),
    }
}

fn selection_name(version: IrVersion, format: &FormatId, layout: Layout) -> String {
    let version = match version {
        IrVersion::V3 => "v3",
        IrVersion::V4 => "v4",
    };
    let layout = match layout {
        Layout::SingleFile => "single-file",
        Layout::DocumentTree => "document-tree",
    };
    format!("{version}/{format}/{layout}")
}

fn command_error(
    code: &'static str,
    stage: Stage,
    message: impl Into<String>,
    guidance: &'static str,
) -> TransportDiagnostic {
    TransportDiagnostic::error(code, stage, IrCursor::root(), message).with_guidance(guidance)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn output_layout_infers_document_trees_without_closing_format_selection() {
        assert_eq!(
            inferred_output_layout(None, &Some(PathBuf::from("model.morphir-dist"))),
            Layout::DocumentTree
        );
        assert_eq!(
            inferred_output_layout(None, &Some(PathBuf::from("model.yaml"))),
            Layout::SingleFile
        );
    }
}

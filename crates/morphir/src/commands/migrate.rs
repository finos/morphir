//! Migrate Command
//!
//! Command to migrate Morphir IR between versions and formats.

use crate::tui::JsonPager;
use morphir_common::ir_transport::{
    ClassicV3ModuleVisitor, read_document_tree, visit_classic_v3, write_document_tree,
};
use morphir_common::loader::{LoadedDistribution, load_distribution};
use morphir_common::remote::{RemoteSource, RemoteSourceResolver, ResolveOptions};
use morphir_common::vfs::{OsVfs, physical_root};
use morphir_core::ir::v4::{TypeEncoding, with_type_encoding};
use morphir_core::migration::{
    MigrationContext, MigrationDiagnostic, MigrationOptions, MigrationReport, V4Encoding,
    migrate_access, migrate_distribution, migrate_module_definition, migrate_package_specification,
    migrate_path,
};
use serde::Serialize;
use starbase::AppResult;
use std::io::{BufReader, BufWriter, Write};
use std::path::Path;
use std::path::PathBuf;

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
}

struct StreamingV4Writer<W> {
    writer: W,
    context: MigrationContext,
    began: bool,
    first_module: bool,
}

impl<W: Write> StreamingV4Writer<W> {
    fn new(writer: W, options: MigrationOptions) -> Self {
        Self {
            writer,
            context: MigrationContext::new(options),
            began: false,
            first_module: true,
        }
    }

    fn write_json(&mut self, value: &impl Serialize) -> Result<(), String> {
        serde_json::to_writer(&mut self.writer, value)
            .map_err(|error| format!("failed to serialize migrated IR: {error}"))
    }
}

impl<W: Write> ClassicV3ModuleVisitor for StreamingV4Writer<W> {
    type Output = MigrationReport;

    fn begin(
        &mut self,
        package: &morphir_core::ir::classic::Path,
        dependencies: &[(
            morphir_core::ir::classic::Path,
            morphir_core::ir::classic::PackageSpecification<morphir_core::ir::classic::Attrs>,
        )],
    ) -> Result<(), String> {
        let dependencies = dependencies
            .iter()
            .map(|(name, specification)| {
                Ok((
                    migrate_path(name).to_canonical_string(),
                    migrate_package_specification(specification, &mut self.context)
                        .map_err(|error| migration_diagnostic(&error))?,
                ))
            })
            .collect::<Result<indexmap::IndexMap<_, _>, String>>()?;
        self.writer
            .write_all(b"{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":")
            .map_err(|error| format!("failed to write migrated IR: {error}"))?;
        let package = morphir_core::naming::PackageName::new(migrate_path(package));
        self.write_json(&package)?;
        self.writer
            .write_all(b",\"dependencies\":")
            .map_err(|error| format!("failed to write migrated IR: {error}"))?;
        self.write_json(&dependencies)?;
        self.writer
            .write_all(b",\"def\":{\"modules\":{")
            .map_err(|error| format!("failed to write migrated IR: {error}"))?;
        self.began = true;
        Ok(())
    }

    fn visit_module(
        &mut self,
        module: morphir_core::ir::classic::ModuleEntry<
            morphir_core::ir::classic::Attrs,
            morphir_core::ir::classic::Type<morphir_core::ir::classic::Attrs>,
        >,
    ) -> Result<(), String> {
        if !self.began {
            return Err("streaming migration received a module before its header".to_owned());
        }
        let name = migrate_path(&module.path).to_canonical_string();
        let definition = morphir_core::ir::v4::AccessControlled {
            access: migrate_access(&module.definition.access),
            value: migrate_module_definition(&module.definition.value, &mut self.context)
                .map_err(|error| migration_diagnostic(&error))?,
        };
        if !self.first_module {
            self.writer
                .write_all(b",")
                .map_err(|error| format!("failed to write migrated IR: {error}"))?;
        }
        self.write_json(&name)?;
        self.writer
            .write_all(b":")
            .map_err(|error| format!("failed to write migrated IR: {error}"))?;
        self.write_json(&definition)?;
        self.first_module = false;
        Ok(())
    }

    fn finish(mut self) -> Result<Self::Output, String> {
        if !self.began {
            return Err("streaming migration did not receive a distribution header".to_owned());
        }
        self.writer
            .write_all(b"}}}}}\n")
            .map_err(|error| format!("failed to finish migrated IR: {error}"))?;
        self.writer
            .flush()
            .map_err(|error| format!("failed to flush migrated IR: {error}"))?;
        Ok(self.context.report)
    }
}

/// JSON output for migrate command
#[derive(Serialize)]
struct MigrateResult {
    success: bool,
    input: String,
    output: String,
    source_format: String,
    target_format: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    warnings: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl MigrateResult {
    fn success(
        input: &str,
        output: &str,
        source_format: &str,
        target_format: &str,
        warnings: Vec<String>,
    ) -> Self {
        Self {
            success: true,
            input: input.to_string(),
            output: output.to_string(),
            source_format: source_format.to_string(),
            target_format: target_format.to_string(),
            warnings,
            error: None,
        }
    }

    fn error(input: &str, output: &str, error: &str) -> Self {
        Self {
            success: false,
            input: input.to_string(),
            output: output.to_string(),
            source_format: String::new(),
            target_format: String::new(),
            warnings: Vec::new(),
            error: Some(error.to_string()),
        }
    }
}

/// Display JSON content using the ratatui-based pager with syntax highlighting.
fn display_json_in_pager(content: &str, title: &str) -> std::io::Result<()> {
    let pager = JsonPager::new(content.to_string(), title.to_string());
    pager.run()
}

/// Write content to output file or display in pager with syntax highlighting.
fn write_or_display(output: &Option<PathBuf>, content: &str, json_mode: bool, title: &str) {
    match output {
        Some(path) => {
            std::fs::write(path, content).expect("Failed to write output");
        }
        None => {
            if !json_mode {
                // Display in pager with syntax highlighting (like bat)
                if let Err(e) = display_json_in_pager(content, title) {
                    eprintln!("Failed to display output: {}", e);
                    // Fallback to plain output
                    println!("{}", content);
                }
            } else {
                // In JSON mode with no output file, emit the migrated IR to stdout
                println!("{}", content);
            }
        }
    }
}

fn write_json_atomically(path: &Path, value: &impl Serialize) -> Result<(), String> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent).map_err(|error| {
        format!(
            "failed to create output directory {}: {error}",
            parent.display()
        )
    })?;

    let mut temporary = tempfile::NamedTempFile::new_in(parent).map_err(|error| {
        format!(
            "failed to create temporary output in {}: {error}",
            parent.display()
        )
    })?;
    {
        let mut writer = BufWriter::new(temporary.as_file_mut());
        serde_json::to_writer_pretty(&mut writer, value)
            .map_err(|error| format!("failed to serialize migrated IR: {error}"))?;
        writer
            .write_all(b"\n")
            .map_err(|error| format!("failed to write migrated IR: {error}"))?;
        writer
            .flush()
            .map_err(|error| format!("failed to flush migrated IR: {error}"))?;
    }
    temporary
        .as_file()
        .sync_all()
        .map_err(|error| format!("failed to sync migrated IR: {error}"))?;
    temporary.persist(path).map_err(|error| {
        format!(
            "failed to publish migrated IR to {}: {error}",
            path.display()
        )
    })?;
    Ok(())
}

fn stream_classic_v3_file_atomically(
    input: &Path,
    output: &Path,
    options: MigrationOptions,
) -> Result<MigrationReport, String> {
    let type_encoding = match options.encoding {
        V4Encoding::Compact => TypeEncoding::Compact,
        V4Encoding::Expanded => TypeEncoding::Expanded,
    };
    let parent = output
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent).map_err(|error| {
        format!(
            "failed to create output directory {}: {error}",
            parent.display()
        )
    })?;
    let input_file = std::fs::File::open(input)
        .map_err(|error| format!("failed to open {}: {error}", input.display()))?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)
        .map_err(|error| format!("failed to create streaming output: {error}"))?;
    let report = with_type_encoding(type_encoding, || {
        visit_classic_v3(
            BufReader::new(input_file),
            StreamingV4Writer::new(BufWriter::new(temporary.as_file_mut()), options),
        )
    })
    .map_err(|error| error.to_string())?;
    if !report.can_publish() {
        return Err("migration produced errors and cannot be published".to_owned());
    }
    temporary
        .as_file()
        .sync_all()
        .map_err(|error| format!("failed to sync migrated IR: {error}"))?;
    temporary.persist(output).map_err(|error| {
        format!(
            "failed to publish migrated IR to {}: {error}",
            output.display()
        )
    })?;
    Ok(report)
}

fn migration_diagnostic(diagnostic: &MigrationDiagnostic) -> String {
    let location = if diagnostic.path.is_empty() {
        String::new()
    } else {
        format!(" at {}", diagnostic.path)
    };
    let help = diagnostic
        .help
        .as_deref()
        .map(|help| format!(" Help: {help}"))
        .unwrap_or_default();
    format!(
        "[{}]{}: {}{}",
        diagnostic.code, location, diagnostic.message, help
    )
}

fn publish_json(
    output: &Option<PathBuf>,
    value: &impl Serialize,
    json_mode: bool,
    title: &str,
) -> Result<(), String> {
    match output {
        Some(path) => write_json_atomically(path, value),
        None => {
            let content = serde_json::to_string_pretty(value)
                .map_err(|error| format!("failed to serialize migrated IR: {error}"))?;
            write_or_display(output, &content, json_mode, title);
            Ok(())
        }
    }
}

fn inferred_output_layout(
    requested: Option<OutputLayout>,
    output: &Option<PathBuf>,
) -> OutputLayout {
    requested.unwrap_or_else(|| {
        output
            .as_ref()
            .filter(|path| {
                path.is_dir()
                    || path
                        .file_name()
                        .and_then(|name| name.to_str())
                        .is_some_and(|name| name.ends_with(".morphir-dist"))
            })
            .map(|_| OutputLayout::Vfs)
            .unwrap_or(OutputLayout::SingleFile)
    })
}

fn publish_document_tree(path: &Path, ir: &morphir_core::ir::v4::IRFile) -> Result<(), String> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent).map_err(|error| {
        format!(
            "failed to create output directory {}: {error}",
            parent.display()
        )
    })?;
    if path.exists() && !path.is_dir() {
        return Err(format!(
            "VFS output {} exists and is not a directory",
            path.display()
        ));
    }

    let staging = tempfile::Builder::new()
        .prefix(".morphir-migrate-")
        .tempdir_in(parent)
        .map_err(|error| format!("failed to create VFS staging directory: {error}"))?;
    write_document_tree(&physical_root(staging.path()), ir)
        .map_err(|error| format!("failed to write VFS output: {error:#}"))?;
    let staging_path = staging.keep();

    if !path.exists() {
        return std::fs::rename(&staging_path, path)
            .map_err(|error| format!("failed to publish VFS output: {error}"));
    }

    let backup_holder = tempfile::Builder::new()
        .prefix(".morphir-backup-")
        .tempdir_in(parent)
        .map_err(|error| format!("failed to reserve VFS backup path: {error}"))?;
    let backup_path = backup_holder.path().to_owned();
    backup_holder
        .close()
        .map_err(|error| format!("failed to prepare VFS backup path: {error}"))?;
    std::fs::rename(path, &backup_path)
        .map_err(|error| format!("failed to stage existing VFS output: {error}"))?;
    if let Err(error) = std::fs::rename(&staging_path, path) {
        let rollback = std::fs::rename(&backup_path, path);
        return Err(match rollback {
            Ok(()) => format!("failed to publish VFS output; existing output restored: {error}"),
            Err(rollback) => format!(
                "failed to publish VFS output ({error}) and restore existing output ({rollback}); backup remains at {}",
                backup_path.display()
            ),
        });
    }
    std::fs::remove_dir_all(&backup_path)
        .map_err(|error| format!("published VFS output but failed to remove backup: {error}"))?;
    Ok(())
}

fn publish_v4(
    output: &Option<PathBuf>,
    layout: OutputLayout,
    ir: &morphir_core::ir::v4::IRFile,
    json_mode: bool,
    title: &str,
    encoding: V4Encoding,
) -> Result<(), String> {
    let encoding = match encoding {
        V4Encoding::Compact => TypeEncoding::Compact,
        V4Encoding::Expanded => TypeEncoding::Expanded,
    };
    with_type_encoding(encoding, || match layout {
        OutputLayout::SingleFile => publish_json(output, ir, json_mode, title),
        OutputLayout::Vfs => output
            .as_deref()
            .ok_or_else(|| "VFS output requires --output <directory>".to_owned())
            .and_then(|path| publish_document_tree(path, ir)),
    })
}

/// Resolve target version string to a normalized format.
/// Returns (is_v4, format_name) where format_name is either "v4" or "classic".
fn resolve_target_version(version: &str) -> Result<(bool, &'static str), String> {
    match version.to_lowercase().as_str() {
        // Latest always resolves to the newest format
        "latest" => Ok((true, "v4")),
        // V4 format
        "v4" | "4" => Ok((true, "v4")),
        // Classic formats (V1, V2, V3) all map to "classic"
        "classic" | "v3" | "3" | "v2" | "2" | "v1" | "1" => Ok((false, "classic")),
        _ => Err(format!(
            "Invalid target version '{}'. Valid values: latest, v4, 4, classic, v3, 3, v2, 2, v1, 1",
            version
        )),
    }
}

/// Run the migrate command.
///
/// # Arguments
/// * `input` - Input file path or remote source
/// * `output` - Output file path
/// * `target_version` - Target format version ("latest", "v4", or "classic")
/// * `force_refresh` - Force refresh cached remote sources
/// * `no_cache` - Skip cache entirely for remote sources
/// * `json` - Output result as JSON
/// * `expanded` - Use expanded (non-compact) format for V4 output
pub fn run_migrate(input: String, options: MigrateCommandOptions) -> AppResult<miette::Report> {
    let MigrateCommandOptions {
        output,
        target_version,
        force_refresh,
        no_cache,
        json,
        expanded,
        allow_partial,
        output_layout,
    } = options;
    let output_str = output
        .as_ref()
        .map(|p| p.display().to_string())
        .unwrap_or_else(|| "<console>".to_string());
    let mut warnings: Vec<String> = Vec::new();

    // Helper to output error
    let output_error = |msg: &str| {
        if json {
            let result = MigrateResult::error(&input, &output_str, msg);
            println!("{}", serde_json::to_string_pretty(&result).unwrap());
        } else {
            eprintln!("{}", msg);
        }
    };

    // Parse input source
    let source = match RemoteSource::parse(&input) {
        Ok(s) => s,
        Err(e) => {
            output_error(&format!("Invalid input source: {}", e));
            return Ok(Some(1));
        }
    };

    // Resolve source to local path
    let local_path = if source.is_local() {
        // Local path - use directly
        PathBuf::from(&input)
    } else {
        // Remote source - resolve using resolver
        let mut resolver = match RemoteSourceResolver::with_defaults() {
            Ok(r) => r,
            Err(e) => {
                output_error(&format!("Failed to initialize source resolver: {}", e));
                return Ok(Some(1));
            }
        };

        // Check if source is allowed
        if !resolver.is_allowed(&source) {
            output_error(&format!(
                "Source URL not allowed by configuration: {}",
                input
            ));
            return Ok(Some(1));
        }

        let options = if no_cache {
            ResolveOptions::no_cache()
        } else if force_refresh {
            ResolveOptions::force_refresh()
        } else {
            ResolveOptions::new()
        };

        match resolver.resolve(&source, &options) {
            Ok(path) => path,
            Err(e) => {
                output_error(&format!("Failed to fetch source: {}", e));
                return Ok(Some(1));
            }
        }
    };

    if !json {
        match &output {
            Some(path) => eprintln!("Migrating IR from {:?} to {:?}", local_path, path),
            None => eprintln!("Migrating IR from {:?} (displaying to console)", local_path),
        }
    }

    let output_layout = inferred_output_layout(output_layout, &output);
    let (target_v4, target_format) = match resolve_target_version(&target_version) {
        Ok(result) => result,
        Err(msg) => {
            output_error(&msg);
            return Ok(Some(1));
        }
    };
    let migration_options = MigrationOptions {
        allow_partial,
        encoding: if expanded {
            V4Encoding::Expanded
        } else {
            V4Encoding::Compact
        },
    };

    if target_v4
        && output_layout == OutputLayout::SingleFile
        && !expanded
        && local_path.is_file()
        && let Some(output_path) = output.as_deref()
        && let Ok(report) =
            stream_classic_v3_file_atomically(&local_path, output_path, migration_options)
    {
        warnings.extend(report.diagnostics().iter().map(migration_diagnostic));
        if json {
            let result =
                MigrateResult::success(&input, &output_str, "classic", target_format, warnings);
            println!("{}", serde_json::to_string_pretty(&result).unwrap());
        } else {
            eprintln!("Migration complete.");
        }
        return Ok(None);
    }

    let vfs = OsVfs;

    // Load input
    let dist = match if local_path.is_dir() && local_path.join("manifest.json").is_file() {
        read_document_tree(&physical_root(&local_path)).map(LoadedDistribution::V4)
    } else {
        load_distribution(&vfs, &local_path)
    } {
        Ok(d) => d,
        Err(e) => {
            output_error(&format!("Failed to load input: {}", e));
            return Ok(Some(1));
        }
    };

    match dist {
        LoadedDistribution::Classic(dist) => {
            let source_format = "classic";
            if target_v4 {
                let migrated = match migrate_distribution(&dist, migration_options) {
                    Ok(migrated) => migrated,
                    Err(diagnostic) => {
                        output_error(&migration_diagnostic(&diagnostic));
                        return Ok(Some(1));
                    }
                };
                warnings.extend(
                    migrated
                        .report
                        .diagnostics()
                        .iter()
                        .map(migration_diagnostic),
                );
                if !migrated.report.can_publish() {
                    output_error("migration produced errors and cannot be published");
                    return Ok(Some(1));
                }
                let title = format!("morphir-ir.json (V4 format, from {})", input);
                if let Err(error) = publish_v4(
                    &output,
                    output_layout,
                    &migrated.value,
                    json,
                    &title,
                    migration_options.encoding,
                ) {
                    output_error(&error);
                    return Ok(Some(1));
                }
            } else {
                if output_layout == OutputLayout::Vfs {
                    output_error("Classic output does not support the VFS document-tree layout");
                    return Ok(Some(1));
                }
                if !json {
                    eprintln!("Input is Classic, Target is Classic. Copying...");
                }
                let title = format!("morphir-ir.json (Classic format, from {})", input);
                if let Err(error) = publish_json(&output, &dist, json, &title) {
                    output_error(&error);
                    return Ok(Some(1));
                }
            }

            if json && output.is_some() {
                let result = MigrateResult::success(
                    &input,
                    &output_str,
                    source_format,
                    target_format,
                    warnings,
                );
                println!("{}", serde_json::to_string_pretty(&result).unwrap());
            }
        }
        LoadedDistribution::V4(ir_file) => {
            let source_format = "v4";
            if !target_v4 {
                output_error(
                    "[unsupported-v4-distribution] at distribution: V4 -> Classic conversion is \
                     not yet implemented; use --target-version v4 to re-encode or change layout",
                );
                return Ok(Some(1));
            } else {
                if !json {
                    eprintln!("Input is V4, Target is V4. Copying...");
                }
                let title = format!("morphir-ir.json (V4 format, from {})", input);
                if let Err(error) = publish_v4(
                    &output,
                    output_layout,
                    &ir_file,
                    json,
                    &title,
                    migration_options.encoding,
                ) {
                    output_error(&error);
                    return Ok(Some(1));
                }

                if json && output.is_some() {
                    let result = MigrateResult::success(
                        &input,
                        &output_str,
                        source_format,
                        target_format,
                        warnings,
                    );
                    println!("{}", serde_json::to_string_pretty(&result).unwrap());
                }
            }
        }
    }

    if !json {
        eprintln!("Migration complete.");
    }
    Ok(None)
}

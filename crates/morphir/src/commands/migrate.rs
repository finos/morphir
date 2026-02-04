//! Migrate Command
//!
//! Command to migrate Morphir IR between versions and formats.

use crate::tui::JsonPager;
use morphir_common::loader::{LoadedDistribution, load_distribution};
use morphir_common::remote::{RemoteSource, RemoteSourceResolver, ResolveOptions};
use morphir_common::vfs::OsVfs;
use serde::Serialize;
use starbase::AppResult;
use std::path::PathBuf;

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
pub fn run_migrate(
    input: String,
    output: Option<PathBuf>,
    target_version: String,
    force_refresh: bool,
    no_cache: bool,
    json: bool,
    _expanded: bool, // TODO: Will be used when converter module is re-enabled
) -> AppResult {
    let output_str = output
        .as_ref()
        .map(|p| p.display().to_string())
        .unwrap_or_else(|| "<console>".to_string());
    let warnings: Vec<String> = Vec::new(); // TODO: Will collect warnings when converter is re-enabled

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

    let vfs = OsVfs;

    // Load input
    let dist = match load_distribution(&vfs, &local_path) {
        Ok(d) => d,
        Err(e) => {
            output_error(&format!("Failed to load input: {}", e));
            return Ok(Some(1));
        }
    };

    // Convert
    // Resolve target version
    let (target_v4, target_format) = match resolve_target_version(&target_version) {
        Ok(result) => result,
        Err(msg) => {
            output_error(&msg);
            return Ok(Some(1));
        }
    };

    match dist {
        LoadedDistribution::Classic(dist) => {
            let source_format = "classic";
            if target_v4 {
                // Classic -> V4 conversion is not yet implemented
                // The converter module is currently disabled pending type system updates
                output_error(
                    "Classic -> V4 conversion is not yet implemented. \
                     The converter module is currently being updated. \
                     Use --target=classic to copy the file as-is.",
                );
                return Ok(Some(1));
            } else {
                if !json {
                    eprintln!("Input is Classic, Target is Classic. Copying...");
                }
                let content = serde_json::to_string_pretty(&dist).expect("Failed to serialize");
                let title = format!("morphir-ir.json (Classic format, from {})", input);
                write_or_display(&output, &content, json, &title);

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
        LoadedDistribution::V4(ir_file) => {
            let source_format = "v4";
            if !target_v4 {
                // V4 -> Classic conversion is not yet implemented
                // The converter module is currently disabled pending type system updates
                output_error(
                    "V4 -> Classic conversion is not yet implemented. \
                     The converter module is currently being updated. \
                     Use --target=v4 to copy the file as-is.",
                );
                return Ok(Some(1));
            } else {
                if !json {
                    eprintln!("Input is V4, Target is V4. Copying...");
                }
                let content = serde_json::to_string_pretty(&ir_file).expect("Failed to serialize");
                let title = format!("morphir-ir.json (V4 format, from {})", input);
                write_or_display(&output, &content, json, &title);

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

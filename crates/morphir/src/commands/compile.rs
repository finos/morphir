//! Compile command for compiling source code to Morphir IR

use crate::error::CliError;
use crate::output::Diagnostic;
use morphir_daemon::extensions::registry::ExtensionRegistry;
use morphir_design::{
    discover_config, ensure_morphir_structure, load_config_context, resolve_compile_output,
    resolve_path_relative_to_config,
};
use starbase::AppResult;
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
pub async fn run_compile(options: CompileOptions) -> AppResult {
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
        discover_config(&start_dir).ok_or_else(|| CliError::Config {
            error: anyhow::anyhow!("No morphir.toml or morphir.json found"),
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
    let registry = ExtensionRegistry::new(
        ctx.project_root
            .unwrap_or_else(|| ctx.config_path.parent().unwrap().to_path_buf()),
        output_path.clone(),
    )
    .map_err(|e| CliError::Extension {
        message: format!("Failed to create extension registry: {}", e),
    })?;

    // Register builtin extensions
    let builtins = morphir_design::discover_builtin_extensions();
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

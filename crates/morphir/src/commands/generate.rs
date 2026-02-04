//! Generate command for code generation from Morphir IR

use crate::error::CliError;
use crate::output::Diagnostic;
use morphir_common::loader::load_ir;
use morphir_daemon::extensions::registry::ExtensionRegistry;
use morphir_design::{
    discover_config, ensure_morphir_structure, load_config_context, resolve_generate_output,
};
use starbase::AppResult;
use std::path::PathBuf;

/// Run the generate command
pub async fn run_generate(
    target: Option<String>,
    input: Option<String>,
    output: Option<String>,
    config_path: Option<String>,
    _project: Option<String>,
    json: bool,
    json_lines: bool,
) -> AppResult {
    use crate::output::{GenerateOutput, OutputFormat, write_output};
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

    // Determine target (from CLI or config)
    let target_lang = target
        .or_else(|| {
            ctx.config
                .codegen
                .as_ref()
                .and_then(|c| c.targets.first().cloned())
        })
        .ok_or_else(|| CliError::Config {
            error: anyhow::anyhow!("Target not specified and not found in config"),
        })?;

    // Determine project name
    let proj_name = ctx
        .current_project
        .as_ref()
        .map(|p| p.name.clone())
        .or_else(|| ctx.config.project.as_ref().map(|p| p.name.clone()))
        .unwrap_or_else(|| "default".to_string());

    // Determine IR input path
    let input_path = if let Some(inp) = input {
        PathBuf::from(inp)
    } else {
        // Default to compile output for the target language
        morphir_design::resolve_compile_output(&proj_name, &target_lang, &ctx.morphir_dir)
    };

    if !input_path.exists() {
        return Err(CliError::FileSystem {
            error: std::io::Error::new(
                std::io::ErrorKind::NotFound,
                format!("IR input path does not exist: {:?}", input_path),
            ),
        }
        .into());
    }

    // Determine output path
    let output_path = if let Some(out) = output {
        PathBuf::from(out)
    } else {
        resolve_generate_output(&proj_name, &target_lang, &ctx.morphir_dir)
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

    // Find and load extension by target
    let extension = registry
        .find_extension_by_target(&target_lang)
        .await
        .ok_or_else(|| CliError::Extension {
            message: format!("No extension found for target: {}", target_lang),
        })?;

    // Load IR (detect format)
    let ir_data = load_ir(&input_path).map_err(|e| CliError::FileSystem {
        error: std::io::Error::other(e),
    })?;

    // Call extension's generate method
    let generate_params = serde_json::json!({
        "input": input_path.to_string_lossy(),
        "output": output_path.to_string_lossy(),
        "ir": ir_data,
    });

    let result: serde_json::Value = extension
        .call("morphir.backend.generate", generate_params)
        .await
        .map_err(|e| CliError::Extension {
            message: format!("Extension generate call failed: {}", e),
        })?;

    let format = OutputFormat::from_flags(json, json_lines);

    // Extract diagnostics and artifacts from result
    let diagnostics: Vec<Diagnostic> = result
        .get("diagnostics")
        .and_then(|d| serde_json::from_value(d.clone()).ok())
        .unwrap_or_default();

    let artifacts: Vec<String> = result
        .get("artifacts")
        .and_then(|a| serde_json::from_value(a.clone()).ok())
        .unwrap_or_default();

    let success = result
        .get("success")
        .and_then(|s| s.as_bool())
        .unwrap_or(true);

    if !success {
        let error_msg = result
            .get("error")
            .and_then(|e| e.as_str())
            .unwrap_or("Code generation failed");

        if format != OutputFormat::Human {
            let output = GenerateOutput {
                success: false,
                artifacts: vec![],
                diagnostics: diagnostics.clone(),
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
        let output = GenerateOutput {
            success: true,
            artifacts,
            diagnostics,
            output_path: output_path.to_string_lossy().to_string(),
        };
        write_output(format, &output).map_err(CliError::from)?;
    } else {
        println!("Code generation successful!");
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

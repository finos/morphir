//! Generate command for code generation from Morphir IR

mod artifacts;
mod options;
mod provider;

pub use options::GenerateOptions;

use crate::error::{CliError, convert_extension_diagnostics};
use crate::home::MorphirHome;
use morphir_common::loader::load_ir;
use morphir_daemon::extensions::registry::ExtensionRegistry;
use morphir_devkit::{
    discover_config, ensure_morphir_structure, load_config_context, resolve_generate_output,
};
use morphir_distribution::list_installed;
use morphir_extension_sdk::{GenerateRequest, GenerateResult, protocol::methods};
use starbase::AppResult;
use std::path::{Path, PathBuf};

/// Run the generate command
pub async fn run_generate(options: GenerateOptions) -> AppResult<miette::Report> {
    use crate::output::{GenerateOutput, OutputFormat, write_generate_human, write_output};
    let GenerateOptions {
        target,
        input,
        output,
        config_path,
        project: _project,
        backend_options,
        json,
        json_lines,
    } = options;
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

    let configured_options = options::target_options(ctx.config.codegen.as_ref(), &target_lang)
        .map_err(|error| CliError::Config { error })?;
    let backend_options = options::merge_options(configured_options, &backend_options)
        .map_err(|error| CliError::Config { error })?;

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
        morphir_devkit::resolve_compile_output(&proj_name, &target_lang, &ctx.morphir_dir)
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

    // Load IR (detect format)
    let ir_data = load_ir(&input_path).map_err(|e| CliError::FileSystem {
        error: std::io::Error::other(e),
    })?;
    let ir_version = provider::detect_ir_major(&ir_data)?;
    let home = MorphirHome::resolve().map_err(|error| CliError::Config { error })?;
    let installed = list_installed(&home).map_err(|error| CliError::Extension {
        message: format!("Failed to list installed backend providers: {error}"),
    })?;
    let workspace = ctx
        .project_root
        .clone()
        .unwrap_or_else(|| ctx.config_path.parent().unwrap().to_path_buf());
    let request = GenerateRequest {
        ir: ir_data,
        options: serde_json::from_value(backend_options).map_err(|error| CliError::Config {
            error: error.into(),
        })?,
    };
    let result = match provider::resolve_provider(&installed, &target_lang, &ir_version)? {
        provider::ProviderRoute::Installed(installed) => {
            provider::invoke_generate(&home, installed, &workspace, request).await?
        }
        provider::ProviderRoute::LegacyBuiltin => {
            invoke_builtin(&workspace, &target_lang, request).await?
        }
    };

    let format = OutputFormat::from_flags(json, json_lines);

    let diagnostics = convert_extension_diagnostics(&result.diagnostics);

    if !result.success {
        let error_msg = "Code generation failed";
        let output = GenerateOutput {
            success: false,
            artifacts: vec![],
            diagnostics,
            output_path: output_path.to_string_lossy().to_string(),
        };
        if format == OutputFormat::Human {
            write_generate_human(&output).map_err(CliError::from)?;
        } else {
            write_output(format, &output).map_err(CliError::from)?;
        }
        return Err(CliError::Compilation {
            message: error_msg.to_string(),
        }
        .into());
    }

    let artifacts = publish_returned_artifacts(&output_path, &result.artifacts)?;

    let output = GenerateOutput {
        success: true,
        artifacts,
        diagnostics,
        output_path: output_path.to_string_lossy().to_string(),
    };
    if format == OutputFormat::Human {
        write_generate_human(&output).map_err(CliError::from)?;
    } else {
        write_output(format, &output).map_err(CliError::from)?;
    }

    Ok(None)
}

async fn invoke_builtin(
    workspace: &Path,
    target: &str,
    request: GenerateRequest,
) -> Result<GenerateResult, CliError> {
    let registry =
        ExtensionRegistry::for_restricted_generation(workspace.to_path_buf()).map_err(|error| {
            CliError::Extension {
                message: format!("Failed to create extension registry: {error}"),
            }
        })?;
    for builtin in morphir_devkit::discover_builtin_extensions() {
        if let Some(path) = builtin.path {
            registry
                .register_builtin(&builtin.id, path)
                .await
                .map_err(|error| CliError::Extension {
                    message: format!(
                        "Failed to register builtin extension '{}': {error}",
                        builtin.id
                    ),
                })?;
        }
    }
    let extension = registry
        .find_extension_by_target(target)
        .await
        .ok_or_else(|| CliError::Extension {
            message: format!("No extension found for target: {target}"),
        })?;
    extension
        .call(methods::GENERATE, request)
        .await
        .map_err(|error| CliError::Extension {
            message: format!("Extension generate call failed: {error}"),
        })
}

fn publish_returned_artifacts(
    output_path: &Path,
    returned: &[morphir_extension_sdk::Artifact],
) -> Result<Vec<String>, CliError> {
    artifacts::write_all(output_path, returned)
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_extension_sdk::Artifact;
    use tempfile::tempdir;

    #[test]
    fn returned_legacy_artifacts_are_published_by_the_host_writer() {
        let output = tempdir().unwrap();
        let returned = vec![Artifact {
            path: "nested/schema.avsc".to_owned(),
            content: "{\"type\":\"record\"}".to_owned(),
            binary: false,
        }];

        let paths = publish_returned_artifacts(output.path(), &returned).unwrap();

        assert_eq!(paths, ["nested/schema.avsc"]);
        assert_eq!(
            std::fs::read_to_string(output.path().join("nested/schema.avsc")).unwrap(),
            "{\"type\":\"record\"}"
        );
    }
}

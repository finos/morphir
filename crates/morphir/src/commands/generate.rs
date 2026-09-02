//! Generate command for code generation from Morphir IR

mod artifacts;
mod options;
mod provider;

pub use options::GenerateOptions;

use crate::commands::out_context::{OutContext, OutOverrides, report_config_warnings};
use crate::error::{CliError, convert_extension_diagnostics};
use crate::home::MorphirHome;
use morphir_common::loader::load_ir;
use morphir_devkit::{TaskId, discover_config, ensure_morphir_structure, load_config_context};
use morphir_distribution::list_installed;
use morphir_extension_sdk::GenerateRequest;
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

    report_config_warnings(&ctx);
    let out = OutContext::resolve(Some(&ctx), &OutOverrides::default(), &start_dir);

    // Determine IR input path
    let input_path = if let Some(inp) = input {
        PathBuf::from(inp)
    } else {
        // Default to the compile task's scratch directory
        out.task(&TaskId::compile()).dest
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
    let input_path = resolve_generate_input(input_path);

    // Determine output path
    let output_path = if let Some(out_path) = output {
        PathBuf::from(out_path)
    } else {
        out.prepare_dest(&TaskId::generate(&target_lang))?.dest
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
    let registry = crate::extensions::extension_registry(installed)?;
    let resolved = registry
        .resolve_backend(
            &target_lang,
            &ir_version,
            morphir_daemon::InvocationPolicy::PreferDirect,
        )
        .map_err(|error| CliError::Extension {
            message: format!("Failed to resolve backend for '{target_lang}': {error}"),
        })?;
    let workspace = ctx
        .project_root
        .clone()
        .unwrap_or_else(|| ctx.config_path.parent().unwrap().to_path_buf());
    let request = GenerateRequest {
        ir: ir_data,
        target: target_lang.clone(),
        options: serde_json::from_value(backend_options).map_err(|error| CliError::Config {
            error: error.into(),
        })?,
    };
    let result = crate::extensions::invoke_backend(&home, &workspace, &resolved, request).await?;

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

fn resolve_generate_input(path: PathBuf) -> PathBuf {
    let compiled = path.join("morphir-ir.json");
    if path.is_dir() && compiled.is_file() {
        compiled
    } else {
        path
    }
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
        let root = tempdir().unwrap();
        let output = root.path().join("output");
        let returned = vec![Artifact {
            path: "nested/schema.avsc".to_owned(),
            content: "{\"type\":\"record\"}".to_owned(),
            binary: false,
        }];

        let paths = publish_returned_artifacts(&output, &returned).unwrap();

        assert_eq!(paths, ["nested/schema.avsc"]);
        assert_eq!(
            std::fs::read_to_string(output.join("nested/schema.avsc")).unwrap(),
            "{\"type\":\"record\"}"
        );
    }

    #[test]
    fn compile_output_directory_resolves_its_host_written_ir_file() {
        let root = tempdir().unwrap();
        let compiled = root.path().join("compiled");
        std::fs::create_dir_all(&compiled).unwrap();
        std::fs::write(compiled.join("morphir-ir.json"), "{}").unwrap();

        assert_eq!(
            resolve_generate_input(compiled.clone()),
            compiled.join("morphir-ir.json")
        );
    }

    #[test]
    fn ordinary_document_tree_directory_stays_a_directory() {
        let root = tempdir().unwrap();
        let document_tree = root.path().join("document-tree");
        std::fs::create_dir_all(&document_tree).unwrap();

        let resolved = resolve_generate_input(document_tree.clone());
        let ir = load_ir(&resolved).unwrap();

        assert_eq!(resolved, document_tree);
        assert_eq!(ir["formatVersion"], 4);
    }
}

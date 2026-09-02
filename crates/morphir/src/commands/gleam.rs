//! Gleam-specific subcommands

use crate::commands::compile::CompileOptions;
use crate::commands::out_context::{OutContext, OutOverrides};
use crate::commands::{GenerateOptions, run_compile, run_generate};
use crate::error::CliError;
use morphir_devkit::{TaskId, discover_config, load_config_context};
use starbase::AppResult;
use std::path::PathBuf;

/// Run Gleam compile command (convenience wrapper)
#[allow(clippy::too_many_arguments)]
pub async fn run_gleam_compile(
    out: OutOverrides,
    input: Option<String>,
    output: Option<String>,
    package_name: Option<String>,
    config_path: Option<String>,
    project: Option<String>,
    json: bool,
    json_lines: bool,
) -> AppResult<miette::Report> {
    run_compile(CompileOptions {
        language: Some("gleam".to_string()), // Set language to gleam
        extension: None,
        input,
        output,
        package_name,
        config_path,
        project,
        json,
        json_lines,
        out,
    })
    .await
}

/// Run Gleam generate command (convenience wrapper)
pub async fn run_gleam_generate(
    out: OutOverrides,
    input: Option<String>,
    output: Option<String>,
    config_path: Option<String>,
    project: Option<String>,
    json: bool,
    json_lines: bool,
) -> AppResult<miette::Report> {
    run_generate(GenerateOptions {
        target: Some("gleam".to_string()), // Set target to gleam
        input,
        output,
        config_path,
        project,
        backend_options: Vec::new(),
        json,
        json_lines,
        out,
    })
    .await
}

/// Run Gleam roundtrip (compile then generate)
#[allow(clippy::too_many_arguments)]
pub async fn run_gleam_roundtrip(
    out: OutOverrides,
    input: Option<String>,
    output: Option<String>,
    package_name: Option<String>,
    config_path: Option<String>,
    project: Option<String>,
    json: bool,
    json_lines: bool,
) -> AppResult<miette::Report> {
    let generate_input = package_name
        .as_deref()
        .map(|package_name| roundtrip_compile_output(&out, package_name, config_path.as_deref()))
        .transpose()?
        .map(|path| path.to_string_lossy().into_owned());
    run_gleam_compile(
        out.clone(),
        input,
        None,
        package_name,
        config_path.clone(),
        project.clone(),
        json,
        json_lines,
    )
    .await?;

    run_gleam_generate(
        out,
        generate_input,
        output,
        config_path,
        project,
        json,
        json_lines,
    )
    .await
}

fn roundtrip_compile_output(
    out: &OutOverrides,
    _package_name: &str,
    config_path: Option<&str>,
) -> Result<PathBuf, CliError> {
    let start_dir = std::env::current_dir().map_err(|error| CliError::FileSystem { error })?;
    let config_file = if let Some(config_path) = config_path {
        PathBuf::from(config_path)
    } else {
        discover_config(&start_dir)
            .map_err(|error| CliError::Config { error })?
            .ok_or_else(|| CliError::Config {
                error: anyhow::anyhow!("No morphir.toml, morphir.yaml, or morphir.json found"),
            })?
    };
    let context = load_config_context(&config_file).map_err(|error| CliError::Config { error })?;
    Ok(OutContext::resolve(Some(&context), out, &start_dir)
        .task(&TaskId::compile())
        .dest)
}

//! Gleam-specific subcommands

use crate::commands::compile::CompileOptions;
use crate::commands::{run_compile, run_generate};
use starbase::AppResult;

/// Run Gleam compile command (convenience wrapper)
pub async fn run_gleam_compile(
    input: Option<String>,
    output: Option<String>,
    package_name: Option<String>,
    config_path: Option<String>,
    project: Option<String>,
    json: bool,
    json_lines: bool,
) -> AppResult {
    run_compile(CompileOptions {
        language: Some("gleam".to_string()), // Set language to gleam
        input,
        output,
        package_name,
        config_path,
        project,
        json,
        json_lines,
    })
    .await
}

/// Run Gleam generate command (convenience wrapper)
pub async fn run_gleam_generate(
    input: Option<String>,
    output: Option<String>,
    config_path: Option<String>,
    project: Option<String>,
    json: bool,
    json_lines: bool,
) -> AppResult {
    run_generate(
        Some("gleam".to_string()), // Set target to gleam
        input,
        output,
        config_path,
        project,
        json,
        json_lines,
    )
    .await
}

/// Run Gleam roundtrip (compile then generate)
pub async fn run_gleam_roundtrip(
    input: Option<String>,
    output: Option<String>,
    package_name: Option<String>,
    config_path: Option<String>,
    project: Option<String>,
    json: bool,
    json_lines: bool,
) -> AppResult {
    // First compile
    let compile_output = output.clone().or_else(|| {
        // Use default compile output path
        Some(".morphir/out/default/compile/gleam".to_string())
    });

    run_gleam_compile(
        input.clone(),
        compile_output.clone(),
        package_name.clone(),
        config_path.clone(),
        project.clone(),
        json,
        json_lines,
    )
    .await?;

    // Then generate from the compile output
    run_gleam_generate(
        compile_output,
        output,
        config_path,
        project,
        json,
        json_lines,
    )
    .await
}

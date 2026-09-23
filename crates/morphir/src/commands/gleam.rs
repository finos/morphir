//! Gleam-specific subcommands

use crate::commands::out_context::OutOverrides;
use crate::commands::{GenerateOptions, run_compile, run_generate};
use starbase::AppResult;

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
        from_partial_compile: false,
        json,
        json_lines,
        out,
    })
    .await
}

/// Run Gleam roundtrip: the compile `startup` prepared, then generate.
///
/// The generate half consumes the compile this same command just ran, so a
/// selection it compiled is acknowledged rather than refused.
pub async fn run_gleam_roundtrip(
    out: OutOverrides,
    output: Option<String>,
    config_path: Option<String>,
    project: Option<String>,
    json: bool,
    json_lines: bool,
    ready: &crate::SessionReady,
) -> AppResult<miette::Report> {
    run_compile(ready).await?;

    run_generate(GenerateOptions {
        target: Some("gleam".to_string()),
        input: None,
        output,
        config_path,
        project,
        backend_options: Vec::new(),
        from_partial_compile: true,
        json,
        json_lines,
        out,
    })
    .await
}

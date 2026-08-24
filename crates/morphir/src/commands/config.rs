//! Config command for inspecting the effective Morphir configuration

use crate::error::CliError;
use crate::output::{OutputFormat, write_output};
use morphir_design::{
    ConfigLoadOptions, ConfigSource, ConfigSourceStatus, EffectiveConfig, discover_config,
    load_effective_config,
};
use serde::Serialize;
use starbase::AppResult;
use std::path::PathBuf;

/// Output of `morphir config path`
#[derive(Debug, Serialize)]
pub struct ConfigPathOutput {
    /// Project configuration that anchored the lookup, if any
    pub project_config: Option<PathBuf>,
    /// Sources considered, from lowest to highest precedence
    pub sources: Vec<ConfigSource>,
}

/// Output of `morphir config show`
#[derive(Debug, Serialize)]
pub struct ConfigShowOutput {
    /// Project configuration that anchored the lookup, if any
    pub project_config: Option<PathBuf>,
    /// Effective configuration value
    pub config: serde_json::Value,
}

fn resolve_project_config(config_path: Option<String>) -> Result<Option<PathBuf>, CliError> {
    match config_path {
        Some(path) => Ok(Some(PathBuf::from(path))),
        None => {
            let start_dir =
                std::env::current_dir().map_err(|error| CliError::FileSystem { error })?;
            discover_config(&start_dir).map_err(|error| CliError::Config { error })
        }
    }
}

fn load(config_path: Option<String>) -> Result<(Option<PathBuf>, EffectiveConfig), CliError> {
    let project_config = resolve_project_config(config_path)?;
    let effective = load_effective_config(project_config.as_deref(), &ConfigLoadOptions::default())
        .map_err(|error| CliError::Config { error })?;
    Ok((project_config, effective))
}

/// Show which configuration sources were considered
pub fn run_config_path(config_path: Option<String>, json: bool) -> AppResult<miette::Report> {
    let (project_config, effective) = load(config_path)?;
    let format = OutputFormat::from_flags(json, false);

    if format == OutputFormat::Human {
        print_sources(&effective.sources);
    } else {
        let output = ConfigPathOutput {
            project_config,
            sources: effective.sources,
        };
        write_output(format, &output).map_err(CliError::from)?;
    }

    Ok(None)
}

fn print_sources(sources: &[ConfigSource]) {
    println!("Configuration sources (in priority order):");
    println!();
    for source in sources.iter().rev() {
        let marker = match source.status {
            ConfigSourceStatus::Loaded => "✓",
            ConfigSourceStatus::NotFound | ConfigSourceStatus::Skipped => "✗",
        };
        println!("  [{marker}] {}", source.kind.name());
        println!("      Path: {}", source.location());
        println!("      Status: {}", source.status.label());
        println!("      Priority: {}", source.priority);
        println!();
    }
}

/// Show the effective configuration after merging every source
pub fn run_config_show(config_path: Option<String>, json: bool) -> AppResult<miette::Report> {
    let (project_config, effective) = load(config_path)?;
    let format = OutputFormat::from_flags(json, false);

    if format == OutputFormat::Human {
        let rendered =
            toml::to_string_pretty(&effective.value).map_err(|error| CliError::Config {
                error: anyhow::anyhow!("Failed to render effective configuration as TOML: {error}"),
            })?;
        print!("{rendered}");
    } else {
        let output = ConfigShowOutput {
            project_config,
            config: effective.value,
        };
        write_output(format, &output).map_err(CliError::from)?;
    }

    Ok(None)
}

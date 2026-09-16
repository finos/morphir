//! Config command for inspecting the effective Morphir configuration

use crate::error::CliError;
use crate::output::{OutputFormat, write_output};
use morphir_common::config::redact_secrets;
use morphir_devkit::{
    ConfigLoadOptions, ConfigSource, ConfigSourceStatus, EffectiveConfig, EnvSelection,
    discover_config, load_effective_config,
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

/// Output of `morphir config get --json`
#[derive(Debug, Serialize)]
pub struct ConfigGetOutput {
    /// Dotted key used for the lookup
    pub key: String,
    /// Effective configuration value
    pub value: serde_json::Value,
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

fn load(
    config_path: Option<String>,
    options: &ConfigLoadOptions,
) -> Result<(Option<PathBuf>, EffectiveConfig), CliError> {
    let project_config = resolve_project_config(config_path)?;
    let effective = load_effective_config(project_config.as_deref(), options)
        .map_err(|error| CliError::Config { error })?;
    Ok((project_config, effective))
}

fn load_options(isolated: bool) -> ConfigLoadOptions {
    if isolated {
        ConfigLoadOptions {
            env: EnvSelection::Process,
            ..ConfigLoadOptions::project_only()
        }
    } else {
        ConfigLoadOptions::default()
    }
}

/// Get one value from the effective configuration.
///
/// The key uses dot-separated object names. Secrets are redacted before the
/// lookup so that fetching a containing object is safe too.
pub fn run_config_get(
    key: String,
    config_path: Option<String>,
    json: bool,
    isolated: bool,
) -> AppResult<miette::Report> {
    let options = load_options(isolated);
    run_config_get_with_options(key, config_path, json, &options)
}

/// Get a configuration value with an explicit source-selection policy.
pub fn run_config_get_with_options(
    key: String,
    config_path: Option<String>,
    json: bool,
    options: &ConfigLoadOptions,
) -> AppResult<miette::Report> {
    let (_, effective) = load(config_path, options)?;
    let config = redact_secrets(&effective.value);
    let value = get_by_dotted_key(&config, &key)
        .cloned()
        .ok_or_else(|| CliError::Config {
            error: anyhow::anyhow!("Configuration key not found: {key}"),
        })?;

    if json {
        write_output(OutputFormat::Json, &ConfigGetOutput { key, value })
            .map_err(CliError::from)?;
    } else {
        println!("{}", render_human_value(&value)?);
    }

    Ok(None)
}

fn get_by_dotted_key<'a>(
    config: &'a serde_json::Value,
    key: &str,
) -> Option<&'a serde_json::Value> {
    if key.is_empty() {
        return None;
    }

    key.split('.').try_fold(config, |value, segment| {
        if segment.is_empty() {
            None
        } else {
            value.as_object()?.get(segment)
        }
    })
}

fn render_human_value(value: &serde_json::Value) -> Result<String, CliError> {
    match value {
        serde_json::Value::String(value) => Ok(value.clone()),
        value => serde_json::to_string(value).map_err(|error| CliError::Config {
            error: anyhow::anyhow!("Failed to render configuration value: {error}"),
        }),
    }
}

/// Show which configuration sources were considered
pub fn run_config_path(
    config_path: Option<String>,
    json: bool,
    isolated: bool,
) -> AppResult<miette::Report> {
    let options = load_options(isolated);
    run_config_path_with_options(config_path, json, &options)
}

/// Show configuration sources with an explicit source-selection policy.
pub fn run_config_path_with_options(
    config_path: Option<String>,
    json: bool,
    options: &ConfigLoadOptions,
) -> AppResult<miette::Report> {
    let (project_config, effective) = load(config_path, options)?;
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

/// Show the effective configuration after merging every source.
///
/// Credentials (tokens, passwords, secrets, API keys) are redacted before
/// anything is printed, in both the human and JSON forms.
pub fn run_config_show(
    config_path: Option<String>,
    json: bool,
    isolated: bool,
) -> AppResult<miette::Report> {
    let options = load_options(isolated);
    run_config_show_with_options(config_path, json, &options)
}

/// Show effective configuration with an explicit source-selection policy.
pub fn run_config_show_with_options(
    config_path: Option<String>,
    json: bool,
    options: &ConfigLoadOptions,
) -> AppResult<miette::Report> {
    let (project_config, effective) = load(config_path, options)?;
    let format = OutputFormat::from_flags(json, false);
    let config = redact_secrets(&effective.value);

    if format == OutputFormat::Human {
        let rendered = toml::to_string_pretty(&config_as_toml(&config)?).map_err(|error| {
            CliError::Config {
                error: anyhow::anyhow!("Failed to render effective configuration as TOML: {error}"),
            }
        })?;
        print!("{rendered}");
    } else {
        let output = ConfigShowOutput {
            project_config,
            config,
        };
        write_output(format, &output).map_err(CliError::from)?;
    }

    Ok(None)
}

/// Rewrites the effective configuration into TOML's own value model.
///
/// `morphir-core` turns on serde_json's `arbitrary_precision`, and Cargo
/// unifies features across the build, so every `serde_json::Number` in this
/// binary serializes as the internal one-member map `{"$serde_json::private::
/// Number": "3"}`. Only serde_json's own serializer understands that map;
/// handing a `Value` straight to the TOML serializer leaks it into what a
/// reader sees. Walking the value here keeps `config show` printing `3`.
fn config_as_toml(value: &serde_json::Value) -> Result<toml::Value, CliError> {
    config_as_toml_at(value, "<config>")
}

/// `path` is the dotted/indexed key of `value` within the effective
/// configuration, threaded through the recursion so an error can name where
/// the offending value lives rather than just what it is.
fn config_as_toml_at(value: &serde_json::Value, path: &str) -> Result<toml::Value, CliError> {
    match value {
        // TOML has no null, and the configuration model has no optional value
        // that reaches this far, so this is a loader bug rather than user input.
        serde_json::Value::Null => Err(CliError::Config {
            error: anyhow::anyhow!(
                "Failed to render effective configuration as TOML: \
                 TOML cannot represent a null at {path}"
            ),
        }),
        serde_json::Value::Bool(bool) => Ok(toml::Value::Boolean(*bool)),
        serde_json::Value::Number(number) => {
            if let Some(integer) = number.as_i64() {
                return Ok(toml::Value::Integer(integer));
            }
            // `morphir-core` turns on serde_json's arbitrary_precision, which keeps
            // the exact source lexeme behind every `Number`. A lexeme with neither a
            // decimal point nor an exponent marker is an integer literal, not a
            // float that happens to be round, so it must not fall through to
            // `as_f64()`: that would silently round a too-large integer into a
            // different, smaller-looking configuration instead of reporting the
            // range error TOML actually has for it.
            let lexeme = number.to_string();
            if !lexeme.contains(['.', 'e', 'E']) {
                return Err(CliError::Config {
                    error: anyhow::anyhow!(
                        "Failed to render effective configuration as TOML: \
                         configuration integer is outside TOML's 64-bit range \
                         at {path}: {lexeme}"
                    ),
                });
            }
            number
                .as_f64()
                .map(toml::Value::Float)
                .ok_or_else(|| CliError::Config {
                    error: anyhow::anyhow!(
                        "Failed to render effective configuration as TOML: \
                     {number} at {path} is outside the range TOML can represent"
                    ),
                })
        }
        serde_json::Value::String(string) => Ok(toml::Value::String(string.clone())),
        serde_json::Value::Array(items) => items
            .iter()
            .enumerate()
            .map(|(index, item)| config_as_toml_at(item, &format!("{path}[{index}]")))
            .collect::<Result<Vec<_>, _>>()
            .map(toml::Value::Array),
        serde_json::Value::Object(members) => members
            .iter()
            .map(|(name, member)| {
                Ok((
                    name.clone(),
                    config_as_toml_at(member, &format!("{path}.{name}"))?,
                ))
            })
            .collect::<Result<toml::map::Map<_, _>, CliError>>()
            .map(toml::Value::Table),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_devkit::SourceSelection;

    #[test]
    fn isolated_mode_only_reads_project_and_controlled_environment_sources() {
        let options = load_options(true);

        assert_eq!(options.system, SourceSelection::Skip);
        assert_eq!(options.global, SourceSelection::Skip);
        assert_eq!(options.user_override, SourceSelection::Skip);
        assert_eq!(options.env, EnvSelection::Process);
    }

    #[test]
    fn rendered_toml_spells_numbers_as_numbers() {
        // serde_json's arbitrary_precision is on across this build, so a number
        // handed straight to the TOML serializer would come out as the internal
        // `$serde_json::private::Number` map instead of as `3`.
        let config = serde_json::json!({
            "ir": { "format_version": 3, "tolerance": 0.5, "strict_mode": false },
            "codegen": { "targets": ["go"] },
        });

        let rendered = toml::to_string_pretty(&config_as_toml(&config).unwrap()).unwrap();

        assert!(rendered.contains("format_version = 3"), "{rendered}");
        assert!(rendered.contains("tolerance = 0.5"), "{rendered}");
        assert!(rendered.contains("strict_mode = false"), "{rendered}");
        assert!(rendered.contains("\"go\""), "{rendered}");
        assert!(!rendered.contains("serde_json"), "{rendered}");
    }

    #[test]
    fn integers_outside_tomls_i64_range_are_rejected_rather_than_rounded() {
        // 18446744073709551615 is u64::MAX: `as_i64()` fails, and `as_f64()` would
        // otherwise succeed and silently round it into a different, smaller-looking
        // configuration instead of reporting that TOML cannot hold it.
        let config = serde_json::json!({ "huge": 18446744073709551615u64 });

        let CliError::Config { error } = config_as_toml(&config).unwrap_err() else {
            panic!("expected a Config error");
        };
        let error = error.to_string();

        assert!(
            error.contains("configuration integer is outside TOML's 64-bit range"),
            "{error}"
        );
        assert!(error.contains("<config>.huge"), "{error}");
        assert!(error.contains("18446744073709551615"), "{error}");
    }

    #[test]
    fn fractional_numbers_still_render_as_floats() {
        let config = serde_json::json!({ "tolerance": 1.0e300 });

        let rendered = toml::to_string_pretty(&config_as_toml(&config).unwrap()).unwrap();

        assert!(rendered.starts_with("tolerance = 1"), "{rendered}");
    }

    #[test]
    fn standard_mode_discovers_all_configuration_sources() {
        assert_eq!(load_options(false), ConfigLoadOptions::default());
    }

    #[test]
    fn dotted_key_lookup_descends_through_objects() {
        let config = serde_json::json!({
            "project": {
                "name": "example"
            }
        });

        assert_eq!(
            get_by_dotted_key(&config, "project.name"),
            Some(&serde_json::json!("example"))
        );
        assert_eq!(get_by_dotted_key(&config, "project.missing"), None);
        assert_eq!(get_by_dotted_key(&config, "project.name.part"), None);
        assert_eq!(get_by_dotted_key(&config, "project..name"), None);
    }

    #[test]
    fn human_values_print_strings_without_json_quotes() {
        assert_eq!(
            render_human_value(&serde_json::json!("example")).unwrap(),
            "example"
        );
        assert_eq!(
            render_human_value(&serde_json::json!({"enabled": true})).unwrap(),
            r#"{"enabled":true}"#
        );
    }

    #[test]
    fn lookup_can_only_observe_redacted_secrets() {
        let config = serde_json::json!({
            "registry": {
                "token": "top-secret-token",
                "endpoint": "https://registry.example.test"
            }
        });
        let redacted = redact_secrets(&config);

        assert_eq!(
            get_by_dotted_key(&redacted, "registry.token"),
            Some(&serde_json::json!("<redacted>"))
        );
        assert_eq!(
            get_by_dotted_key(&redacted, "registry"),
            Some(&serde_json::json!({
                "token": "<redacted>",
                "endpoint": "https://registry.example.test"
            }))
        );
    }
}

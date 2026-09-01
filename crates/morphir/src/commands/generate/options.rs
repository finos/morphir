use anyhow::{Context, Result, anyhow, bail};
use morphir_common::config::model::CodegenSection;
use serde_json::{Map, Value};

/// Options shared by all code generation backends.
#[derive(Debug, Clone, Default)]
pub struct GenerateOptions {
    /// Target language or format.
    pub target: Option<String>,
    /// Morphir IR input path.
    pub input: Option<String>,
    /// Generated artifact output path.
    pub output: Option<String>,
    /// Explicit Morphir configuration path.
    pub config_path: Option<String>,
    /// Project name for workspace configurations.
    pub project: Option<String>,
    /// Backend-specific `KEY=VALUE` overrides.
    pub backend_options: Vec<String>,
    /// Emit JSON output.
    pub json: bool,
    /// Emit JSON Lines output.
    pub json_lines: bool,
}

pub(super) fn target_options(codegen: Option<&CodegenSection>, target: &str) -> Result<Value> {
    let Some(setting) = codegen.and_then(|codegen| codegen.settings.get(target)) else {
        return Ok(Value::Object(Map::new()));
    };
    let toml::Value::Table(table) = setting else {
        bail!("Target setting [codegen.{target}] must be a table");
    };

    serde_json::to_value(table)
        .with_context(|| format!("Failed to convert [codegen.{target}] to backend options"))
}

pub(super) fn merge_options(configured: Value, cli_options: &[String]) -> Result<Value> {
    let Value::Object(mut merged) = configured else {
        bail!("Target configuration must be a JSON object");
    };

    for option in cli_options {
        let (key, value) = parse_option(option)?;
        merged.insert(key, value);
    }

    Ok(Value::Object(merged))
}

pub(super) fn parse_option(option: &str) -> Result<(String, Value)> {
    let (key, raw_value) = option
        .split_once('=')
        .ok_or_else(|| anyhow!("Backend option '{option}' must use KEY=VALUE"))?;
    let key = key.trim();
    if key.is_empty() {
        bail!("Backend option key cannot be empty");
    }

    let value =
        serde_json::from_str(raw_value).unwrap_or_else(|_| Value::String(raw_value.to_owned()));
    Ok((key.to_owned(), value))
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_common::config::model::CodegenSection;
    use serde_json::json;
    use std::collections::HashMap;

    #[test]
    fn cli_values_parse_as_json_then_fall_back_to_strings() {
        assert_eq!(
            parse_option("logical_types=false").unwrap(),
            ("logical_types".into(), json!(false))
        );
        assert_eq!(
            parse_option("decimal_precision=28").unwrap(),
            ("decimal_precision".into(), json!(28))
        );
        assert_eq!(
            parse_option("representation=idl").unwrap(),
            ("representation".into(), json!("idl"))
        );
        assert_eq!(
            parse_option("type_mappings={\"Acme.Id\":{\"type\":\"string\"}}")
                .unwrap()
                .1,
            json!({"Acme.Id": {"type": "string"}})
        );
    }

    /// `parse_option` tries JSON before falling back to a string, so a
    /// value that happens to be a valid JSON number reaches the backend as a
    /// number. `3.0` and `3.1` are exactly that, while the OpenAPI backend's
    /// `version` option only accepts the strings `"3.1"` and `"3.0"` — so
    /// `--option version=3.0` fails with `JSC002` and the user has to write
    /// `--option 'version="3.0"'`. This is deliberate rather than accidental:
    /// a JSON number cannot tell `3.1` from `3.10`, and the JSON-first rule
    /// is what lets `error_status=422` and `logical_types=false` arrive as a
    /// number and a Boolean without per-option knowledge here. Pinned so the
    /// quoting requirement `docs/generate/openapi.md` documents cannot drift
    /// away from what the parser actually does.
    #[test]
    fn a_bare_version_value_parses_as_a_number_and_a_quoted_one_as_a_string() {
        assert_eq!(parse_option("version=3.0").unwrap().1, json!(3.0));
        assert_eq!(parse_option("version=3.1").unwrap().1, json!(3.1));
        assert_eq!(
            parse_option("version=\"3.0\"").unwrap().1,
            json!("3.0"),
            "quoting the value is what makes it reach the backend as a string"
        );
    }

    #[test]
    fn cli_options_override_target_config_and_last_duplicate_wins() {
        let configured = json!({"representation": "json", "projection": "schemas"});
        let merged = merge_options(
            configured,
            &["representation=idl".into(), "representation=json".into()],
        )
        .unwrap();

        assert_eq!(merged["representation"], "json");
        assert_eq!(merged["projection"], "schemas");
    }

    #[test]
    fn empty_cli_option_key_is_rejected() {
        let error = parse_option("=value").unwrap_err();

        assert!(error.to_string().contains("key cannot be empty"), "{error}");
    }

    #[test]
    fn cli_option_without_equals_is_rejected() {
        let error = parse_option("representation").unwrap_err();

        assert!(error.to_string().contains("KEY=VALUE"), "{error}");
    }

    #[test]
    fn target_table_is_converted_to_json() {
        let codegen = codegen_with_setting(
            "avro",
            toml::Value::Table(toml::Table::from_iter([
                ("representation".into(), toml::Value::String("idl".into())),
                ("logical_types".into(), toml::Value::Boolean(false)),
            ])),
        );

        assert_eq!(
            target_options(Some(&codegen), "avro").unwrap(),
            json!({"representation": "idl", "logical_types": false})
        );
    }

    #[test]
    fn absent_target_setting_produces_empty_options() {
        let codegen = codegen_with_setting("scala", toml::Value::Table(toml::Table::new()));

        assert_eq!(target_options(Some(&codegen), "avro").unwrap(), json!({}));
        assert_eq!(target_options(None, "avro").unwrap(), json!({}));
    }

    #[test]
    fn target_setting_that_is_not_a_table_is_rejected() {
        let codegen = codegen_with_setting("avro", toml::Value::String("idl".into()));
        let error = target_options(Some(&codegen), "avro").unwrap_err();

        assert!(error.to_string().contains("must be a table"), "{error}");
    }

    fn codegen_with_setting(target: &str, value: toml::Value) -> CodegenSection {
        CodegenSection {
            targets: vec![target.into()],
            output_format: "pretty".into(),
            settings: HashMap::from([(target.into(), value)]),
        }
    }
}

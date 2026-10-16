//! Admission of MCK infrastructure envelopes and observations only. Native frame
//! bytes remain opaque to the shared runner; production adapters own decoding.

use serde::Deserialize;
use serde_json::{Value, json};
use std::sync::OnceLock;

pub(super) const INVALID_CODES: [&str; 6] = [
    "native.frame.limit",
    "native.frame.utf8",
    "native.frame.json",
    "native.frame.shape",
    "native.frame.model",
    "native.frame.arguments",
];

#[derive(Deserialize)]
#[serde(rename_all = "lowercase")]
enum Encoding {
    Utf8,
    Hex,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Input {
    encoding: Encoding,
    source: String,
    #[serde(default, deserialize_with = "present_generation")]
    generate: Option<Generation>,
}

fn present_generation<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Generation>, D::Error> {
    Generation::deserialize(deserializer).map(Some)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Generation {
    prefix: Prefix,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Prefix {
    repeat: String,
    #[serde(deserialize_with = "count")]
    count: u64,
}

fn count<'de, D: serde::Deserializer<'de>>(deserializer: D) -> Result<u64, D::Error> {
    let value = Value::deserialize(deserializer)?;
    value
        .as_number()
        .and_then(|number| exact_count(&number.to_string()))
        .ok_or_else(|| {
            serde::de::Error::custom("prefix count must be a bounded nonnegative integer")
        })
}

/// Interpret the original decimal token, never a rounded floating-point value.
/// The result is bounded before multiplication; exponent size cannot allocate.
fn exact_count(token: &str) -> Option<u64> {
    let negative = token.starts_with('-');
    let unsigned = token.strip_prefix('-').unwrap_or(token);
    let (mantissa, exponent) = unsigned.split_once(['e', 'E']).unwrap_or((unsigned, "0"));
    let fraction = mantissa.split_once('.').map_or(0, |(_, right)| right.len());
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    let significant = digits.trim_start_matches('0');
    if significant.is_empty() {
        return Some(0);
    }
    if negative {
        return None;
    }
    let exponent = exponent.parse::<i64>().ok()?;
    let scale = exponent.checked_sub(i64::try_from(fraction).ok()?)?;
    let integer_digits = significant.trim_end_matches('0');
    let zeros = significant.len() - integer_digits.len();
    let scale = scale.checked_add(i64::try_from(zeros).ok()?)?;
    if scale < 0 || integer_digits.len() as u64 + scale as u64 > 7 {
        return None;
    }
    let value = integer_digits.parse::<u64>().ok()? * 10_u64.pow(scale as u32);
    (value <= 1_048_576).then_some(value)
}

pub(super) fn validate_input(value: &Value) -> Result<(), String> {
    if let Some(count) = value.pointer("/generate/prefix/count")
        && !count.is_number()
    {
        return Err("native frame prefix count must be a number".into());
    }
    let input: Input = serde_json::from_value(value.clone())
        .map_err(|e| format!("native frame compact input: {e}"))?;
    let source_bytes = match input.encoding {
        Encoding::Utf8 => input.source.len(),
        Encoding::Hex => {
            if !input.source.len().is_multiple_of(2)
                || !input.source.bytes().all(|b| b.is_ascii_hexdigit())
            {
                return Err("native frame source must be complete hexadecimal byte pairs".into());
            }
            input.source.len() / 2
        }
    };
    let prefix_bytes = match input.generate {
        None => 0,
        Some(generation) => {
            if generation.prefix.repeat != " " || generation.prefix.count > 1_048_576 {
                return Err(
                    "native frame generation requires ASCII space and count 0..1048576".into(),
                );
            }
            generation.prefix.count as usize
        }
    };
    if source_bytes
        .checked_add(prefix_bytes)
        .is_none_or(|n| n > 2_097_152)
    {
        return Err("native frame materialization exceeds 2 MiB".into());
    }
    Ok(())
}

/// Admit infrastructure shape from literal JSON token kinds before any nested
/// serde Value deserialization. The schema never examines native source text.
fn schema_validator(schema: &str) -> jsonschema::Validator {
    let mut options = jsonschema::options();
    options.with_retriever(super::contract::OfflineOnly);
    for text in [
        include_str!("../../../../spec/workbench/draft.7/schemas/mck-input.schema.json"),
        include_str!(
            "../../../../spec/workbench/draft.7/schemas/native-frame-projection.schema.json"
        ),
        include_str!("../../../../spec/workbench/draft.7/schemas/mck-observation.schema.json"),
        include_str!("../../../../spec/workbench/draft.7/schemas/mck-capabilities.schema.json"),
    ] {
        let value: Value = serde_json::from_str(text).expect("native MCK schema JSON");
        options.with_resource(
            value["$id"].as_str().expect("native MCK schema id"),
            jsonschema::Resource::from_contents(value.clone()).expect("native MCK schema resource"),
        );
    }
    let value: Value = serde_json::from_str(schema).expect("native MCK schema JSON");
    options.build(&value).expect("native MCK schema")
}

fn validate_shape(
    value: &Value,
    validator: &jsonschema::Validator,
    label: &str,
) -> Result<(), String> {
    validator.validate(value).map_err(|error| {
        format!(
            "invalid native frame {label} shape at {}: {error}",
            error.instance_path
        )
    })
}

pub(super) fn validate_corpus_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    validate_shape(
        value,
        VALIDATOR.get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.7/schemas/mck-corpus.schema.json"
            ))
        }),
        "corpus",
    )
}

pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    validate_shape(
        value,
        VALIDATOR.get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.7/schemas/mck-observation.schema.json"
            ))
        }),
        "observation",
    )
}

pub(super) fn validate_report_shape(value: &Value) -> Result<(), String> {
    static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
    validate_shape(
        value,
        VALIDATOR.get_or_init(|| {
            schema_validator(include_str!(
                "../../../../spec/workbench/draft.7/schemas/mck-report.schema.json"
            ))
        }),
        "report",
    )
}

pub(super) fn projection(value: &Value) -> Result<Value, String> {
    if value != &json!({"frameAccepted":true}) {
        return Err("invalid native frame projection".into());
    }
    Ok(value.clone())
}

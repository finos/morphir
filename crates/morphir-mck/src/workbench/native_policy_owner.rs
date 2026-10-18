//! Owner fixture infrastructure and fixed projection comparison only. The runner
//! never decodes native replies, model source, or production owner transitions.
use base64::Engine;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::OnceLock;

fn schema_validator(schema: &str) -> jsonschema::Validator {
    let mut options = jsonschema::options();
    options.with_retriever(super::contract::OfflineOnly);
    for text in [
        include_str!("../../../../spec/workbench/schemas/value.schema.json"),
        include_str!("../../../../spec/workbench/schemas/outcome-value.schema.json"),
        include_str!("../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/value-type.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/definitions.schema.json"),
        include_str!("../../../../spec/workbench/draft.3/schemas/manifest.schema.json"),
        include_str!(
            "../../../../spec/workbench/executions/0.2.0-draft.1/schemas/identity.schema.json"
        ),
        include_str!(
            "../../../../spec/workbench/execution-plan/0.2.0-draft.1/schemas/plan.schema.json"
        ),
        include_str!("../../../../spec/workbench/admission/draft.1/schemas/selection.schema.json"),
        include_str!("../../../../spec/workbench/draft.22/schemas/mck-input.schema.json"),
        include_str!(
            "../../../../spec/workbench/draft.22/schemas/native-owner-projection.schema.json"
        ),
        include_str!(
            "../../../../spec/workbench/draft.22/schemas/native-owner-expectation.schema.json"
        ),
        include_str!("../../../../spec/workbench/draft.22/schemas/mck-observation.schema.json"),
        include_str!("../../../../spec/workbench/draft.22/schemas/mck-expectation.schema.json"),
        include_str!("../../../../spec/workbench/draft.22/schemas/mck-capabilities.schema.json"),
    ] {
        let value: Value = serde_json::from_str(text).expect("native owner MCK schema JSON");
        options.with_resource(
            value["$id"].as_str().expect("native owner MCK schema id"),
            jsonschema::Resource::from_contents(value.clone()).expect("schema resource"),
        );
    }
    let value: Value = serde_json::from_str(schema).expect("native owner MCK schema JSON");
    options.build(&value).expect("native owner MCK schema")
}

macro_rules! shape_validator {
    ($name:ident, $schema:literal) => {
        pub(super) fn $name(value: &Value) -> Result<(), String> {
            check_integer_tokens(value)?;
            static VALIDATOR: OnceLock<jsonschema::Validator> = OnceLock::new();
            VALIDATOR
                .get_or_init(|| schema_validator(include_str!($schema)))
                .validate(value)
                .map_err(|e| {
                    format!(
                        "invalid native owner {} at {}: {e}",
                        stringify!($name),
                        e.instance_path
                    )
                })
        }
    };
}

/// JSON Schema numeric checks may round arbitrary-precision decimal tokens.
/// Infrastructure contains bounded integers only; completion outcomes remain
/// opaque and are admitted by the production execution host instead.
fn check_integer_tokens(value: &Value) -> Result<(), String> {
    match value {
        Value::Number(number) => {
            if exact_integer(&number.to_string()).is_none() {
                return Err("native owner infrastructure requires exact bounded integers".into());
            }
        }
        Value::Array(items) => {
            for item in items {
                check_integer_tokens(item)?;
            }
        }
        Value::Object(fields) => {
            for (name, child) in fields {
                if name != "outcomes" {
                    check_integer_tokens(child)?;
                }
            }
        }
        _ => {}
    }
    Ok(())
}

fn exact_integer(token: &str) -> Option<u64> {
    let unsigned = token.strip_prefix('-').unwrap_or(token);
    let (mantissa, exponent) = unsigned.split_once(['e', 'E']).unwrap_or((unsigned, "0"));
    let fraction = mantissa.split_once('.').map_or(0, |(_, right)| right.len());
    let digits: String = mantissa.chars().filter(|c| *c != '.').collect();
    let significant = digits.trim_start_matches('0');
    if significant.is_empty() {
        return Some(0);
    }
    if token.starts_with('-') {
        return None;
    }
    let integer_digits = significant.trim_end_matches('0');
    let zeros = significant.len() - integer_digits.len();
    let scale = exponent
        .parse::<i64>()
        .ok()?
        .checked_sub(fraction as i64)?
        .checked_add(zeros as i64)?;
    if scale < 0 || (integer_digits.len() as i64).checked_add(scale)? > 10 {
        return None;
    }
    let value = integer_digits.parse::<u64>().ok()? * 10_u64.pow(scale as u32);
    (value <= 2_147_483_647).then_some(value)
}
shape_validator!(
    validate_corpus_shape,
    "../../../../spec/workbench/draft.22/schemas/mck-corpus.schema.json"
);
shape_validator!(
    validate_observation_shape,
    "../../../../spec/workbench/draft.22/schemas/mck-observation.schema.json"
);
shape_validator!(
    validate_report_shape,
    "../../../../spec/workbench/draft.22/schemas/mck-report.schema.json"
);
shape_validator!(
    validate_projection_shape,
    "../../../../spec/workbench/draft.22/schemas/native-owner-projection.schema.json"
);
shape_validator!(
    validate_expected_shape,
    "../../../../spec/workbench/draft.22/schemas/native-owner-expectation.schema.json"
);

fn validate_file(file: &Value) -> Result<(), String> {
    let source = file["source"].as_str().expect("schema checked source");
    let bytes = if file["encoding"] == "utf8" {
        source.len()
    } else {
        let decoded = base64::engine::general_purpose::STANDARD
            .decode(source)
            .map_err(|_| "invalid native owner base64 file")?;
        if base64::engine::general_purpose::STANDARD.encode(&decoded) != source {
            return Err("noncanonical native owner base64 file".into());
        }
        decoded.len()
    };
    if bytes > 262144 {
        return Err("native owner file exceeds 262144 decoded bytes".into());
    }
    Ok(())
}

pub(super) fn validate_input(value: &Value) -> Result<(), String> {
    super::contract::encoded_size(value, 491520)?;
    let mut roots = BTreeMap::new();
    for root in value["roots"].as_array().expect("schema checked roots") {
        let mut files = BTreeSet::new();
        for file in root["files"].as_array().expect("schema checked files") {
            validate_file(file)?;
            if !files.insert(file["name"].as_str().expect("schema checked name")) {
                return Err("duplicate native owner file".into());
            }
        }
        if roots
            .insert(root["id"].as_str().expect("schema checked id"), files)
            .is_some()
        {
            return Err("duplicate native owner root".into());
        }
    }
    let pickers = value["pickers"].as_array().expect("schema checked pickers");
    let cleanups = value["cleanups"]
        .as_array()
        .expect("schema checked cleanups");
    if pickers.len() + cleanups.len() > 128 {
        return Err("native owner fixture exceeds 128 boundaries".into());
    }
    for picker in pickers {
        if let Some(root) = picker["root"].as_str()
            && !roots.contains_key(root)
        {
            return Err("undeclared native owner picker root".into());
        }
    }
    let mut boundaries = BTreeSet::new();
    let mut cleanup_sessions = BTreeSet::new();
    for cleanup in cleanups {
        if !cleanup_sessions.insert(cleanup["session"].as_str().expect("schema checked session")) {
            return Err("duplicate native owner cleanup session".into());
        }
    }
    let mut held = BTreeSet::new();
    for boundary in pickers.iter().chain(cleanups) {
        let id = boundary["id"].as_str().expect("schema checked boundary id");
        if !boundaries.insert(id) {
            return Err("duplicate native owner boundary id".into());
        }
        if boundary["held"] == true {
            held.insert(id);
        }
    }
    let mut attempts = BTreeSet::new();
    let mut delivered = BTreeSet::new();
    for action in value["actions"].as_array().expect("schema checked actions") {
        match action["op"].as_str().expect("schema checked op") {
            "call" | "shutdown" => {
                if !attempts.insert(action["id"].as_str().expect("schema checked attempt id")) {
                    return Err("duplicate native owner attempt id".into());
                }
            }
            "deliver" => {
                let id = action["id"].as_str().expect("schema checked delivery id");
                if !held.contains(id) || !delivered.insert(id) {
                    return Err("invalid native owner delivery reference".into());
                }
            }
            "replace" => {
                let root = action["root"]
                    .as_str()
                    .expect("schema checked replacement root");
                let name = action["name"]
                    .as_str()
                    .expect("schema checked replacement name");
                if !roots.get(root).is_some_and(|files| files.contains(name)) {
                    return Err("undeclared native owner replacement checkpoint".into());
                }
                validate_file(action)?;
            }
            _ => {}
        }
    }
    if value["evaluation"]["inputs"]["format"] == "json" {
        let source = value["evaluation"]["inputs"]["source"]
            .as_str()
            .expect("schema checked arguments");
        if !crate::json::strict::parse(source)?.is_array() {
            return Err("native owner arguments must be a JSON array".into());
        }
    }
    Ok(())
}

pub(super) fn projection(value: &Value) -> Result<Value, String> {
    super::contract::encoded_size(value, super::contract::MAX_VALUE_BYTES)?;
    validate_projection_shape(value)?;
    super::native_policy_client::validate_plans(value)?;
    Ok(value.clone())
}

pub(super) fn validate_expected(value: &Value) -> Result<(), String> {
    super::contract::encoded_size(value, super::contract::MAX_VALUE_BYTES)?;
    validate_expected_shape(value)?;
    super::native_policy_client::validate_plans(value)
}

pub(super) fn matches(expected: &Value, actual: &Value) -> Result<bool, String> {
    validate_expected(expected)?;
    projection(actual)?;
    let mut admitted = expected.clone();
    for (index, result) in admitted["results"]
        .as_array_mut()
        .expect("checked results")
        .iter_mut()
        .enumerate()
    {
        if let Some(allowed) = result["reply"]["effect"].as_array() {
            let effect = &actual["results"][index]["reply"]["effect"];
            if !allowed.contains(effect) {
                return Ok(false);
            }
            result["reply"]["effect"] = effect.clone();
        }
    }
    Ok(admitted == *actual)
}

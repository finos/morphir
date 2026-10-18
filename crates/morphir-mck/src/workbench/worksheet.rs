//! Independent worksheet evidence checks. Source programs and supplied raw
//! documents are adapter inputs, never evaluated or decoded by this runner.
use super::contract::{OfflineOnly, Operation, encoded_size};
use serde_json::{Value, json};
use std::sync::OnceLock;

pub(super) const MAX_INPUT_BYTES: usize = 8 * 1024 * 1024;
const MAX_DOCUMENT_BYTES: usize = 2 * 1024 * 1024;

pub(super) fn validate_corpus_shape(value: &Value) -> Result<(), String> {
    check("mck-corpus", value)
}
pub(super) fn validate_report_shape(value: &Value) -> Result<(), String> {
    check("mck-report", value)
}
pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    check("mck-observation", value)
}
pub(super) fn validate_input(value: &Value, operation: Operation) -> Result<(), String> {
    encoded_size(value, MAX_INPUT_BYTES)?;
    check("mck-input", value)?;
    let validating = value.get("report").is_some();
    if validating != (operation == Operation::WorksheetValidate)
        || !matches!(
            operation,
            Operation::WorksheetEvaluate | Operation::WorksheetValidate
        )
    {
        return Err("worksheet input belongs to another operation".into());
    }
    Ok(())
}

enum RangeRole {
    Form,
    ReadPoint,
}

struct Source {
    units: Vec<u16>,
}
impl Source {
    fn read(value: &Value) -> Result<Self, String> {
        let id = value["id"].as_str().expect("schema source id");
        if id.encode_utf16().count() > 128 || id.chars().any(|c| c.is_control()) {
            return Err("worksheet source identity exceeds its contract".into());
        }
        let text = value["text"].as_str().expect("schema source text");
        let units = text.encode_utf16().collect::<Vec<_>>();
        if units.len() > 262144 || text.len() > 1024 * 1024 {
            return Err("worksheet source text exceeds its contract".into());
        }
        Ok(Self { units })
    }
    fn range(&self, value: &Value, role: RangeRole) -> Result<std::ops::Range<usize>, String> {
        let start = value["start"]
            .as_u64()
            .ok_or("worksheet range requires integral offsets")? as usize;
        let end = value["end"]
            .as_u64()
            .ok_or("worksheet range requires integral offsets")? as usize;
        if start > end
            || (matches!(role, RangeRole::Form) && start == end)
            || end > self.units.len()
        {
            return Err("worksheet range outside captured source".into());
        }
        for offset in [start, end] {
            if offset > 0
                && offset < self.units.len()
                && (0xd800..=0xdbff).contains(&self.units[offset - 1])
                && (0xdc00..=0xdfff).contains(&self.units[offset])
            {
                return Err("worksheet range splits a surrogate pair".into());
            }
        }
        Ok(start..end)
    }
}

fn terminal(value: &Value, budget: &mut usize) -> Result<Value, String> {
    if value["status"] == "failed"
        && !matches!(
            value["failure"]["code"].as_str(),
            Some("worksheet.worker_failed" | "worksheet.timeout")
        )
        && value["failure"]["stage"] != "evaluate"
    {
        return Err("worksheet failure requires evaluate stage".into());
    }
    let wrapped = super::outcomes::projection_semantics(
        &json!({"contractVersion":"0.1.0-draft.5","calls":[{"id":"worksheet","outcome":value}],"cleanup":null,"extensions":null}),
        |value| super::contract::projection_semantics(value, budget),
    )?;
    Ok(wrapped["calls"][0]["outcome"].clone())
}
fn portable(value: &Value, depth: usize) -> Result<(), String> {
    if depth > 64 {
        return Err("worksheet value exceeds depth".into());
    }
    match value["type"]
        .as_str()
        .ok_or("worksheet value requires a type")?
    {
        "int" | "bool" | "unit" => {}
        "float64" => {
            let bits = value["bits"]
                .as_str()
                .expect("typed float bits")
                .parse::<u64>()
                .map_err(|e| e.to_string())?;
            if !f64::from_bits(bits).is_finite() {
                return Err("worksheet Float64 must be finite".into());
            }
        }
        "text" | "character" => {}
        "list" | "tuple" => {
            for child in value["items"].as_array().expect("typed items") {
                portable(child, depth + 1)?;
            }
        }
        "record" => {
            for field in value["fields"].as_array().expect("typed fields") {
                portable(&field["value"], depth + 1)?;
            }
        }
        _ => return Err("value is outside this exact worksheet projection".into()),
    }
    Ok(())
}
fn diagnostic(value: &Value, stage: &str, range: Option<&Value>) -> bool {
    value["stage"] == stage
        && match range {
            Some(range) => &value["range"] == range,
            None => value["range"].is_null(),
        }
}

pub(super) fn projection(value: &Value, operation: Operation) -> Result<Value, String> {
    if !matches!(
        operation,
        Operation::WorksheetEvaluate | Operation::WorksheetValidate
    ) {
        return Err("not a worksheet operation".into());
    }
    encoded_size(value, MAX_DOCUMENT_BYTES)?;
    check("mck-projection", value)?;
    let source = Source::read(&value["source"])?;
    let mut result = value.clone();
    let rows = result["observations"]
        .as_array_mut()
        .expect("schema observations");
    let mut end = 0;
    let mut budget = 100000;
    let mut projection_failure = None;
    let mut fatal = None;
    for (index, row) in rows.iter_mut().enumerate() {
        if row["id"] != format!("form-{index}") {
            return Err("worksheet form identity/order differs".into());
        }
        let range = source.range(&row["range"], RangeRole::Form)?;
        if range.start < end {
            return Err("worksheet ranges overlap or reorder".into());
        }
        let slice = String::from_utf16(&source.units[range.clone()]).map_err(|e| e.to_string())?;
        if row["expression"] != slice {
            return Err("worksheet expression differs from exact source slice".into());
        }
        end = range.end;
        if row["preview"]
            .as_str()
            .expect("schema preview")
            .encode_utf16()
            .count()
            > 4000
        {
            return Err("worksheet preview exceeds UTF-16 budget".into());
        }
        row["outcome"] = terminal(&row["outcome"], &mut budget)?;
        match row["outcome"]["status"].as_str().expect("terminal status") {
            "returned" => portable(&row["outcome"]["value"], 0)?,
            "failed" => {
                if row["outcome"]["failure"]["code"] == "worksheet.value_unsupported" {
                    if row["outcome"]["failure"]["message"]
                        != "This Scheme value has no portable worksheet representation."
                    {
                        return Err("worksheet projection failure message differs".into());
                    }
                    if projection_failure.is_none() {
                        projection_failure = Some(row["range"].clone());
                    }
                } else {
                    if fatal.is_some() {
                        return Err("worksheet has multiple fatal rows".into());
                    }
                    fatal = Some((index, row["range"].clone(), row["outcome"].clone()));
                }
            }
            "cancelled" => {
                return Err("worksheet cancellation has no unobserved partial rows".into());
            }
            "model-error" => {}
            _ => unreachable!("checked terminal"),
        }
    }
    let count = rows.len();
    let completion = terminal(&result["completion"], &mut 100000)?;
    result["completion"] = completion.clone();
    let diag = &result["diagnostic"];
    if !diag.is_null() && !diag["range"].is_null() {
        source.range(
            &diag["range"],
            if diag["stage"] == "read" {
                RangeRole::ReadPoint
            } else {
                RangeRole::Form
            },
        )?;
    }
    match completion["status"].as_str().expect("terminal completion") {
        "returned" => {
            if completion["value"] != json!({"type":"unit"}) || fatal.is_some() {
                return Err("worksheet completion is inconsistent".into());
            }
            match projection_failure {
                Some(range) if diagnostic(diag, "project", Some(&range)) => {}
                None if diag.is_null() => {}
                _ => {
                    return Err(
                        "worksheet projection diagnostic differs from first unavailable row".into(),
                    );
                }
            }
        }
        "cancelled" => {
            if count != 0 || !diagnostic(diag, "transport", None) {
                return Err("worksheet cancellation context differs".into());
            }
        }
        "failed" => match completion["failure"]["code"]
            .as_str()
            .expect("failure code")
        {
            "worksheet.read_failed" => {
                if count != 0
                    || diag["stage"] != "read"
                    || (!diag["range"].is_null() && diag["range"]["start"] != diag["range"]["end"])
                {
                    return Err("worksheet read failure requires zero-width source diagnostic and no execution".into());
                }
            }
            "worksheet.worker_failed" | "worksheet.timeout" => {
                if count != 0 || !diagnostic(diag, "transport", None) {
                    return Err("worksheet transport failure must not fabricate rows".into());
                }
            }
            "worksheet.output_limit" => {
                if fatal.is_some()
                    || diag["stage"] != "project"
                    || diag["range"].is_null()
                    || source.range(&diag["range"], RangeRole::Form)?.start < end
                {
                    return Err(
                        "worksheet output limit must identify an unretained suffix form".into(),
                    );
                }
            }
            "worksheet.evaluation_failed" | "worksheet.runtime_limit" => match fatal {
                Some((index, range, outcome))
                    if index + 1 == count
                        && outcome == completion
                        && diagnostic(diag, "evaluate", Some(&range)) => {}
                _ => {
                    return Err(
                        "worksheet fatal completion differs from last observed failure".into(),
                    );
                }
            },
            _ => return Err("unknown worksheet fatal completion".into()),
        },
        _ => return Err("worksheet completion must be unit, failure or cancellation".into()),
    }
    Ok(result)
}

fn check(name: &str, value: &Value) -> Result<(), String> {
    static VALIDATORS: OnceLock<std::collections::BTreeMap<&str, jsonschema::Validator>> =
        OnceLock::new();
    let validators = VALIDATORS.get_or_init(|| {
        let schemas = [
            include_str!("../../../../spec/workbench/schemas/value.schema.json"),
            include_str!(
                "../../../../spec/workbench/draft.5/schemas/terminal-outcomes.schema.json"
            ),
            include_str!(
                "../../../../spec/workbench/worksheet/0.1.0-draft.1/schemas/request.schema.json"
            ),
            include_str!(
                "../../../../spec/workbench/worksheet/0.1.0-draft.1/schemas/report.schema.json"
            ),
            include_str!("../../../../spec/workbench/draft.27/schemas/mck-input.schema.json"),
            include_str!("../../../../spec/workbench/draft.27/schemas/mck-projection.schema.json"),
            include_str!("../../../../spec/workbench/draft.27/schemas/mck-observation.schema.json"),
            include_str!(
                "../../../../spec/workbench/draft.27/schemas/mck-capabilities.schema.json"
            ),
            include_str!("../../../../spec/workbench/draft.27/schemas/mck-corpus.schema.json"),
            include_str!("../../../../spec/workbench/draft.27/schemas/mck-report.schema.json"),
        ]
        .map(|s| serde_json::from_str::<Value>(s).expect("worksheet schema JSON"));
        [
            "mck-input",
            "mck-projection",
            "mck-observation",
            "mck-capabilities",
            "mck-corpus",
            "mck-report",
        ]
        .into_iter()
        .map(|name| {
            let id = format!(
                "https://morphir.finos.org/spec/workbench/0.1.0-draft.27/{name}.schema.json"
            );
            let schema = schemas
                .iter()
                .find(|s| s["$id"] == id)
                .expect("worksheet schema");
            let mut options = jsonschema::options();
            options.with_retriever(OfflineOnly);
            for resource in &schemas {
                options.with_resource(
                    resource["$id"].as_str().expect("schema id"),
                    jsonschema::Resource::from_contents(resource.clone()).expect("schema resource"),
                );
            }
            (name, options.build(schema).expect("worksheet validator"))
        })
        .collect()
    });
    validators[name].validate(value).map_err(|e| {
        format!(
            "invalid worksheet infrastructure at {}: {e}",
            e.instance_path
        )
    })
}

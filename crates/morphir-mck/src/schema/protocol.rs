use super::SchemaError;
use super::catalog::{Catalog, Schema};
use serde_json::Value;

struct Pending<'a> {
    id: &'a Value,
    op: &'a str,
    answered: bool,
}

fn integer_id(value: &Value) -> Option<u64> {
    value.as_u64().or_else(|| {
        let number = value.as_f64()?;
        // Match the live protocol's bounded conversion for integral decimal
        // spellings. Large decimal IDs may already have rounded during parsing;
        // accepting them could pair two different IDs. Integer literals above
        // this bound remain lossless through as_u64().
        ((1.0..9.0e15).contains(&number) && number.fract() == 0.0).then_some(number as u64)
    })
}

fn unanswered(pending: &Option<Pending<'_>>, errors: &mut Vec<String>) {
    if let Some(pending) = pending
        && !pending.answered
    {
        errors.push(format!(
            "request id {} ({}) has no response",
            pending.id, pending.op
        ));
    }
}

pub(super) fn check(
    catalog: &mut Catalog,
    example: &Value,
    errors: &mut Vec<String>,
) -> Result<usize, SchemaError> {
    let entries = example
        .as_array()
        .ok_or_else(|| SchemaError("protocol.example.json must be an array".into()))?;
    let mut pending = None;
    let mut checked = 0;
    for (index, entry) in entries.iter().enumerate() {
        let message = &entry["message"];
        if !message.is_object() {
            errors.push(format!("protocol entry {index}: message is not an object"));
            continue;
        }
        let definition = match entry["direction"].as_str() {
            Some("request") => {
                unanswered(&pending, errors);
                pending = match message["op"].as_str() {
                    Some("exit") | None => None,
                    Some(op) => Some(Pending {
                        id: &message["id"],
                        op,
                        answered: false,
                    }),
                };
                "Request"
            }
            Some("response") => {
                let Some(request) = &mut pending else {
                    errors.push(format!(
                        "protocol entry {index}: response without a preceding request"
                    ));
                    continue;
                };
                // JSON Schema integer accepts integral JSON numbers such as 1.0 too.
                let id = integer_id(&message["id"]);
                if id.is_none() || id != integer_id(request.id) {
                    errors.push(format!("protocol entry {index}: response id {} does not answer the pending request id {}", message["id"], request.id));
                    continue;
                }
                let definition = match request.op {
                    "capabilities" => "Capabilities",
                    "decode" | "readTree" => "DecodeResponse",
                    "writeTree" => "WriteTreeResponse",
                    op => {
                        errors.push(format!("protocol entry {index}: answers unknown op {op}"));
                        continue;
                    }
                };
                request.answered = true;
                definition
            }
            _ => {
                errors.push(format!("protocol entry {index}: unknown direction"));
                continue;
            }
        };
        checked += 1;
        for (definition, label) in [(definition, definition), ("", "root schema")] {
            if let Err(error) = catalog
                .validator(Schema::Protocol, definition)?
                .validate(message)
            {
                errors.push(format!(
                    "protocol entry {index} ({label}): {error} at {}",
                    error.instance_path
                ));
            }
        }
    }
    unanswered(&pending, errors);
    Ok(checked)
}

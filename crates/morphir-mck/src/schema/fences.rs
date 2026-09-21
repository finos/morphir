use super::catalog::{Catalog, node_target};
use super::{FenceOutcome, FenceResult, SchemaError};
use crate::kit::Kit;
use crate::kit::syntax::case::Status;
use crate::kit::syntax::info_string::{Language, Role};
use serde_json::Value;

pub(super) fn check(catalog: &mut Catalog, kit: &Kit) -> Result<Vec<FenceResult>, SchemaError> {
    let mut results = Vec::new();
    for case in &kit.cases {
        if case.status == Status::Pending || case.version.is_some_and(|v| v != 4) {
            continue;
        }
        // The historical schema checker numbers only canonical/accepted inline JSON fences.
        for (index, fence) in case
            .fences
            .iter()
            .filter(|f| {
                f.info.language == Language::Json
                    && matches!(f.info.role, Role::Canonical | Role::Accepted)
            })
            .enumerate()
        {
            let expected_acceptance = fence.info.key("warning").is_none()
                || matches!(
                    case.id.as_str(),
                    "definitions-0006" | "definitions-0010" | "definitions-0018"
                );
            let node = case.node.as_deref().unwrap_or("unset");
            let outcome = match node_target(node) {
                None => {
                    FenceOutcome::Failed(format!("no schema target for node={node}; coverage loss"))
                }
                Some((schema, definition)) => {
                    let validator = catalog.validator(schema, definition)?;
                    match serde_json::from_str::<Value>(&fence.body) {
                        Err(error) => FenceOutcome::Failed(format!("invalid JSON: {error}")),
                        Ok(value) => match (validator.validate(&value), expected_acceptance) {
                            (Ok(()), true) => FenceOutcome::Accepted,
                            (Err(_), false) => FenceOutcome::RejectedAsExpected,
                            (Ok(()), false) => FenceOutcome::Failed("the schema accepted a window spelling it must reject (decision 0006)".into()),
                            (Err(error), true) => FenceOutcome::Failed(format!("{error} at {}", error.instance_path)),
                        },
                    }
                }
            };
            results.push(FenceResult {
                case_id: case.id.to_string(),
                index: index + 1,
                file: case.file.clone(),
                line: fence.line,
                outcome,
            });
        }
    }
    Ok(results)
}

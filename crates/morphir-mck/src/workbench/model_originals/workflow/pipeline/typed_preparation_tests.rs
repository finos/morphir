//! Prospective child of pipeline. This is the existing outer String boundary.
use super::*;
use std::cell::Cell;

const CORPUS: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
));
const CHECKER: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
));
const FORGED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/source-forged-cases.json"
));
const REORDERED: &str = include_str!(concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/src/workbench/model_originals/workflow/pipeline_controls/reordered-cases.json"
));
fn source(raw: &str) -> Source {
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), raw).unwrap();
    Source::new(CorpusSource::load(root.path()).unwrap()).unwrap()
}
fn policy(raw: &str) -> Policy {
    Policy::from_document(&Document::parse_exact(raw.as_bytes()).unwrap()).unwrap()
}

#[test]
fn legacy_prepared_01_exact_existing_phase_messages_and_callback_passthrough() {
    for (raw, expected) in [
        (FORGED, "source correspondence refused"),
        (
            REORDERED,
            "inventory differs from complete ordered reviewed subset",
        ),
    ] {
        let calls = Cell::new(0);
        let result = prepared(
            &source(raw),
            &policy(CHECKER),
            ReviewedSources::selected(),
            |_, _| {
                calls.set(calls.get() + 1);
                Ok(())
            },
        );
        assert_eq!(result.unwrap_err(), expected);
        assert_eq!(calls.get(), 0);
    }
    for (section, field, amount, expected) in [
        ("closure", "definitions", 0, "source closure refused"),
        ("expansion", "frameBytes", 0, "source expansion refused"),
        ("decode", "byteVisits", 1, "source corpus decode refused"),
    ] {
        let mut value: serde_json::Value = serde_json::from_str(CHECKER).unwrap();
        value[section][field] = amount.into();
        let result = prepared(
            &source(CORPUS),
            &policy(&value.to_string()),
            ReviewedSources::selected(),
            |_, _| Ok(()),
        );
        assert_eq!(result.unwrap_err(), expected);
    }
    // A callback String is an existing outer API operand. Move it unchanged.
    let original = String::from("existing outer callback failure");
    let pointer = original.as_ptr();
    let result = prepared(
        &source(CORPUS),
        &policy(CHECKER),
        ReviewedSources::selected(),
        |_, _| Err::<(), _>(original),
    );
    let returned = result.unwrap_err();
    assert_eq!(returned, "existing outer callback failure");
    assert_eq!(returned.as_ptr(), pointer);
}

#[test]
fn legacy_prepared_02_compilation_mapper_keeps_all_existing_branches_exact() {
    use crate::workbench::model_originals::workflow::{
        compile::CompileError,
        expansion::{ExpansionError, ExpansionResource},
        identity_input::IdentityInputError,
        work::{ClosureError, Resource},
    };
    for (cause, expected) in [
        (
            CompilationError::Source(SourceError::Inventory),
            "inventory differs from complete ordered reviewed subset",
        ),
        (
            CompilationError::Source(SourceError::MissingManifestCase),
            "source correspondence refused",
        ),
        (
            CompilationError::Closure(CompileError::Owner(ClosureError::Resource(
                Resource::Definitions,
            ))),
            "source closure refused",
        ),
        (
            CompilationError::Expansion(ExpansionError::Resource(ExpansionResource::FrameBytes)),
            "source expansion refused",
        ),
        (
            CompilationError::IdentityInput(IdentityInputError::Work(ClosureError::Semantic)),
            "source identity input refused",
        ),
    ] {
        assert_eq!(compilation_message(&cause), expected);
    }
}

//! Prospective test-only browser child, SIBLING of inputs.
//! Copy exactly one privacy-cases/*.rs to privacy-selected.rs per privacy-plan.json.
use super::inputs::{BrowserClientInput, BrowserInputAlias, BrowserInputFault};
use super::{BrowserPreparationFault, prepared_browser_originals};
use crate::workbench::model_originals::workflow::pipeline::Source;
use crate::workbench::{RunConfiguration, corpus::CorpusSource};
#[path = "privacy-selected.rs"]
mod selected;

#[test]
fn actual_borrowed_input_privacy_harness() {
    let corpus = include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/workbench/model_originals/workflow/pipeline_controls/cases.json"
    ));
    let checker: serde_json::Value = serde_json::from_str(include_str!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/src/workbench/model_originals/workflow/pipeline_controls/explicit-test-policy.json"
    )))
    .unwrap();
    let configuration = RunConfiguration::from_json(
        &serde_json::json!({
            "kind":"model-originals-browser","browser":"chromium","checker":checker,
            "receiving":{"retainedBytes":0,"stdoutPrefixBytes":0,"stderrPrefixBytes":0,
                "snapshotReadBytes":0,"byteVisits":0,"records":0}
        })
        .to_string(),
    )
    .unwrap();
    let root = tempfile::tempdir().unwrap();
    std::fs::write(root.path().join("cases.json"), corpus).unwrap();
    let source = Source::new(CorpusSource::load(root.path()).unwrap()).unwrap();
    let result: Result<(), BrowserPreparationFault<BrowserInputFault>> =
        prepared_browser_originals(&source, &configuration, |inventory, loans| {
            inventory.visit_clients(loans, |client, loans| {
                for alias in client.input_aliases(loans)? {
                    selected::check_alias(alias);
                }
                selected::check(client);
                Ok(())
            })
        });
    result.unwrap();
}

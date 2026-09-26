//! The Gherkin kit step library runs canonical, accepted and rejected inputs.

use std::borrow::Cow;
use std::collections::BTreeMap;

use morphir_bdd::{Console, Suite};
use morphir_mck::ir::run::Testee;
use morphir_mck::kit::KitSource;
use morphir_mck::kit::load::load_feature_kit;
use morphir_mck::report::Outcome;
use morphir_mck::steps::KitRun;
use morphir_mck::transport::protocol::Request;
use serde_json::{Map, Value, json};

const FEATURE: &str = r#"@node:Value
Feature: Values
  Scenario: values-0001 A variable
    Then its canonical YAML spelling is:
      """yaml
      Variable: x
      """
    And its canonical JSON spelling is { "Variable": "x" }
    And a reader of JSON accepts "x"

  Scenario: values-0002 An unknown node is rejected
    Then a reader of JSON rejects { "Bogus": 1 } with unknown_node
"#;

struct Fake;

impl Testee for Fake {
    fn exchange(&mut self, request: &Request) -> Result<Map<String, Value>, String> {
        let body = match request {
            Request::Capabilities => json!({
                "contractVersion": 1, "binding": "fake", "language": "rust",
                "formatVersions": "[4.0.0,4.1.0)", "versions": [4], "profiles": ["json", "yaml"],
                "layouts": ["single"], "paths": ["current", "pinned"], "nodes": ["Value"]
            }),
            Request::Decode { .. } => json!({
                "ok": true, "kind": "Variable",
                "canonical": { "yaml": "Variable: x", "json": "{ \"Variable\": \"x\" }" },
                "warnings": []
            }),
            other => return Err(format!("the fake does not answer {other:?}")),
        };
        Ok(body.as_object().expect("an object").clone())
    }
}

#[tokio::main]
async fn main() {
    morphir_mck::steps::link();
    let source = KitSource::map(
        "feature kit",
        BTreeMap::from([(
            "spec/ir/mck/values.feature".to_owned(),
            Cow::Owned(FEATURE.as_bytes().to_vec()),
        )]),
    );
    let kit = load_feature_kit(source).expect("load the feature kit");
    assert!(kit.kit.errors.is_empty(), "{:?}", kit.kit.errors);
    assert_eq!(kit.kit.cases.len(), 2);

    let features = tempfile::tempdir().expect("create a features directory");
    std::fs::write(features.path().join("values.feature"), FEATURE).unwrap();
    let out_dir = tempfile::tempdir().expect("create an output directory");
    let kit_run = KitRun::new(kit, Box::new(Fake), Box::new(|| 0.0));
    let result = Suite::new("mck-kit-steps")
        .features(features.path())
        .clear_tags()
        .max_concurrent_scenarios(1)
        .with_component(kit_run.clone())
        .console(Console::Off)
        .out_dir(out_dir.path())
        .run()
        .await;

    assert_eq!(result.errors, 0, "{result:?}");
    assert_eq!(result.failed, 1, "{result:?}");
    assert!(result.passed >= 1, "{result:?}");
    let records = kit_run.report_records();
    assert_eq!(records.len(), 8); // Four fences, each checked in both path modes.
    assert_eq!(
        records.iter().filter(|r| r.result == Outcome::Pass).count(),
        6
    );
    assert_eq!(
        records.iter().filter(|r| r.result == Outcome::Fail).count(),
        2
    );
    assert_eq!(records[0].case_id, "values-0001");
    assert_eq!(records[7].case_id, "values-0002");
    println!("kit_steps: ok");
}

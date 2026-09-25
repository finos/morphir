//! The kit step library runs a `.feature` kit to the same records as the legacy engine.
//!
//! The test builds a two-case kit from Markdown text and converts it to its `.feature` twin, so
//! the twins match by construction. `values-0001` has canonical YAML and JSON spellings and an
//! accepted JSON input; `values-0002` has a rejected JSON input. A fake adapter decodes every
//! input, so case 1 passes and case 2 fails. A `Suite` runs the `.feature` twin through the kit
//! steps with one shared `KitRun`. Exactly one step must fail, and the `KitRun`'s report records
//! must equal what `run_kit` writes for the Markdown twin with the same fake, `duration_ms`
//! aside.

use std::borrow::Cow;
use std::collections::BTreeMap;

use morphir_bdd::{Console, Suite};
use morphir_mck::ir::run::{RunOptions, Testee, run_kit};
use morphir_mck::kit::KitSource;
use morphir_mck::kit::gherkin::convert::{convert, feature_description, feature_title};
use morphir_mck::kit::load::{load_feature_kit, load_kit};
use morphir_mck::kit::syntax::case::parse_kit_file;
use morphir_mck::report::{Millis, Record};
use morphir_mck::steps::KitRun;
use morphir_mck::transport::protocol::Request;
use serde_json::{Map, Value, json};

const MARKDOWN_PATH: &str = "spec/ir/mck/values.md";
const FEATURE_PATH: &str = "spec/ir/mck/values.feature";

const MARKDOWN: &str = r#"# Values

Two cases for the kit step library's test.

## values-0001: A variable {node=Value}

```yaml canonical
Variable: x
```

```json canonical
{ "Variable": "x" }
```

```json accepted
"x"
```

## values-0002: An unknown node is rejected {node=Value}

```json rejected diagnostic=unknown_node
{ "Bogus": 1 }
```
"#;

/// A fake adapter: it declares both path modes and the `Value` node, and decodes every input to
/// the variable `x`. So every fence of `values-0001` passes, and the rejected fence of
/// `values-0002` fails.
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

fn files(path: &str, text: &str) -> BTreeMap<String, Cow<'static, [u8]>> {
    BTreeMap::from([(path.to_owned(), Cow::Owned(text.as_bytes().to_vec()))])
}

/// The records with their durations zeroed, so two runs compare field by field on everything
/// else.
fn without_durations(records: Vec<Record>) -> Vec<Record> {
    records
        .into_iter()
        .map(|record| Record {
            duration_ms: Millis(0.0),
            ..record
        })
        .collect()
}

#[tokio::main]
async fn main() {
    morphir_mck::steps::link();

    // The Markdown twin, and the legacy engine's records for it.
    let markdown = load_kit(KitSource::map(
        "markdown kit",
        files(MARKDOWN_PATH, MARKDOWN),
    ))
    .expect("load the Markdown kit");
    assert!(markdown.errors.is_empty(), "{:?}", markdown.errors);
    assert_eq!(markdown.cases.len(), 2);
    let clock = || 0.0;
    let options = RunOptions {
        filter: None,
        driver_version: "test".into(),
        kit_version: "test".into(),
        started_at: "1970-01-01T00:00:00.000Z".into(),
        clock: &clock,
    };
    let legacy = run_kit(&markdown, &mut Fake, &options).report.records;

    // The `.feature` twin, converted from the same Markdown.
    let parsed = parse_kit_file(MARKDOWN_PATH, MARKDOWN);
    assert!(parsed.errors.is_empty(), "{:?}", parsed.errors);
    let feature = convert(
        &feature_title("values", MARKDOWN),
        &feature_description(MARKDOWN),
        &parsed.cases,
    );
    let kit = load_feature_kit(KitSource::map("feature kit", files(FEATURE_PATH, &feature)))
        .expect("load the .feature kit");
    assert!(kit.kit.errors.is_empty(), "{:?}", kit.kit.errors);
    assert_eq!(kit.kit.cases.len(), 2);

    let features = tempfile::tempdir().expect("create a features directory");
    std::fs::write(features.path().join("values.feature"), &feature)
        .expect("write the .feature twin");
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

    assert_eq!(result.errors, 0, "{result:?}\n{feature}");
    assert_eq!(result.failed, 1, "{result:?}\n{feature}");
    assert!(result.passed >= 1, "{result:?}\n{feature}");

    let gherkin = kit_run.report_records();
    assert!(!legacy.is_empty());
    assert_eq!(without_durations(gherkin), without_durations(legacy));
    println!("kit_steps: ok");
}

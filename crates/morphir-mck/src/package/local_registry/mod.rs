//! Draft.3 definition inspection and admission, independent of package operations.
//! An inspection is not an execution result. Only a fully bound corpus can produce
//! an admitted kit; its private fields retain the validated, owned inputs.
mod corpus;
mod result;
mod scenario;
mod semantics;
mod validation;

use crate::kit::hash::{ContentDigest, content_hash};
use corpus::Corpus;
pub use corpus::{CorpusSource, FileMapSource, RepositorySource};
use semantics::Validated;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;
use validation::{list, text};

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DefinitionSummary {
    pub kind: &'static str,
    pub case_count: usize,
    pub bound_asset_count: usize,
    pub pending_asset_count: usize,
    pub errors: Vec<String>,
}
impl DefinitionSummary {
    pub fn error(error: String) -> Self {
        Self {
            kind: "definition-summary",
            case_count: 0,
            bound_asset_count: 0,
            pending_asset_count: 0,
            errors: vec![error],
        }
    }
}
pub fn inspect_local_registry(source: &dyn CorpusSource) -> DefinitionSummary {
    let inspect = || -> Result<DefinitionSummary, String> {
        let mut loaded = Corpus::load(source)?;
        semantics::validate(&mut loaded)?;
        let assets = list(&loaded.index["assets"])?;
        Ok(DefinitionSummary {
            kind: "definition-summary",
            case_count: loaded.cases.len(),
            bound_asset_count: assets.iter().filter(|a| a["kind"] == "bound").count(),
            pending_asset_count: assets.iter().filter(|a| a["kind"] == "pending").count(),
            errors: vec![],
        })
    };
    inspect().unwrap_or_else(DefinitionSummary::error)
}
#[derive(Debug)]
pub struct AdmittedCase {
    definition: Value,
    assets: BTreeMap<String, Vec<u8>>,
    expectations: BTreeMap<String, Value>,
    observations: Option<Value>,
}
impl AdmittedCase {
    pub fn id(&self) -> &str {
        self.definition["id"].as_str().expect("admitted ID")
    }
    pub fn definition(&self) -> &Value {
        &self.definition
    }
    pub fn asset_bytes(&self, id: &str) -> Result<&[u8], String> {
        self.assets
            .get(id)
            .map(Vec::as_slice)
            .ok_or_else(|| format!("asset outside admitted closure {id}"))
    }
    pub fn expectations(&self) -> &BTreeMap<String, Value> {
        &self.expectations
    }
    pub fn observations(&self) -> Option<&Value> {
        self.observations.as_ref()
    }
    fn construct(definition: &Value, validated: &Validated) -> Result<Self, String> {
        fn visit(
            value: &Value,
            validated: &Validated,
            assets: &mut BTreeMap<String, Vec<u8>>,
        ) -> Result<(), String> {
            match value {
                Value::Array(items) => {
                    for item in items {
                        visit(item, validated, assets)?;
                    }
                }
                Value::Object(object) => {
                    if let Some(id) = object.get("asset") {
                        let id = text(id)?;
                        if !assets.contains_key(id) {
                            let bytes = validated
                                .bytes
                                .get(id)
                                .ok_or_else(|| format!("pending asset {id}"))?;
                            assets.insert(id.into(), bytes.clone());
                            if let Some(doc) = validated.documents.get(id) {
                                visit(doc, validated, assets)?;
                            }
                        }
                    }
                    for (key, child) in object {
                        if key != "assertions" {
                            visit(child, validated, assets)?;
                        }
                    }
                }
                _ => {}
            }
            Ok(())
        }
        let mut assets = BTreeMap::new();
        visit(definition, validated, &mut assets)?;
        let operations = if definition["kind"] == "parse" {
            std::slice::from_ref(definition)
        } else {
            list(&definition["operations"])?
        };
        let mut expectations = BTreeMap::new();
        for operation in operations {
            let expected = &operation["expected"];
            let result = match text(&expected["kind"])? {
                "terminated" => {
                    serde_json::json!({"kind":"terminated","checkpoint":expected["checkpoint"]})
                }
                "inline" => expected["result"].clone(),
                _ => validated
                    .documents
                    .get(text(&expected["asset"])?)
                    .ok_or("pending expected result")?
                    .clone(),
            };
            expectations.insert(text(&operation["id"])?.into(), result);
        }
        let observations = if definition["kind"] == "scenario" {
            Some(
                validated
                    .documents
                    .get(text(&definition["expectedObservations"]["asset"])?)
                    .ok_or("pending observations")?
                    .clone(),
            )
        } else {
            None
        };
        Ok(Self {
            definition: definition.clone(),
            assets,
            expectations,
            observations,
        })
    }
}
#[derive(Debug)]
pub struct AdmittedKit {
    content_hash: ContentDigest,
    cases: Vec<AdmittedCase>,
}
impl AdmittedKit {
    pub fn content_hash(&self) -> &ContentDigest {
        &self.content_hash
    }
    pub fn cases(&self) -> &[AdmittedCase] {
        &self.cases
    }
}
pub fn admit_local_registry(source: &dyn CorpusSource) -> Result<AdmittedKit, Vec<String>> {
    let admit = || -> Result<AdmittedKit, String> {
        let mut loaded = Corpus::load(source)?;
        let validated = semantics::validate(&mut loaded)?;
        for asset in list(&loaded.index["assets"])? {
            if asset["kind"] == "pending" {
                return Err(format!("pending asset {}", text(&asset["id"])?));
            }
        }
        let cases = loaded
            .cases
            .iter()
            .map(|entry| AdmittedCase::construct(entry, &validated))
            .collect::<Result<_, _>>()?;
        Ok(AdmittedKit {
            content_hash: content_hash(
                loaded
                    .consumed
                    .iter()
                    .map(|(path, bytes)| (path.as_str(), bytes.as_slice())),
            ),
            cases,
        })
    };
    admit().map_err(|error| vec![error])
}
#[cfg(test)]
fn admit_exact_case_for_testing(
    source: &impl CorpusSource,
    id: &str,
) -> Result<AdmittedCase, String> {
    let mut loaded = Corpus::load(source)?;
    let validated = semantics::validate(&mut loaded)?;
    let definition = loaded
        .cases
        .iter()
        .find(|entry| entry["id"] == id)
        .ok_or_else(|| format!("unknown case {id}"))?;
    AdmittedCase::construct(definition, &validated)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_case_probe_is_test_only_and_has_no_kit_hash() {
        let source =
            RepositorySource::new(std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../.."))
                .unwrap();
        let case =
            admit_exact_case_for_testing(&source, "local-registry.wire.valid-two-node").unwrap();
        assert_eq!(case.id(), "local-registry.wire.valid-two-node");
        assert!(!case.expectations().is_empty());
        assert!(admit_local_registry(&source).is_err());
    }
}

#[cfg(test)]
#[allow(dead_code)]
mod test_support {
    include!(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/support/local_registry/mod.rs"
    ));
}
#[cfg(test)]
mod closure_tests {
    use super::{test_support::*, *};
    use serde_json::json;
    #[test]
    fn exact_case_admits_only_its_transitive_bound_closure() {
        let mut source = files();
        bind(&mut source, "expected", "result", encode(&failure()));
        mutate(
            &mut source,
            CASE,
            |d| d["cases"][0]["expected"] = json!({"kind":"asset","asset":"expected","assertions":[{"pointer":"/ok","equals":false}]}),
        );
        assert!(admit_exact_case_for_testing(&source, "local-registry.wire.raw").is_ok());
        assert!(admit_local_registry(&source).is_err());
        let mut source = scenario_files();
        bind(
            &mut source,
            "future",
            "tree",
            encode(
                &json!({"entries":[{"kind":"file","path":"negative.json","bytes":{"kind":"asset","asset":"missing-bytes"}}]}),
            ),
        );
        mutate(&mut source, INDEX, |d| {
            d["assets"].as_array_mut().unwrap().push(json!({"id":"missing-bytes","kind":"pending","type":"bytes","purpose":"Awaiting exact bytes"}))
        });
        assert!(inspect_local_registry(&source).errors.is_empty());
        assert!(
            admit_exact_case_for_testing(&source, "local-registry.wire.scenario")
                .unwrap_err()
                .contains("pending asset")
        );
        bind(&mut source, "missing-bytes", "bytes", vec![0xff]);
        let case = admit_exact_case_for_testing(&source, "local-registry.wire.scenario").unwrap();
        assert_eq!(case.asset_bytes("missing-bytes").unwrap(), [0xff]);
    }
}

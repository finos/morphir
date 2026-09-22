use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
pub type Files = BTreeMap<String, Vec<u8>>;
pub const INDEX: &str = "spec/package/mck/local-registry-cases.json";
pub const CASE: &str = "spec/package/mck/fixtures/local-registry/cases/test.json";
pub const SCHEMA: &str = "spec/package/schemas/local-registry-case.schema.json";
pub const SCHEMA_ID: &str =
    "https://morphir.finos.org/spec/package/0.1.0-draft.3/local-registry-case.schema.json";
pub fn digest(bytes: &[u8]) -> String {
    format!(
        "sha256:{}",
        Sha256::digest(bytes)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect::<String>()
    )
}
pub fn encode(value: &Value) -> Vec<u8> {
    serde_json::to_vec(value).unwrap()
}
pub fn mutate(files: &mut Files, name: &str, change: impl FnOnce(&mut Value)) {
    let mut value = serde_json::from_slice(&files[name]).unwrap();
    change(&mut value);
    files.insert(name.into(), encode(&value));
}
pub fn failure() -> Value {
    json!({"ok":false,"diagnostic":{"category":"invalid-input","code":"invalid-input","phase":"decode","witnesses":[{"kind":"violation","subject":{"kind":"lock"},"pointer":"","rule":"malformed-json"}]}})
}
pub fn files() -> Files {
    BTreeMap::from([
        (
            INDEX.into(),
            encode(
                &json!({"formatVersion":"0.1.0-draft.3","status":"candidate-definitions","schema":"../schemas/local-registry-case.schema.json","fixtures":["fixtures/local-registry/cases/test.json"],"assets":[{"id":"future","kind":"pending","type":"bytes","purpose":"Not bound yet"}]}),
            ),
        ),
        (
            CASE.into(),
            encode(
                &json!({"formatVersion":"0.1.0-draft.3","cases":[{"kind":"parse","id":"local-registry.wire.raw","family":"wire","description":"Exact malformed bytes","required":true,"target":"lock","at":"2027-01-01T00:00:00Z","input":{"kind":"hex","value":"efbbbf7b7d"},"expected":{"kind":"inline","result":failure()}}]}),
            ),
        ),
        (
            "spec/package/mck/README.md".into(),
            b"Definition contract\n".to_vec(),
        ),
        (
            SCHEMA.into(),
            encode(
                &json!({"$schema":"https://json-schema.org/draft/2020-12/schema","$id":SCHEMA_ID,"$defs":{
                    "Index":{"type":"object","required":["fixtures","assets"]},"CaseFile":{"type":"object","required":["cases"]},
                    "Result":{"type":"object","required":["ok"],"oneOf":[{"required":["diagnostic"],"properties":{"ok":{"const":false},"diagnostic":{"type":"object","required":["category","code","phase","witnesses"]}}},{"required":["kind"],"properties":{"ok":{"const":true}}}]},
                    "Tree":{"type":"object","required":["entries"]},"Configuration":{"type":"object","required":["bindings","bootstrapRoots"]},"Observations":{"type":"object","required":["security","filesystems","registries","lockBytes","readyGraphs"]}
                }}),
            ),
        ),
    ])
}
pub fn bind(files: &mut Files, id: &str, kind: &str, bytes: Vec<u8>) -> String {
    let path = format!("fixtures/local-registry/assets/{id}.json");
    mutate(files, INDEX, |index| {
        let assets = index["assets"].as_array_mut().unwrap();
        assets.retain(|asset| asset["id"] != id);
        assets.push(json!({"id":id,"type":kind,"kind":"bound","purpose":"Fixed test bytes","path":path,"length":bytes.len().to_string(),"sha256":digest(&bytes)}));
    });
    let path = format!("spec/package/mck/{path}");
    files.insert(path.clone(), bytes);
    path
}
pub fn scenario_files() -> Files {
    let mut source = files();
    let digest = format!("sha256:{}", "0".repeat(64));
    bind(
        &mut source,
        "future",
        "tree",
        encode(&json!({"entries":[]})),
    );
    bind(
        &mut source,
        "configuration",
        "configuration",
        encode(
            &json!({"bindings":[{"alias":"finance","registryRoot":"finance","identity":digest}],"bootstrapRoots":[{"identity":digest,"version":"1","bytes":{"kind":"hex","value":"00"}}]}),
        ),
    );
    let policy = json!({"kind":"hex","value":"00"});
    let at = "2027-01-01T00:00:00Z";
    bind(
        &mut source,
        "observations",
        "observations",
        encode(&json!({
            "security":[{"actor":"client","condition":"readable","repositories":[{"registry":"finance","currentRoot":"1","floors":{"timestamp":"0","snapshot":"0","targets":"0"},"lastFreshAuthorization":{"kind":"none"}}],"grants":[],"revocations":[],"marker":"none","observedAt":at,"policy":policy}],
            "filesystems":[{"root":{"owner":"client","kind":"cache"},"entries":[]},{"root":{"owner":"client","kind":"destination"},"entries":[]},{"root":{"owner":"finance","kind":"registry"},"entries":[]}],
            "registries":[{"registry":"finance","timestamp":{"kind":"absent"},"reserved":{"targets":"0","snapshot":"0","timestamp":"0"}}],"lockBytes":[],"readyGraphs":[]
        })),
    );
    mutate(&mut source, CASE, |doc| {
        doc["cases"] = json!([{
            "kind":"scenario","id":"local-registry.wire.scenario","family":"wire","description":"Fixed scenario","required":true,
            "setup":{"registries":[{"id":"finance","tree":{"asset":"future"},"publisher":"explicitly-initialize"}],"actors":[{"id":"client","configuration":{"asset":"configuration"},"policy":policy,"security":"explicitly-initialize","cache":{"asset":"future"},"staging":"empty","destination":"empty"}]},
            "operations":[{"id":"refresh","actor":"client","at":at,"policy":policy,"limits":[],"name":"refresh-library-registry","input":{"registry":"finance"},"expected":{"kind":"inline","result":failure()}}],
            "actions":[{"kind":"start","operation":"refresh","barriers":[]},{"kind":"join","operation":"refresh"}],
            "observe":{"at":at,"policies":[{"actor":"client","policy":policy}]},"expectedObservations":{"asset":"observations","assertions":[{"pointer":"/readyGraphs","equals":[]}]}
        }])
    });
    source
}
pub fn observation(files: &mut Files, change: impl FnOnce(&mut Value)) {
    let name = "spec/package/mck/fixtures/local-registry/assets/observations.json";
    let mut value = serde_json::from_slice(&files[name]).unwrap();
    change(&mut value);
    bind(files, "observations", "observations", encode(&value));
}

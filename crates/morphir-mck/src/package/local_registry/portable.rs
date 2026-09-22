//! Required portable consumption inventory. This planning format deliberately has
//! no executable-kit or hash constructor: fixture/protocol closure remains pending.
use super::{
    CorpusSource,
    corpus::Corpus,
    semantics,
    validation::{list, text},
};
use crate::package::schemas::Catalog;
use serde::Serialize;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

const PROFILE: &str = "spec/package/mck/portable-local-registry-cases.json";
const SCHEMA: &str = "spec/package/schemas/portable-local-registry-profile.schema.json";
const SCHEMA_ID: &str = "https://morphir.finos.org/spec/package/local-library-portable/0.1.0-draft.1/portable-local-registry-profile.schema.json";
const GROUPS: [&str; 5] = [
    "common",
    "posix",
    "windows",
    "case-sensitive",
    "case-insensitive",
];

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PortableProfileSummary {
    pub kind: &'static str,
    pub case_count: usize,
    pub derived_case_count: usize,
    pub pending_definition_count: usize,
    /// Source-derivation closure only, never the eventual portable asset count.
    pub source_asset_count: usize,
    pub source_bound_asset_count: usize,
    pub source_pending_asset_count: usize,
    pub errors: Vec<String>,
}

struct Inspected {
    profile: Value,
    derived: usize,
    source_bound: usize,
    source_pending: usize,
}

pub fn inspect_portable_profile(source: &dyn CorpusSource) -> PortableProfileSummary {
    match inspect(source) {
        Ok(loaded) => PortableProfileSummary {
            kind: "definition-planning-summary",
            case_count: loaded.profile["cases"]
                .as_array()
                .expect("validated cases")
                .len(),
            derived_case_count: loaded.derived,
            pending_definition_count: loaded.profile["cases"]
                .as_array()
                .expect("validated cases")
                .len(),
            source_asset_count: loaded.source_bound + loaded.source_pending,
            source_bound_asset_count: loaded.source_bound,
            source_pending_asset_count: loaded.source_pending,
            errors: vec![],
        },
        Err(error) => PortableProfileSummary {
            kind: "definition-planning-summary",
            case_count: 0,
            derived_case_count: 0,
            pending_definition_count: 0,
            source_asset_count: 0,
            source_bound_asset_count: 0,
            source_pending_asset_count: 0,
            errors: vec![error],
        },
    }
}

fn inspect(source: &dyn CorpusSource) -> Result<Inspected, String> {
    let schema = super::corpus::decode(&source.read(SCHEMA)?)?;
    if schema["$id"] != SCHEMA_ID {
        return Err("unknown portable profile schema identity".into());
    }
    let catalog = Catalog::compile(&BTreeMap::from([(SCHEMA.to_owned(), schema)]))?;
    let profile = super::corpus::decode(&source.read(PROFILE)?)?;
    catalog.validate(SCHEMA, &profile)?;
    validate_memberships(&profile)?;
    validate_environments(&profile)?;

    // Preserve original draft.3 schema, observations and source semantic checks.
    // Derived recipes cannot bypass them by declaring only a subset of fixtures.
    let mut corpus = Corpus::load(source)?;
    let validated = semantics::validate(&mut corpus)?;
    let originals: BTreeMap<_, _> = corpus
        .cases
        .iter()
        .filter(|case| {
            case["family"] != "publication"
                && case["id"] != "local-registry.filesystem.special-file"
                && case["id"] != "local-registry.filesystem.case-collision"
        })
        .map(|case| (case["id"].as_str().expect("validated source id"), case))
        .collect();
    let mut derived = BTreeSet::new();
    let mut source_assets = BTreeSet::new();
    for case in list(&profile["cases"])? {
        if case["provenance"]["kind"] == "source-case" {
            let source_id = text(&case["provenance"]["caseId"])?;
            let original = originals
                .get(source_id)
                .ok_or_else(|| format!("invalid source derivation {source_id}"))?;
            if !derived.insert(source_id) {
                return Err(format!("duplicate source derivation {source_id}"));
            }
            validate_derivation(case, original)?;
            collect_assets(original, &validated.documents, &mut source_assets)?;
        }
    }
    if derived != originals.keys().copied().collect() {
        return Err("missing required source derivation".into());
    }
    let assets: BTreeMap<_, _> = list(&corpus.index["assets"])?
        .iter()
        .map(|asset| (asset["id"].as_str().expect("validated asset id"), asset))
        .collect();
    let mut source_bound = 0;
    let mut source_pending = 0;
    for id in source_assets {
        let asset = assets
            .get(id.as_str())
            .ok_or_else(|| format!("unknown source asset {id}"))?;
        if asset["kind"] == "bound" {
            source_bound += 1;
        } else {
            source_pending += 1;
        }
    }
    let derived_count = derived.len();
    Ok(Inspected {
        profile,
        derived: derived_count,
        source_bound,
        source_pending,
    })
}

fn validate_memberships(profile: &Value) -> Result<(), String> {
    let mut cases = BTreeMap::new();
    for case in list(&profile["cases"])? {
        let id = text(&case["id"])?;
        if cases.insert(id, text(&case["group"])?).is_some() {
            return Err(format!("duplicate case {id}"));
        }
    }
    let mut members = BTreeSet::new();
    for group in GROUPS {
        for member in list(&profile["requiredGroups"][group])? {
            let id = text(member)?;
            if !members.insert(id) {
                return Err(format!("duplicate required membership {id}"));
            }
            let expected = cases
                .get(id)
                .ok_or_else(|| format!("unknown required membership {id}"))?;
            if *expected != group {
                return Err(format!(
                    "wrong required membership {id}: expected {expected}, found {group}"
                ));
            }
        }
    }
    for id in cases.keys() {
        if !members.contains(id) {
            return Err(format!("missing required membership {id}"));
        }
    }
    Ok(())
}

fn environment_id(os: &str, architecture: &str, case_sensitivity: &str) -> String {
    match os {
        "linux" => format!("linux-ext4-{architecture}"),
        "macos" => format!("macos-apfs-{architecture}-{case_sensitivity}"),
        _ => format!("windows-ntfs-{architecture}"),
    }
}

fn validate_environments(profile: &Value) -> Result<(), String> {
    let mut seen = BTreeSet::new();
    for environment in list(&profile["environments"])? {
        let id = text(&environment["id"])?;
        if !seen.insert(id.to_owned()) {
            return Err(format!("duplicate environment {id}"));
        }
        let os = text(&environment["os"])?;
        let sensitivity = text(&environment["caseSensitivity"])?;
        let filesystem = match os {
            "linux" => "ext4",
            "macos" => "apfs",
            _ => "ntfs",
        };
        if environment["filesystem"] != filesystem
            || (os == "linux" && sensitivity != "sensitive")
            || (os == "windows" && sensitivity != "insensitive")
            || id != environment_id(os, text(&environment["architecture"])?, sensitivity)
        {
            return Err(format!("environment identity mismatch {id}"));
        }
        let expected = json!([
            "common",
            if os == "windows" { "windows" } else { "posix" },
            format!("case-{sensitivity}")
        ]);
        if environment["requiredGroups"] != expected {
            return Err(format!("environment groups mismatch {id}"));
        }
    }
    for architecture in ["x86-64", "aarch64"] {
        for (os, sensitivity) in [
            ("linux", "sensitive"),
            ("macos", "sensitive"),
            ("macos", "insensitive"),
            ("windows", "insensitive"),
        ] {
            let id = environment_id(os, architecture, sensitivity);
            if !seen.contains(&id) {
                return Err(format!("missing environment {id}"));
            }
        }
    }
    Ok(())
}

fn validate_derivation(case: &Value, original: &Value) -> Result<(), String> {
    let source_id = text(&original["id"])?;
    if case["id"] != source_id.replacen("local-registry.", "portable-local-registry.", 1)
        || case["group"] != "common"
    {
        return Err(format!("source derivation identity mismatch {source_id}"));
    }
    let scenario = original["kind"] == "scenario";
    let removals: Vec<_> = if scenario {
        list(&original["setup"]["registries"])?
            .iter()
            .enumerate()
            .map(|(i, _)| format!("/setup/registries/{i}/publisher"))
            .collect()
    } else {
        vec![]
    };
    let expected = json!({
        "removeSetup": removals,
        "removeObservations": if scenario { vec!["/registries/*/reserved"] } else { vec![] },
        "operations": "unchanged",
        "consumptionObservations": if scenario { "complete" } else { "not-applicable" }
    });
    if case["derivation"] != expected {
        return Err(format!("invalid portable derivation {source_id}"));
    }
    Ok(())
}

fn collect_assets(
    value: &Value,
    documents: &BTreeMap<String, Value>,
    seen: &mut BTreeSet<String>,
) -> Result<(), String> {
    match value {
        Value::Array(items) => {
            for item in items {
                collect_assets(item, documents, seen)?;
            }
        }
        Value::Object(object) => {
            if let Some(asset) = object.get("asset") {
                let id = text(asset)?;
                if seen.insert(id.into())
                    && let Some(document) = documents.get(id)
                {
                    collect_assets(document, documents, seen)?;
                }
            }
            for (key, child) in object {
                if key != "assertions" {
                    collect_assets(child, documents, seen)?;
                }
            }
        }
        _ => {}
    }
    Ok(())
}

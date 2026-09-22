use super::{
    corpus::{Corpus, decode, fixture_path},
    result, scenario,
    validation::*,
};
use crate::kit::hash::sha256_hex;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
#[derive(Default)]
pub(super) struct Validated {
    pub bytes: BTreeMap<String, Vec<u8>>,
    pub documents: BTreeMap<String, Value>,
}
struct Validation<'a, 's> {
    loaded: &'a mut Corpus<'s>,
    assets: BTreeMap<String, Value>,
    validated: Validated,
    visiting: BTreeSet<String>,
}
impl Validation<'_, '_> {
    fn reference(&mut self, id: &Value, kind: &str) -> Result<Option<Value>, String> {
        let id = text(id)?;
        let asset = self
            .assets
            .get(id)
            .ok_or_else(|| format!("unknown asset reference {id}"))?
            .clone();
        if asset["type"] != kind {
            return Err(format!("wrong asset type {id}: expected {kind}"));
        }
        if asset["kind"] == "pending" {
            return Ok(None);
        }
        if self.visiting.contains(id) {
            return Err(format!("cyclic asset reference {id}"));
        }
        if self.validated.bytes.contains_key(id) {
            return Ok(self.validated.documents.get(id).cloned());
        }
        self.visiting.insert(id.into());
        let bytes = self.loaded.read(&fixture_path(&asset["path"], false)?)?;
        if bytes.len().to_string() != text(&asset["length"])? {
            return Err(format!("asset length mismatch {id}"));
        }
        if format!("sha256:{}", sha256_hex(&bytes)) != text(&asset["sha256"])? {
            return Err(format!("asset digest mismatch {id}"));
        }
        if kind != "bytes" {
            let value = decode(&bytes)?;
            let mut title = kind.to_owned();
            if let Some(first) = title.get_mut(..1) {
                first.make_ascii_uppercase();
            }
            self.loaded.validate(&title, &value)?;
            calendar(&value)?;
            match kind {
                "tree" => tree(&value)?,
                "result" => result::validate(&value, None, false)?,
                "configuration" => {
                    let bindings = list(&value["bindings"])?;
                    let roots = list(&value["bootstrapRoots"])?;
                    unique(bindings.iter().map(|b| &b["alias"]), "configuration alias")?;
                    let identities = roots
                        .iter()
                        .map(|r| serde_json::json!([r["identity"], r["version"]]))
                        .collect::<Vec<_>>();
                    unique(&identities, "bootstrap identity/version")?;
                    for binding in bindings {
                        if !roots.iter().any(|r| r["identity"] == binding["identity"]) {
                            return Err("configuration identity has no bootstrap bytes".into());
                        }
                    }
                }
                _ => {}
            }
            self.walk(&value, "")?;
            self.validated.documents.insert(id.into(), value);
        }
        self.validated.bytes.insert(id.into(), bytes);
        self.visiting.remove(id);
        Ok(self.validated.documents.get(id).cloned())
    }
    fn walk(&mut self, value: &Value, key: &str) -> Result<(), String> {
        match value {
            Value::Array(items) => {
                for child in items {
                    self.walk(child, key)?;
                }
            }
            Value::Object(object) => {
                if let Some(id) = object.get("asset") {
                    let kind = match key {
                        "expectedObservations" => "observations",
                        "expected" => "result",
                        "configuration" => "configuration",
                        "tree" | "cache" | "bundle" | "proposal" => "tree",
                        _ => "bytes",
                    };
                    let complete = self.reference(id, kind)?;
                    if let Some(assertions) = object.get("assertions") {
                        validate_assertions(assertions, complete.as_ref())?;
                    }
                }
                for (key, child) in object {
                    if key != "assertions" {
                        self.walk(child, key)?;
                    }
                }
            }
            _ => {}
        }
        Ok(())
    }
}
fn pointer<'a>(value: &'a Value, path: &str) -> Result<&'a Value, String> {
    value
        .pointer(path)
        .ok_or_else(|| format!("missing assertion pointer {path}"))
}
fn validate_assertions(value: &Value, complete: Option<&Value>) -> Result<(), String> {
    let entries = list(value)?;
    unique(entries.iter().map(|e| &e["pointer"]), "assertion pointer")?;
    for left in entries {
        let at = text(&left["pointer"])?;
        for right in entries {
            let below = text(&right["pointer"])?;
            if below != at && below.starts_with(&format!("{at}/")) {
                equal(
                    pointer(&left["equals"], &below[at.len()..])?,
                    &right["equals"],
                    "contradictory assertions",
                )?;
            }
        }
        if let Some(value) = complete {
            equal(
                pointer(value, at)?,
                &left["equals"],
                &format!("assertion {at}"),
            )?;
        }
    }
    Ok(())
}
pub(super) fn validate(loaded: &mut Corpus<'_>) -> Result<Validated, String> {
    let assets = list(&loaded.index["assets"])?;
    unique(assets.iter().map(|a| &a["id"]), "asset ID")?;
    unique(loaded.cases.iter().map(|c| &c["id"]), "case ID")?;
    let mut paths = loaded.paths.clone();
    for asset in assets {
        if asset["kind"] == "bound" {
            let name = fixture_path(&asset["path"], false)?;
            if !paths.insert(name.clone()) {
                return Err(format!("duplicate logical asset path {name}"));
            }
        }
    }
    let assets = assets
        .iter()
        .map(|a| Ok((text(&a["id"])?.to_owned(), a.clone())))
        .collect::<Result<BTreeMap<_, _>, String>>()?;
    let mut validation = Validation {
        loaded,
        assets,
        validated: Validated::default(),
        visiting: BTreeSet::new(),
    };
    for asset in list(&validation.loaded.index["assets"])?.to_vec() {
        validation.reference(&asset["id"], text(&asset["type"])?)?;
    }
    for entry in validation.loaded.cases.clone() {
        calendar(&entry)?;
        validation.walk(&entry, "")?;
        let parse = entry["kind"] == "parse";
        let operations = if parse {
            std::slice::from_ref(&entry)
        } else {
            list(&entry["operations"])?
        };
        for operation in operations {
            let expected = &operation["expected"];
            let complete = match text(&expected["kind"])? {
                "inline" => Some(&expected["result"]),
                "asset" => validation
                    .validated
                    .documents
                    .get(text(&expected["asset"])?),
                _ => None,
            };
            if let Some(value) = complete {
                validation.loaded.validate("Result", value)?;
                result::validate(value, (!parse).then_some(operation), parse)?;
            }
        }
        if entry["kind"] == "scenario" {
            scenario::validate(&entry, &validation.validated)?;
        }
    }
    Ok(validation.validated)
}

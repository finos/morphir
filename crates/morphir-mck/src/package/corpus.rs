use super::contract::{Artifact, Library, LibraryFile, Schemas};
use super::json::{Document, array, digest, fields, hex, nonempty, string};
use super::schemas::{self, Catalog};
use super::{Contract, Operation, Request};
use crate::kit::hash::{ContentDigest, content_hash};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Path, PathBuf},
};

#[derive(Debug, Clone)]
pub struct Case {
    pub id: String,
    pub request: Request,
    expected: Value,
}
impl Case {
    pub fn expected(&self) -> &Value {
        &self.expected
    }
}
pub struct Kit {
    pub contract: Contract,
    pub content_hash: ContentDigest,
    pub cases: Vec<Case>,
    pub errors: Vec<String>,
    pub(super) catalog: Option<Catalog>,
}
impl Kit {
    pub fn project_response(&self, operation: Operation, value: &Value) -> Result<Value, String> {
        if !self.contract.operations().contains(&operation) {
            return Err("operation does not belong to package contract".into());
        }
        super::projection::project(
            operation,
            value,
            self.catalog.as_ref().ok_or("invalid package kit")?,
        )
    }
}
struct Files {
    root: PathBuf,
    mck: PathBuf,
    used: BTreeMap<String, Vec<u8>>,
}
impl Files {
    fn bytes(&mut self, name: &str) -> Result<Vec<u8>, String> {
        let candidate = match name.strip_prefix("mck/") {
            Some(relative) => self.mck.join(relative),
            None => self.root.join(name),
        };
        let resolved = candidate
            .canonicalize()
            .map_err(|e| format!("{name}: {e}"))?;
        let boundary = if name.starts_with("mck/") {
            &self.mck
        } else {
            &self.root
        };
        if !resolved.starts_with(boundary) || resolved == *boundary {
            return Err(format!("fixture path is not confined: {name}"));
        }
        let bytes = std::fs::read(resolved).map_err(|e| format!("{name}: {e}"))?;
        self.used.insert(name.into(), bytes.clone());
        Ok(bytes)
    }
    fn document(&mut self, name: &str) -> Result<Document, String> {
        Document::parse(&self.bytes(name)?).map_err(|e| format!("{name}: {e}"))
    }
    fn value(&mut self, name: &str) -> Result<Value, String> {
        self.document(name).map(|d| d.value())
    }
}
/// `directory` is `spec/package/mck`; only its fixed schemas and confined cases are read.
/// Loader errors are reportable kit errors and never start an adapter.
pub fn load_kit(directory: &Path, contract: Contract) -> Kit {
    let mut files = Files {
        root: PathBuf::new(),
        mck: PathBuf::new(),
        used: BTreeMap::new(),
    };
    let loaded = (|| {
        files.mck = directory.canonicalize().map_err(|e| e.to_string())?;
        files.root = files
            .mck
            .parent()
            .ok_or("missing package directory")?
            .to_path_buf();
        match contract {
            Contract::Integrity => integrity(&mut files),
            Contract::Resolution => resolution(&mut files),
        }
    })();
    let content_hash = content_hash(
        files
            .used
            .iter()
            .map(|(name, bytes)| (name.as_str(), bytes.as_slice())),
    );
    match loaded {
        Ok((cases, catalog)) => Kit {
            contract,
            content_hash,
            cases,
            errors: Vec::new(),
            catalog: Some(catalog),
        },
        Err(error) => Kit {
            contract,
            content_hash,
            cases: Vec::new(),
            errors: vec![error],
            catalog: None,
        },
    }
}
fn document(value: &Value, names: &[&str], contract: Contract) -> Result<(), String> {
    let mut required = vec!["formatVersion"];
    required.extend(names);
    fields(value, &required, &[])?;
    if value["formatVersion"] != contract.as_str() {
        return Err("unsupported package corpus formatVersion".into());
    }
    Ok(())
}
fn cases(value: &Value) -> Result<&Vec<Value>, String> {
    let cases = array(value)?;
    if cases.is_empty() {
        Err("empty case collection".into())
    } else {
        Ok(cases)
    }
}
fn unique(cases: &[Case]) -> Result<(), String> {
    let mut ids = BTreeSet::new();
    for case in cases {
        if !ids.insert(&case.id) {
            return Err(format!("duplicate case id {}", case.id));
        }
    }
    if cases.is_empty() {
        return Err("empty package corpus".into());
    }
    Ok(())
}
fn add(
    cases: &mut Vec<Case>,
    entry: &Value,
    request: Request,
    expected: Value,
) -> Result<(), String> {
    cases.push(Case {
        id: nonempty(&entry["id"])?.into(),
        request,
        expected,
    });
    Ok(())
}
fn mutate(source: &Document, entry: &Document) -> Result<Document, String> {
    let value = entry.value();
    let mut result = source.clone();
    if value.get("replace").is_some() && value.get("remove").is_some() {
        return Err("replace and remove are mutually exclusive".into());
    }
    let (path, replacement) = if let Some(replace) = value.get("replace") {
        fields(replace, &["path", "value"], &[])?;
        (
            &replace["path"],
            Some(entry.get("replace")?.get("value")?.clone()),
        )
    } else if let Some(remove) = value.get("remove") {
        (remove, None)
    } else {
        return Ok(result);
    };
    let path = array(path)?
        .iter()
        .map(|key| nonempty(key).map(String::from))
        .collect::<Result<Vec<_>, _>>()?;
    result.mutate(&path, replacement)?;
    Ok(result)
}
fn expectation(entry: &Value) -> Result<Value, String> {
    match entry["expected"].as_str() {
        Some("accept") => Ok(json!({"ok":true,"valid":true})),
        Some("reject") => Ok(json!({"ok":true,"valid":false})),
        _ => Err("unknown validation expectation".into()),
    }
}
fn load_schemas(
    files: &mut Files,
    names: &[&str],
) -> Result<(BTreeMap<String, Value>, Catalog), String> {
    let schemas = names
        .iter()
        .map(|name| Ok(((*name).into(), files.value(name)?)))
        .collect::<Result<BTreeMap<_, _>, String>>()?;
    let catalog = Catalog::compile(&schemas)?;
    Ok((schemas, catalog))
}
fn integrity(files: &mut Files) -> Result<(Vec<Case>, Catalog), String> {
    let mut parsed = Vec::new();
    let docs = files.value("mck/digest-vectors.json")?;
    document(&docs, &["cases", "byteCases"], Contract::Integrity)?;
    for entry in cases(&docs["cases"])? {
        let expected = if entry.get("error").is_some() {
            fields(entry, &["id", "input", "error"], &[])?;
            if entry["error"] != "invalid-document" {
                return Err("unknown normalization error".into());
            }
            json!({"ok":false,"error":"invalid-document"})
        } else {
            fields(
                entry,
                &[
                    "id",
                    "input",
                    "canonical",
                    "manifestDigest",
                    "packageContentDigest",
                ],
                &[],
            )?;
            json!({"ok":true,"canonical":string(&entry["canonical"] )?,"manifestDigest":digest(&entry["manifestDigest"] )?,"packageContentDigest":digest(&entry["packageContentDigest"] )?})
        };
        add(
            &mut parsed,
            entry,
            Request::Normalize {
                input: string(&entry["input"])?.into(),
            },
            expected,
        )?;
    }
    for entry in cases(&docs["byteCases"])? {
        fields(entry, &["id", "hex", "digest"], &[])?;
        add(
            &mut parsed,
            entry,
            Request::HashBytes {
                hex: hex(&entry["hex"])?.into(),
            },
            json!({"ok":true,"digest":digest(&entry["digest"] )?}),
        )?;
    }
    let (schema_values, catalog) = load_schemas(files, schemas::INTEGRITY)?;
    let schemas = Schemas {
        manifest: schema_values[schemas::INTEGRITY[0]].clone(),
        lock: schema_values[schemas::INTEGRITY[1]].clone(),
    };
    let fixtures = Document::Object(vec![
        (
            "eligibility".into(),
            files.document("mck/fixtures/two-libraries/eligibility/manifest.json")?,
        ),
        (
            "consumer".into(),
            files.document("mck/fixtures/two-libraries/loan-rules/manifest.json")?,
        ),
        (
            "lock".into(),
            files.document("mck/fixtures/two-libraries/lock-core.json")?,
        ),
    ]);
    let schema_document = files.document("mck/schema-cases.json")?;
    document(&schema_document.value(), &["cases"], Contract::Integrity)?;
    let Document::Array(entries) = schema_document.get("cases")? else {
        return Err("expected case array".into());
    };
    if entries.is_empty() {
        return Err("empty case collection".into());
    }
    for source in entries {
        let entry = source.value();
        fields(
            &entry,
            &["id", "schema", "fixture", "expected"],
            &["replace", "remove"],
        )?;
        let artifact = match string(&entry["schema"])? {
            "manifest" => Artifact::Manifest,
            "lock" => Artifact::Lock,
            _ => return Err("unknown schema".into()),
        };
        let fixture = nonempty(&entry["fixture"])?;
        if !["eligibility", "consumer", "lock"].contains(&fixture) {
            return Err("unknown fixture".into());
        }
        if (fixture == "lock") != (artifact == Artifact::Lock) {
            return Err("fixture/schema mismatch".into());
        }
        let input = mutate(fixtures.get(fixture)?, source)?.text();
        add(
            &mut parsed,
            &entry,
            Request::Validate {
                artifact,
                input,
                schemas: schemas.clone(),
            },
            expectation(&entry)?,
        )?;
    }
    let libraries_doc = files.document("mck/library-cases.json")?;
    document(&libraries_doc.value(), &["cases"], Contract::Integrity)?;
    let payloads = [
        files.bytes("mck/fixtures/two-libraries/eligibility/ir.json")?,
        files.bytes("mck/fixtures/two-libraries/loan-rules/ir.json")?,
    ]
    .map(|bytes| bytes.iter().map(|b| format!("{b:02x}")).collect::<String>());
    let Document::Array(entries) = libraries_doc.get("cases")? else {
        return Err("expected case array".into());
    };
    if entries.is_empty() {
        return Err("empty case collection".into());
    }
    for source in entries {
        let entry = source.value();
        fields(
            &entry,
            &["id", "expected"],
            &["replace", "remove", "payloadSuffix", "lockText"],
        )?;
        if entry.get("lockText").is_some()
            && (entry.get("replace").is_some() || entry.get("remove").is_some())
        {
            return Err("lockText and mutation are mutually exclusive".into());
        }
        let modified = mutate(&fixtures, source)?;
        let suffix = if let Some(suffix) = entry.get("payloadSuffix") {
            fields(suffix, &["library", "hex"], &[])?;
            let name = string(&suffix["library"])?;
            if !["eligibility", "consumer"].contains(&name) {
                return Err("unknown payload fixture".into());
            }
            Some((name, hex(&suffix["hex"])?))
        } else {
            None
        };
        let libraries = ["eligibility", "consumer"]
            .iter()
            .enumerate()
            .map(|(index, name)| {
                let addition = suffix
                    .filter(|(library, _)| library == name)
                    .map_or("", |(_, bytes)| bytes);
                Ok(Library {
                    manifest: modified.get(name)?.text(),
                    files: vec![LibraryFile {
                        path: "ir.json".into(),
                        hex: format!("{}{addition}", payloads[index]),
                    }],
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        let lock = match entry.get("lockText") {
            Some(value) => string(value)?.into(),
            None => modified.get("lock")?.text(),
        };
        add(
            &mut parsed,
            &entry,
            Request::VerifyLibrarySet {
                lock,
                libraries,
                schemas: schemas.clone(),
            },
            expectation(&entry)?,
        )?;
    }
    unique(&parsed)?;
    Ok((parsed, catalog))
}
fn resolution(files: &mut Files) -> Result<(Vec<Case>, Catalog), String> {
    let (_, catalog) = load_schemas(files, schemas::RESOLUTION)?;
    let index = files.value("mck/resolution-cases.json")?;
    catalog.validate("schemas/resolution-case.schema.json", &index)?;
    document(&index, &["fixtures"], Contract::Resolution)?;
    let mut parsed = Vec::new();
    let pattern =
        regex::Regex::new(r"\Afixtures/resolution/[a-z-]+\.json\z").expect("fixed pattern");
    for relative in array(&index["fixtures"])? {
        let relative = string(relative)?;
        if !pattern.is_match(relative) {
            return Err(format!("fixture path is not confined: {relative}"));
        }
        let name = format!("mck/{relative}");
        let fixture = files.value(&name)?;
        catalog.validate("schemas/resolution-case.schema.json", &fixture)?;
        document(&fixture, &["cases"], Contract::Resolution)?;
        for entry in cases(&fixture["cases"])? {
            fields(
                entry,
                &["id", "family", "description", "input", "expected"],
                &[],
            )?;
            let expected = &entry["expected"];
            super::projection::project(Operation::ResolveLibrary, expected, &catalog)?;
            add(
                &mut parsed,
                entry,
                Request::ResolveLibrary {
                    input: string(&entry["input"])?.into(),
                },
                expected.clone(),
            )?;
        }
    }
    unique(&parsed)?;
    Ok((parsed, catalog))
}

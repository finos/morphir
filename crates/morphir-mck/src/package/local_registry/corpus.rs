use super::validation::{list, text};
use jsonschema::{Resource, Retrieve, Uri, Validator};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Path, PathBuf},
};

pub const INDEX: &str = "spec/package/mck/local-registry-cases.json";
const CASE_SCHEMA: &str =
    "https://morphir.finos.org/spec/package/0.1.0-draft.3/local-registry-case.schema.json";
const SCHEMAS: &[(&str, &str)] = &[
    (CASE_SCHEMA, "local-registry-case"),
    (
        "https://morphir.finos.org/spec/package/0.1.0-draft.1/library-manifest.schema.json",
        "library-manifest",
    ),
    (
        "https://morphir.finos.org/spec/package/0.1.0-draft.1/lock-core.schema.json",
        "lock-core",
    ),
    (
        "https://morphir.finos.org/spec/package/0.1.0-draft.2/resolution-input.schema.json",
        "resolution-input",
    ),
    (
        "https://morphir.finos.org/spec/package/0.1.0-draft.2/resolution-result.schema.json",
        "resolution-result",
    ),
];
/// Supplies owned bytes for a confined repository-relative logical path.
pub trait CorpusSource {
    fn read(&self, path: &str) -> Result<Vec<u8>, String>;
}
pub type FileMapSource = BTreeMap<String, Vec<u8>>;
impl CorpusSource for FileMapSource {
    fn read(&self, path: &str) -> Result<Vec<u8>, String> {
        logical_path(path)?;
        self.get(path)
            .cloned()
            .ok_or_else(|| format!("missing corpus file {path}"))
    }
}
/// Loads trusted static fixtures. This is not a runtime filesystem provider.
pub struct RepositorySource {
    root: PathBuf,
}
impl RepositorySource {
    pub fn new(root: impl AsRef<Path>) -> Result<Self, String> {
        Ok(Self {
            root: root.as_ref().canonicalize().map_err(|e| e.to_string())?,
        })
    }
}
impl CorpusSource for RepositorySource {
    fn read(&self, name: &str) -> Result<Vec<u8>, String> {
        logical_path(name)?;
        let target = self
            .root
            .join(name)
            .canonicalize()
            .map_err(|e| format!("{name}: {e}"))?;
        let scope = if name.starts_with("spec/package/schemas/") {
            "spec/package/schemas"
        } else if name.starts_with("spec/package/mck/fixtures/") {
            "spec/package/mck/fixtures/local-registry"
        } else {
            "spec/package/mck"
        };
        let confined = self.root.join(scope);
        if target == confined || !target.starts_with(confined) {
            return Err(format!("path is not confined: {name}"));
        }
        std::fs::read(target).map_err(|e| format!("{name}: {e}"))
    }
}
pub(super) fn logical_path(name: &str) -> Result<(), String> {
    if name.contains(['\\', '\0', '\r', '\n'])
        || name
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
    {
        return Err(format!("path is not confined: {name}"));
    }
    Ok(())
}
pub(super) fn fixture_path(value: &Value, cases: bool) -> Result<String, String> {
    let name = text(value)?;
    logical_path(name)?;
    let relative = name
        .strip_prefix("fixtures/local-registry/")
        .ok_or_else(|| format!("fixture path is not confined: {name}"))?;
    let (area, rest) = relative
        .split_once('/')
        .ok_or("fixture path is not confined")?;
    if !["assets", "cases", "expected"].contains(&area)
        || (cases && area != "cases")
        || !rest
            .as_bytes()
            .first()
            .is_some_and(u8::is_ascii_alphanumeric)
        || !rest
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"./-".contains(&b))
    {
        return Err(format!("fixture path is not confined: {name}"));
    }
    Ok(format!("spec/package/mck/{name}"))
}
pub(super) fn decode(bytes: &[u8]) -> Result<Value, String> {
    super::super::json::parse(std::str::from_utf8(bytes).map_err(|e| e.to_string())?)
}
struct Offline;
impl Retrieve for Offline {
    fn retrieve(&self, uri: &Uri<&str>) -> Result<Value, Box<dyn std::error::Error + Send + Sync>> {
        Err(format!("unknown local schema ID {uri}").into())
    }
}
pub(super) struct Corpus<'a> {
    source: &'a dyn CorpusSource,
    pub consumed: BTreeMap<String, Vec<u8>>,
    validators: BTreeMap<String, Validator>,
    pub index: Value,
    pub cases: Vec<Value>,
    pub paths: BTreeSet<String>,
    pub schemas: BTreeMap<String, Value>,
}
impl<'a> Corpus<'a> {
    pub fn load(source: &'a dyn CorpusSource) -> Result<Self, String> {
        let mut loaded = Self {
            source,
            consumed: BTreeMap::new(),
            validators: BTreeMap::new(),
            index: Value::Null,
            cases: vec![],
            paths: BTreeSet::new(),
            schemas: BTreeMap::new(),
        };
        loaded.load_schema(CASE_SCHEMA)?;
        for definition in [
            "Index",
            "CaseFile",
            "Result",
            "Tree",
            "Configuration",
            "Observations",
        ] {
            let mut options = jsonschema::draft202012::options();
            options.with_retriever(Offline);
            for (id, schema) in &loaded.schemas {
                options.with_resource(
                    id,
                    Resource::from_contents(schema.clone()).map_err(|e| e.to_string())?,
                );
            }
            let validator = options
                .build(&json!({"$ref":format!("{CASE_SCHEMA}#/$defs/{definition}")}))
                .map_err(|e| format!("{definition}: {e}"))?;
            loaded.validators.insert(definition.into(), validator);
        }
        loaded.read("spec/package/mck/README.md")?;
        loaded.index = decode(&loaded.read(INDEX)?)?;
        loaded.validate("Index", &loaded.index)?;
        for fixture in list(&loaded.index["fixtures"])?.to_vec() {
            let name = fixture_path(&fixture, true)?;
            if !loaded.paths.insert(name.clone()) {
                return Err(format!("duplicate fixture path {name}"));
            }
            let document = decode(&loaded.read(&name)?)?;
            loaded.validate("CaseFile", &document)?;
            loaded.cases.extend_from_slice(list(&document["cases"])?);
        }
        Ok(loaded)
    }
    pub fn read(&mut self, name: &str) -> Result<Vec<u8>, String> {
        logical_path(name)?;
        if let Some(bytes) = self.consumed.get(name) {
            return Ok(bytes.clone());
        }
        let bytes = self.source.read(name)?;
        self.consumed.insert(name.into(), bytes.clone());
        Ok(bytes)
    }
    pub fn validate(&self, definition: &str, value: &Value) -> Result<(), String> {
        self.validators
            .get(definition)
            .ok_or_else(|| format!("unknown definition {definition}"))?
            .validate(value)
            .map_err(|e| {
                format!(
                    "{definition} schema validation failed: {e} at {}",
                    e.instance_path
                )
            })
    }
    fn load_schema(&mut self, id: &str) -> Result<(), String> {
        if self.schemas.contains_key(id) {
            return Ok(());
        }
        let name = SCHEMAS
            .iter()
            .find(|(known, _)| *known == id)
            .map(|(_, name)| name)
            .ok_or_else(|| format!("unknown local schema ID {id}"))?;
        let schema = decode(&self.read(&format!("spec/package/schemas/{name}.schema.json"))?)?;
        if schema["$id"] != id {
            return Err(format!("unknown local schema ID {}", schema["$id"]));
        }
        self.schemas.insert(id.into(), schema.clone());
        let mut references = vec![];
        fn visit(value: &Value, refs: &mut Vec<String>) {
            match value {
                Value::Array(items) => {
                    for item in items {
                        visit(item, refs);
                    }
                }
                Value::Object(object) => {
                    if let Some(reference) = object.get("$ref").and_then(Value::as_str) {
                        refs.push(reference.into());
                    }
                    for child in object.values() {
                        visit(child, refs);
                    }
                }
                _ => {}
            }
        }
        visit(&schema, &mut references);
        for reference in references {
            let mut url = url::Url::parse(id)
                .map_err(|e| e.to_string())?
                .join(&reference)
                .map_err(|e| e.to_string())?;
            url.set_fragment(None);
            self.load_schema(url.as_str())?;
        }
        Ok(())
    }
}

//! Admission of the fixed linked-metadata reference corpus into the shared kit.
//! This validates the authored inputs; it does not execute metadata operations.

use std::collections::BTreeSet;

use jsonschema::{Retrieve, Uri};
use serde_json::Value;

use crate::kit::KitSource;
use crate::kit::hash::sha256_hex;

const CORPUS: &str = "spec/ir/mck/metadata-contract-draft.json";
const SCHEMA: &str = "spec/ir/mck/metadata-contract-draft.schema.json";
const PREFIX: &str = "spec/ir/mck/";

struct OfflineOnly;

impl Retrieve for OfflineOnly {
    fn retrieve(&self, uri: &Uri<&str>) -> Result<Value, Box<dyn std::error::Error + Send + Sync>> {
        Err(format!("reference outside the offline metadata schema: {uri}").into())
    }
}

fn read(source: &KitSource, path: &str) -> Result<Vec<u8>, String> {
    source
        .read(path)
        .map_err(|error| format!("{path}: {error}"))?
        .map(|bytes| bytes.into_owned())
        .ok_or_else(|| format!("missing metadata input {path}"))
}

fn json(source: &KitSource, path: &str) -> Result<Value, String> {
    serde_json::from_slice(&read(source, path)?)
        .map_err(|error| format!("{path}: invalid JSON: {error}"))
}

fn fixture_path(relative: &str) -> Result<String, String> {
    if !relative.starts_with("metadata-fixtures/")
        || relative.contains('\\')
        || relative
            .split('/')
            .any(|part| part.is_empty() || part == "." || part == "..")
    {
        return Err(format!("unsafe metadata fixture path {relative}"));
    }
    Ok(format!("{PREFIX}{relative}"))
}

struct Declarations {
    predicates: BTreeSet<String>,
    sidecar_predicates: BTreeSet<String>,
}

fn sdk_arity(target: &str) -> Option<usize> {
    match target {
        "morphir/SDK:basics#bool" | "morphir/SDK:basics#int" | "morphir/SDK:string#string" => {
            Some(0)
        }
        "morphir/SDK:list#list" | "morphir/SDK:maybe#maybe" => Some(1),
        "morphir/SDK:dict#dict" => Some(2),
        _ => None,
    }
}

fn check_role(entry: &Value, expected: &str, path: &str, group: &str) -> Result<(), String> {
    if entry["declarationRole"] != expected {
        return Err(format!(
            "{path}: {group} declarationRole must be {expected}"
        ));
    }
    Ok(())
}

fn check_shape(shape: &Value, types: &BTreeSet<String>, path: &str) -> Result<(), String> {
    let kind = shape["kind"]
        .as_str()
        .ok_or_else(|| format!("{path}: data type needs shape.kind"))?;
    match kind {
        "boolean" | "unit" => Ok(()),
        "alias" => {
            if !shape["typeParams"].is_array() {
                return Err(format!("{path}: alias shape needs typeParams"));
            }
            check_shape(&shape["body"], types, path)
        }
        "record" => {
            if shape["closed"] != true {
                return Err(format!("{path}: record shape requires closed=true"));
            }
            let fields = shape["fields"]
                .as_object()
                .ok_or_else(|| format!("{path}: record shape needs fields"))?;
            for (name, field) in fields {
                check_shape(field, types, &format!("{path}.{name}"))?;
            }
            Ok(())
        }
        "custom" => {
            if !shape["typeParams"].is_array() {
                return Err(format!("{path}: custom shape needs typeParams"));
            }
            let constructors = shape["constructors"]
                .as_object()
                .filter(|values| !values.is_empty())
                .ok_or_else(|| format!("{path}: custom shape needs constructors"))?;
            for (name, arguments) in constructors {
                let arguments = arguments
                    .as_array()
                    .ok_or_else(|| format!("{path}: constructor {name} needs arguments"))?;
                for argument in arguments {
                    check_shape(argument, types, &format!("{path}.{name}"))?;
                }
            }
            Ok(())
        }
        "reference" => {
            let target = shape["type"]
                .as_str()
                .ok_or_else(|| format!("{path}: reference shape needs type"))?;
            let arguments = shape["arguments"]
                .as_array()
                .ok_or_else(|| format!("{path}: reference shape needs arguments"))?;
            if let Some(arity) = sdk_arity(target) {
                if arguments.len() != arity {
                    return Err(format!("{path}: {target} needs {arity} arguments"));
                }
            } else if !types.contains(target) {
                return Err(format!("{path}: undeclared data type {target}"));
            }
            for argument in arguments {
                check_shape(argument, types, path)?;
            }
            if let Some(encoding) = shape["jsonEncoding"].as_str() {
                let string_key = arguments.first().is_some_and(|key| {
                    key["kind"] == "reference"
                        && key["type"] == "morphir/SDK:string#string"
                        && key["arguments"].as_array().is_some_and(Vec::is_empty)
                });
                if encoding != "string-keyed-object"
                    || target != "morphir/SDK:dict#dict"
                    || !string_key
                {
                    return Err(format!(
                        "{path}: string-keyed-object requires Dict String values"
                    ));
                }
            }
            Ok(())
        }
        _ => Err(format!("{path}: unsupported data shape {kind}")),
    }
}

fn declared_closure(source: &KitSource, relative: &str) -> Result<Declarations, String> {
    let path = fixture_path(relative)?;
    let closure = json(source, &path)?;
    let object = closure
        .as_object()
        .ok_or_else(|| format!("{path}: expected an object"))?;
    let mut groups = Vec::new();
    for field in [
        "predicates",
        "dataTypes",
        "sidecarEntryPoints",
        "annotations",
    ] {
        let entries = object
            .get(field)
            .and_then(Value::as_array)
            .ok_or_else(|| format!("{path}: {field} must be an array"))?;
        if entries.is_empty() {
            return Err(format!("{path}: {field} must not be empty"));
        }
        let mut uris = BTreeSet::new();
        for entry in entries {
            let uri = entry
                .get(if field == "sidecarEntryPoints" {
                    "entryPoint"
                } else {
                    "uri"
                })
                .and_then(Value::as_str)
                .filter(|uri| uri.starts_with("morphir://ir/"))
                .ok_or_else(|| format!("{path}: {field} entry needs a Morphir URI"))?;
            if !uris.insert(uri) {
                return Err(format!("{path}: duplicate {field} declaration {uri}"));
            }
        }
        groups.push(uris.into_iter().map(str::to_owned).collect::<BTreeSet<_>>());
    }
    let data_types = &groups[1];
    for data_type in object["dataTypes"].as_array().expect("checked above") {
        check_role(data_type, "TypeSpecification", &path, "dataTypes")?;
        let uri = data_type["uri"].as_str().expect("checked above");
        check_shape(&data_type["shape"], data_types, &format!("{path}: {uri}"))?;
    }
    for predicate in object["predicates"].as_array().expect("checked above") {
        check_role(predicate, "ValueSpecification", &path, "predicates")?;
        let uri = predicate["uri"].as_str().expect("checked above");
        let kind = predicate["object"]["kind"]
            .as_str()
            .ok_or_else(|| format!("{path}: {uri} needs an object kind"))?;
        match kind {
            "data" | "json" => {
                let type_uri = predicate["object"]["type"]
                    .as_str()
                    .ok_or_else(|| format!("{path}: {uri} needs an object type"))?;
                let declared = if kind == "data" {
                    sdk_arity(type_uri) == Some(0) || data_types.contains(type_uri)
                } else {
                    data_types.contains(type_uri)
                };
                if !declared {
                    return Err(format!("{path}: {uri} has undeclared data type {type_uri}"));
                }
            }
            "node" => {
                if !matches!(
                    predicate["object"]["targetKind"].as_str(),
                    Some("Type" | "Value")
                ) {
                    return Err(format!("{path}: {uri} has unsupported node targetKind"));
                }
            }
            _ => return Err(format!("{path}: {uri} has unsupported object kind {kind}")),
        }
        let subjects = predicate["subjects"]
            .as_array()
            .filter(|values| !values.is_empty())
            .ok_or_else(|| format!("{path}: {uri} needs subjects"))?;
        for subject in subjects {
            if !matches!(
                subject.as_str(),
                Some(
                    "TypeSpecification"
                        | "TypeDefinition"
                        | "ValueSpecification"
                        | "ValueDefinition"
                )
            ) {
                return Err(format!(
                    "{path}: {uri} has unsupported subjects entry {subject}"
                ));
            }
        }
        let interpretation = &predicate["interpretation"];
        match interpretation["kind"].as_str() {
            Some("descriptive") => {}
            Some("required")
                if interpretation["id"]
                    .as_str()
                    .is_some_and(|id| !id.is_empty()) => {}
            _ => return Err(format!("{path}: {uri} has invalid interpretation")),
        }
    }
    let mut sidecar_predicates = BTreeSet::new();
    for entry in object["sidecarEntryPoints"]
        .as_array()
        .expect("checked above")
    {
        let type_uri = entry["type"]
            .as_str()
            .ok_or_else(|| format!("{path}: sidecar entry point needs a type"))?;
        if !data_types.contains(type_uri) {
            return Err(format!(
                "{path}: sidecar entry point has undeclared data type {type_uri}"
            ));
        }
        let predicate = entry["projectionPredicate"]
            .as_str()
            .ok_or_else(|| format!("{path}: sidecar entry point needs projectionPredicate"))?;
        sidecar_predicates.insert(predicate.to_owned());
    }
    for annotation in object["annotations"].as_array().expect("checked above") {
        check_role(annotation, "AnnotationDeclaration", &path, "annotations")?;
        if annotation["name"].as_str().is_none_or(str::is_empty) {
            return Err(format!("{path}: annotation declaration needs name"));
        }
    }
    Ok(Declarations {
        predicates: groups.remove(0),
        sidecar_predicates,
    })
}

fn fixture(source: &KitSource, value: &Value, allow_missing: bool) -> Result<(), String> {
    if let Some(relative) = value.as_str()
        && relative.starts_with("metadata-fixtures/")
        && !allow_missing
    {
        read(source, &fixture_path(relative)?)?;
    }
    Ok(())
}

fn check_fixture_references(source: &KitSource, case: &Value, id: &str) -> Result<(), String> {
    let given = &case["given"];
    let operation = case["operation"]
        .as_str()
        .expect("schema validated operation");
    match operation {
        "resolveContext" => {
            let unavailable = case["expected"]["diagnostic"] == "context_resource_unavailable";
            fixture(source, &given["import"], unavailable)?;
            if let Some(imports) = given["imports"].as_array() {
                for import in imports {
                    fixture(source, import, unavailable)?;
                }
            }
            if let Some(context) = given["context"].as_array() {
                for reference in context {
                    fixture(source, reference, false)?;
                }
            }
            fixture(source, &given["baseFile"], false)?;
            fixture(source, &given["acceptedResource"], false)?;
            fixture(source, &given["resourceFile"], false)?;
        }
        "publish" => {
            fixture(source, &given["contextFile"], false)?;
            fixture(source, &given["publishedContextFile"], false)?;
        }
        _ => {}
    }
    if let (Some(resource), Some(relative)) =
        (given["resource"].as_str(), given["resourceFile"].as_str())
    {
        let expected = resource
            .strip_prefix("morphir://context/sha256/")
            .ok_or_else(|| format!("{id}: resource must be a content-addressed context URI"))?;
        let bytes = read(source, &fixture_path(relative)?)?;
        if sha256_hex(&bytes) != expected {
            return Err(format!("{id}: resource digest does not match {relative}"));
        }
    }
    if case["expected"]["outcome"] == "accepted"
        && let Some(relative) = given["acceptedResource"].as_str()
    {
        let imports = given["imports"]
            .as_array()
            .into_iter()
            .flatten()
            .chain(std::iter::once(&given["import"]));
        let addresses: Vec<_> = imports
            .filter_map(Value::as_str)
            .filter_map(|text| text.strip_prefix("morphir://context/sha256/"))
            .collect();
        if addresses.len() > 1 {
            return Err(format!(
                "{id}: acceptedResource has multiple content addresses"
            ));
        }
        if let Some(expected) = addresses.first()
            && sha256_hex(&read(source, &fixture_path(relative)?)?) != *expected
        {
            return Err(format!("{id}: import digest does not match {relative}"));
        }
    }
    Ok(())
}

fn check_targets(source: &KitSource, case: &Value, id: &str) -> Result<(), String> {
    let targets = case["targets"]
        .as_array()
        .filter(|targets| !targets.is_empty())
        .ok_or_else(|| format!("{id}: targets must be a nonempty array"))?;
    if case["operation"] != "profileEquivalence" {
        if targets.len() != 1 || targets[0]["profile"] != "json" || targets[0]["layout"] != "single"
        {
            return Err(format!(
                "{id}: ordinary reference case targets must be json/single"
            ));
        }
        return Ok(());
    }

    let fixtures = case["given"]["fixtures"]
        .as_object()
        .ok_or_else(|| format!("{id}: profileEquivalence needs given.fixtures"))?;
    let profiles: BTreeSet<_> = targets
        .iter()
        .map(|target| {
            target["profile"]
                .as_str()
                .ok_or_else(|| format!("{id}: target profile must be a string"))
        })
        .collect::<Result<_, _>>()?;
    let fixture_profiles: BTreeSet<_> = fixtures.keys().map(String::as_str).collect();
    if profiles.len() != targets.len() || profiles != fixture_profiles {
        return Err(format!(
            "{id}: targets must name exactly the profiles in given.fixtures"
        ));
    }
    for target in targets {
        let profile = target["profile"]
            .as_str()
            .ok_or_else(|| format!("{id}: target profile must be a string"))?;
        let (layout, expected_fixture) = match profile {
            "json" => ("single", "metadata-fixtures/profiles/value.json"),
            "yaml" => ("single", "metadata-fixtures/profiles/value.yaml"),
            "ion" => ("record", "metadata-fixtures/profiles/value.ion"),
            _ => return Err(format!("{id}: unsupported target profile {profile}")),
        };
        if target["layout"] != layout {
            return Err(format!("{id}: {profile} target layout must be {layout}"));
        }
        let relative = fixtures[profile]
            .as_str()
            .ok_or_else(|| format!("{id}: {profile} fixture must be a path string"))?;
        let path = fixture_path(relative).map_err(|error| format!("{id}: {error}"))?;
        if relative != expected_fixture {
            return Err(format!(
                "{id}: {profile} fixture must be {expected_fixture}"
            ));
        }
        read(source, &path).map_err(|error| format!("{id}: {error}"))?;
    }
    Ok(())
}

/// `None` means an older/ad-hoc kit has no metadata reference corpus.
/// A present corpus must be completely admitted before any kit command succeeds.
pub(crate) fn admit(source: &KitSource) -> Result<Option<usize>, String> {
    if source
        .read(CORPUS)
        .map_err(|error| format!("{CORPUS}: {error}"))?
        .is_none()
    {
        if source
            .read(SCHEMA)
            .map_err(|error| format!("{SCHEMA}: {error}"))?
            .is_some()
        {
            return Err(format!("{CORPUS}: missing metadata corpus for {SCHEMA}"));
        }
        return Ok(None);
    }
    let schema = json(source, SCHEMA)?;
    let corpus = json(source, CORPUS)?;
    let validator = jsonschema::options()
        .with_retriever(OfflineOnly)
        .build(&schema)
        .map_err(|error| format!("{SCHEMA}: {error}"))?;
    if let Err(error) = validator.validate(&corpus) {
        return Err(format!("{CORPUS}: {error} at {}", error.instance_path));
    }
    let closure = corpus["schemaClosure"]
        .as_str()
        .ok_or_else(|| format!("{CORPUS}: missing schemaClosure"))?;
    let declarations = declared_closure(source, closure)?;
    let cases = corpus["cases"]
        .as_array()
        .ok_or_else(|| format!("{CORPUS}: cases must be an array"))?;
    let mut ids = BTreeSet::new();
    for case in cases {
        let id = case["id"].as_str().expect("schema validated case id");
        if !ids.insert(id) {
            return Err(format!("{CORPUS}: duplicate metadata case id {id}"));
        }
        check_targets(source, case, id)?;
        check_fixture_references(source, case, id)?;
        if case["expected"]["outcome"] == "accepted"
            && let Some(facts) = case["expected"]["facts"].as_array()
        {
            for fact in facts {
                let predicate = fact["predicate"].as_str().expect("schema validated fact");
                if !declarations.predicates.contains(predicate)
                    && !declarations.sidecar_predicates.contains(predicate)
                {
                    return Err(format!("{id}: undeclared predicate {predicate}"));
                }
            }
        }
        if case["operation"] == "publish" && case["expected"]["outcome"] == "accepted" {
            let given = &case["given"];
            let context_file = given["contextFile"]
                .as_str()
                .ok_or_else(|| format!("{id}: accepted publication needs contextFile"))?;
            let digest = given["contextDigest"]
                .as_str()
                .and_then(|text| text.strip_prefix("sha256:"))
                .ok_or_else(|| format!("{id}: accepted publication needs contextDigest"))?;
            if sha256_hex(&read(source, &fixture_path(context_file)?)?) != digest {
                return Err(format!(
                    "{id}: context digest does not match {context_file}"
                ));
            }
            let published_file = given["publishedContextFile"]
                .as_str()
                .ok_or_else(|| format!("{id}: accepted publication needs publishedContextFile"))?;
            let inventory = case["expected"]["inventory"]
                .as_array()
                .and_then(|items| items.first())
                .and_then(|item| item["sha256"].as_str())
                .ok_or_else(|| format!("{id}: accepted publication needs inventory digest"))?;
            if sha256_hex(&read(source, &fixture_path(published_file)?)?) != inventory {
                return Err(format!(
                    "{id}: published context digest does not match {published_file}"
                ));
            }
        }
    }
    Ok(Some(cases.len()))
}

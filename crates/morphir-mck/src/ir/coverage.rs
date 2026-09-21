//! IR coverage uses the frozen first driver's JSON-key heuristic. It does not
//! decode IR, filter by IR version, or inspect YAML and referenced documents.
//!
//! JSON parsing retains serde_json's nesting and finite-number limits. The
//! parity fixtures and repository corpus fit those limits; arbitrary JSON
//! accepted by JavaScript's JSON.parse can exceed them.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

use serde::Deserialize;
use serde_json::Value;

use crate::kit::KitSource;
use crate::kit::syntax::case::{KitCase, Status};
use crate::kit::syntax::info_string::Language;

const VOCABULARY_PATH: &str = "spec/mck/vocabulary.json";

/// A validated vocabulary. Construction checks version, structure, and node
/// references; callers cannot mutate entries after validation.
#[derive(Debug)]
pub struct Vocabulary {
    nodes: BTreeSet<String>,
    aliases: BTreeMap<String, String>,
    entries: Vec<Entry>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct VocabularyDocument {
    vocabulary_version: u64,
    ir_version: u64,
    #[serde(rename = "description")]
    _description: String,
    nodes: Vec<String>,
    aliases: BTreeMap<String, String>,
    entries: Vec<Entry>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Entry {
    node: String,
    variant: String,
    members: Vec<Member>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Member {
    name: String,
    #[serde(rename = "spelling")]
    _spelling: Spelling,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum Spelling {
    Canonical,
    Legacy,
}

/// A vocabulary could not be read or did not satisfy its contract.
#[derive(Debug)]
pub struct VocabularyError(String);

impl fmt::Display for VocabularyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{VOCABULARY_PATH}: {}", self.0)
    }
}

impl std::error::Error for VocabularyError {}

fn identifier(value: &str) -> bool {
    value.as_bytes().first().is_some_and(u8::is_ascii_uppercase)
        && value.bytes().all(|byte| byte.is_ascii_alphanumeric())
}

impl Vocabulary {
    /// Read the vocabulary belonging to this source, including embedded kits.
    pub fn load(source: &KitSource) -> Result<Self, VocabularyError> {
        let bytes = source.read(VOCABULARY_PATH)
            .map_err(|error| VocabularyError(error.to_string()))?
            .ok_or_else(|| VocabularyError("not found in the selected kit source; use --repo-root for a standalone kit directory".into()))?;
        Self::parse(&bytes)
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, VocabularyError> {
        let document: VocabularyDocument =
            serde_json::from_slice(bytes).map_err(|error| VocabularyError(error.to_string()))?;
        if document.vocabulary_version != 1 {
            return Err(VocabularyError("vocabularyVersion must be 1".into()));
        }
        if document.ir_version == 0 {
            return Err(VocabularyError(
                "irVersion must be a positive integer".into(),
            ));
        }
        let nodes: BTreeSet<_> = document.nodes.iter().cloned().collect();
        if nodes.is_empty()
            || nodes.len() != document.nodes.len()
            || !nodes.iter().all(|node| identifier(node))
        {
            return Err(VocabularyError(
                "nodes must contain unique node identifiers".into(),
            ));
        }
        for (alias, node) in &document.aliases {
            if !nodes.contains(node) {
                return Err(VocabularyError(format!(
                    "alias {alias} refers to unknown node {node}"
                )));
            }
            if nodes.contains(alias) {
                return Err(VocabularyError(format!(
                    "alias {alias} conflicts with a canonical node"
                )));
            }
        }
        for entry in &document.entries {
            if !nodes.contains(&entry.node) {
                return Err(VocabularyError(format!(
                    "entry refers to unknown node {}",
                    entry.node
                )));
            }
            if entry.variant.is_empty() {
                return Err(VocabularyError("variant must not be empty".into()));
            }
            for member in &entry.members {
                if member.name.is_empty() {
                    return Err(VocabularyError("member name must not be empty".into()));
                }
            }
        }
        Ok(Self {
            nodes,
            aliases: document.aliases,
            entries: document.entries,
        })
    }

    fn resolve_node<'a>(&'a self, name: &'a str) -> Option<&'a str> {
        self.nodes
            .get(name)
            .map(String::as_str)
            .or_else(|| self.aliases.get(name).map(String::as_str))
    }
}

/// The missing obligation, preserving vocabulary entry and member order.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Gap {
    Variant {
        node: String,
        variant: String,
    },
    Member {
        node: String,
        variant: String,
        member: String,
    },
}

impl fmt::Display for Gap {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Variant { node, variant } => write!(f, "{node}/{variant} has no case"),
            Self::Member {
                node,
                variant,
                member,
            } => write!(f, "{node}/{variant} member {member} has no case"),
        }
    }
}

fn json_fences(case: &KitCase) -> impl Iterator<Item = Value> + '_ {
    case.fences
        .iter()
        .filter(|fence| fence.info.language == Language::Json)
        .filter_map(|fence| serde_json::from_str(&fence.body).ok())
}

fn walk(value: &Value, visit: &mut impl FnMut(&str, &Value)) {
    match value {
        Value::Array(values) => {
            for value in values {
                walk(value, visit);
            }
        }
        Value::Object(values) => {
            for (key, value) in values {
                visit(key, value);
                walk(value, visit);
            }
        }
        _ => {}
    }
}

/// Pure coverage, ported from the TypeScript driver's frozen coverage rule.
/// Matching an object key is intentional, even if that key is a record field
/// rather than an IR tag. This heuristic is not an IR decoder.
pub fn coverage_gaps(cases: &[KitCase], vocabulary: &Vocabulary) -> Vec<Gap> {
    let recognized: Vec<_> = cases
        .iter()
        .filter_map(|case| {
            vocabulary
                .resolve_node(case.node.as_deref()?)
                .map(|node| (node, case))
        })
        .collect();
    let mut variant_nodes: BTreeMap<&str, BTreeSet<&str>> = BTreeMap::new();
    for entry in &vocabulary.entries {
        variant_nodes
            .entry(&entry.variant)
            .or_default()
            .insert(&entry.node);
    }
    let mut gaps = Vec::new();
    for entry in &vocabulary.entries {
        let scoped: Vec<_> = recognized
            .iter()
            .filter(|(node, _)| *node == entry.node)
            .map(|(_, case)| *case)
            .collect();
        let ambiguous = variant_nodes[entry.variant.as_str()].len() > 1;
        let mut variant_seen = false;
        let mut member_seen = BTreeSet::new();
        for (_, case) in recognized.iter().filter(|(node, case)| {
            case.status != Status::Pending && (!ambiguous || *node == entry.node)
        }) {
            for json in json_fences(case) {
                walk(&json, &mut |key, _| {
                    if key == entry.variant {
                        variant_seen = true;
                    }
                });
            }
        }
        for case in scoped.iter().filter(|case| case.status != Status::Pending) {
            for json in json_fences(case) {
                walk(&json, &mut |key, payload| {
                    if key == entry.variant {
                        variant_seen = true;
                        if let Value::Object(members) = payload {
                            member_seen.extend(members.keys().cloned());
                        }
                    }
                });
            }
        }
        for case in scoped.iter().filter(|case| case.status == Status::Pending) {
            let text = format!("{}\n{}", case.title, case.prose.join("\n"));
            if text.contains(&entry.variant) {
                variant_seen = true;
                member_seen.extend(
                    entry
                        .members
                        .iter()
                        .filter(|member| text.contains(&member.name))
                        .map(|member| member.name.clone()),
                );
            }
        }
        if !variant_seen {
            gaps.push(Gap::Variant {
                node: entry.node.clone(),
                variant: entry.variant.clone(),
            });
        }
        for member in &entry.members {
            if !member_seen.contains(&member.name) {
                gaps.push(Gap::Member {
                    node: entry.node.clone(),
                    variant: entry.variant.clone(),
                    member: member.name.clone(),
                });
            }
        }
    }
    gaps
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::kit::{KitSource, load_kit};
    use std::borrow::Cow;

    const VOCABULARY: &str = r#"{
        "vocabularyVersion":1, "irVersion":4, "description":"fixture",
        "nodes":["Type","Value","TypeDefinition","AccessControlledTypeDefinition","IRFile"],
        "aliases":{"Distribution":"IRFile"},
        "entries":[
            {"node":"Type","variant":"Record","members":[{"name":"fields","spelling":"canonical"}]},
            {"node":"Value","variant":"Record","members":[{"name":"fields","spelling":"canonical"}]},
            {"node":"TypeDefinition","variant":"TypeAliasDefinition","members":[{"name":"body","spelling":"canonical"}]},
            {"node":"IRFile","variant":"Library","members":[]}
        ]
    }"#;

    fn kit(markdown: &str) -> crate::kit::Kit {
        load_kit(KitSource::map(
            "coverage fixture",
            BTreeMap::from([
                (
                    "spec/ir/mck/types.md".into(),
                    Cow::Owned(markdown.as_bytes().to_vec()),
                ),
                (
                    "spec/mck/vocabulary.json".into(),
                    Cow::Borrowed(VOCABULARY.as_bytes()),
                ),
                (
                    "fixture.json".into(),
                    Cow::Borrowed(b"{\"Library\":{}}".as_slice()),
                ),
            ]),
        ))
        .unwrap()
    }

    fn gaps(markdown: &str) -> Vec<String> {
        let kit = kit(markdown);
        assert!(kit.errors.is_empty(), "{:?}", kit.errors);
        let vocabulary = Vocabulary::load(&kit.source).unwrap();
        coverage_gaps(&kit.cases, &vocabulary)
            .iter()
            .map(ToString::to_string)
            .collect()
    }

    #[test]
    fn ambiguous_variants_and_members_stay_node_scoped() {
        assert_eq!(
            gaps(
                "## types-0001: record {node=Value}\n```json canonical\n{\"Record\":{\"fields\":[]}}\n```\n"
            ),
            [
                "Type/Record has no case",
                "Type/Record member fields has no case",
                "TypeDefinition/TypeAliasDefinition has no case",
                "TypeDefinition/TypeAliasDefinition member body has no case",
                "IRFile/Library has no case"
            ]
        );
    }

    #[test]
    fn nested_unambiguous_variants_cross_nodes_but_members_do_not() {
        assert_eq!(
            gaps(
                "## types-0001: public alias {node=AccessControlledTypeDefinition}\n```json canonical\n{\"Public\":[{\"TypeAliasDefinition\":{\"body\":{}}}]}\n```\n"
            ),
            [
                "Type/Record has no case",
                "Type/Record member fields has no case",
                "Value/Record has no case",
                "Value/Record member fields has no case",
                "TypeDefinition/TypeAliasDefinition member body has no case",
                "IRFile/Library has no case"
            ]
        );
    }

    #[test]
    fn aliases_resolve_but_unknown_and_absent_nodes_are_ignored() {
        let result = gaps(
            "## types-0001: alias {node=Distribution}\n```json canonical\n{\"Library\":{}}\n```\n\n## types-0002: unknown {node=Unknown}\n```json canonical\n{\"TypeAliasDefinition\":{}}\n```\n\n## types-0003: absent\n```json canonical\n{\"TypeAliasDefinition\":{}}\n```\n",
        );
        assert!(!result.iter().any(|g| g.starts_with("IRFile/")));
        assert!(result.contains(&"TypeDefinition/TypeAliasDefinition has no case".to_owned()));
    }

    #[test]
    fn pending_uses_title_and_prose_only_and_requires_variant_for_members() {
        assert_eq!(
            gaps(
                "## types-0001: Record {node=Type status=pending}\nfields is pending\n\n## types-0002: fields {node=Value status=pending}\n\n## types-0003: deferred {node=TypeDefinition status=pending}\n```json rejected diagnostic=invalid\n{\"TypeAliasDefinition\":{\"body\":{}}}\n```\n\n## types-0004: Library {node=Distribution status=pending}\n"
            ),
            [
                "Value/Record has no case",
                "Value/Record member fields has no case",
                "TypeDefinition/TypeAliasDefinition has no case",
                "TypeDefinition/TypeAliasDefinition member body has no case"
            ]
        );
    }

    #[test]
    fn member_payload_must_be_an_object_and_member_must_be_a_direct_key() {
        for payload in ["null", "[\"fields\"]", "{\"nested\":{\"fields\":[]}}"] {
            let result = gaps(&format!(
                "## types-0001: record {{node=Type}}\n```json canonical\n{{\"Record\":{payload}}}\n```\n"
            ));
            assert!(!result.contains(&"Type/Record has no case".to_owned()));
            assert!(result.contains(&"Type/Record member fields has no case".to_owned()));
        }
    }

    #[test]
    fn every_inline_json_role_counts_at_any_version_but_invalid_json_does_not() {
        for info in [
            "canonical",
            "accepted",
            "rejected diagnostic=invalid",
            "file path=entry.json set=input",
        ] {
            // The pure engine intentionally works independently of kit structural errors.
            let kit = kit(&format!(
                "## types-0001: record {{node=Type version=1}}\n```json {info}\n[{{\"Record\":{{\"fields\":[]}}}}]\n```\n"
            ));
            let result = coverage_gaps(
                &kit.cases,
                &Vocabulary::parse(VOCABULARY.as_bytes()).unwrap(),
            );
            assert!(
                !result
                    .iter()
                    .any(|g| g.to_string().starts_with("Type/Record")),
                "{info}: {result:?}"
            );
        }
        assert!(gaps("## types-0001: invalid {node=Type}\n```json canonical\n{\"Record\":{\"fields\":[]}\n```\n").contains(&"Type/Record has no case".to_owned()));
    }

    #[test]
    fn yaml_and_text_are_ignored_even_when_they_contain_json() {
        let result = gaps(
            "## types-0001: yaml {node=Type}\n```yaml canonical\n{\"Record\":{\"fields\":[]}}\n```\n\n## types-0002: reference {node=IRFile}\n```text canonical\nfixture.json\n```\n",
        );
        assert!(result.contains(&"Type/Record has no case".to_owned()));
        assert!(result.contains(&"IRFile/Library has no case".to_owned()));
    }

    #[test]
    fn gaps_keep_vocabulary_order_and_distinguish_variants_from_members() {
        let vocabulary = Vocabulary::parse(VOCABULARY.as_bytes()).unwrap();
        let result = coverage_gaps(&[], &vocabulary);
        assert!(
            matches!(&result[0], Gap::Variant { node, variant } if node == "Type" && variant == "Record")
        );
        assert!(
            matches!(&result[1], Gap::Member { node, variant, member } if node == "Type" && variant == "Record" && member == "fields")
        );
        assert_eq!(
            result.iter().map(ToString::to_string).collect::<Vec<_>>(),
            [
                "Type/Record has no case",
                "Type/Record member fields has no case",
                "Value/Record has no case",
                "Value/Record member fields has no case",
                "TypeDefinition/TypeAliasDefinition has no case",
                "TypeDefinition/TypeAliasDefinition member body has no case",
                "IRFile/Library has no case"
            ]
        );
    }

    #[test]
    fn vocabulary_validates_version_structure_and_references() {
        for invalid in [
            VOCABULARY.replace("\"vocabularyVersion\":1", "\"vocabularyVersion\":2"),
            VOCABULARY.replace("\"irVersion\":4", "\"irVersion\":0"),
            VOCABULARY.replace(
                "\"Distribution\":\"IRFile\"",
                "\"Distribution\":\"Missing\"",
            ),
            VOCABULARY.replace("\"node\":\"Type\"", "\"node\":\"Missing\""),
            VOCABULARY.replace("\"variant\":\"Record\"", "\"variant\":\"\""),
            VOCABULARY.replace("\"name\":\"fields\"", "\"name\":\"\""),
            VOCABULARY.replace("\"canonical\"", "\"unknown\""),
            VOCABULARY.replace("\"nodes\":[\"Type\"", "\"nodes\":[\"Type\",\"Type\""),
            VOCABULARY.replace("\"Type\"", "\"bad-node\""),
            VOCABULARY.replace("\"description\":\"fixture\",", ""),
            VOCABULARY.replace(
                "\"description\":\"fixture\"",
                "\"description\":\"fixture\",\"extra\":true",
            ),
        ] {
            assert!(Vocabulary::parse(invalid.as_bytes()).is_err(), "{invalid}");
        }
    }

    #[test]
    fn repository_and_embedded_corpora_have_no_gaps() {
        for source in [
            crate::kit::embedded::embedded_source(),
            KitSource::directory(
                &std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../spec/ir/mck"),
                None,
            ),
        ] {
            let kit = load_kit(source).unwrap();
            assert!(kit.errors.is_empty());
            assert_eq!(
                coverage_gaps(&kit.cases, &Vocabulary::load(&kit.source).unwrap()),
                []
            );
        }
    }
}

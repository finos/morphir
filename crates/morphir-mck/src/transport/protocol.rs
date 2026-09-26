//! IR adapter protocol, contract versions 1 and 2 (`spec/ir/mck/protocol.schema.json`).
//!
//! An adapter is a foreign process, so nothing it sends is trusted until it is
//! checked. Every guard rejects unknown members, matching the schema's
//! `additionalProperties: false`: the contract grows only through
//! `contractVersion`, never through an added-but-ignored key. A failed check
//! is a [`ProtocolError`] naming the member, which the runner reports as a
//! kit error rather than letting a malformed answer pass as a result.
//!
//! Requests are written with the members in the order the first driver wrote
//! them, so a replayed transcript sees the same bytes.

use std::fmt;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

use crate::format_version::{DOMAIN_FLOOR, SupportTable};

pub const CONTRACT_VERSION: u64 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdapterContract {
    V1,
    V2,
}

impl AdapterContract {
    pub fn as_u64(self) -> u64 {
        match self {
            Self::V1 => 1,
            Self::V2 => 2,
        }
    }
}

/// A response or envelope that breaks the protocol.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProtocolError(pub String);

impl fmt::Display for ProtocolError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ProtocolError {}

fn fail<T>(message: impl Into<String>) -> Result<T, ProtocolError> {
    Err(ProtocolError(message.into()))
}

macro_rules! closed_enum {
    ($name:ident, $what:literal, { $($variant:ident => $text:literal),+ $(,)? }) => {
        #[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
        pub enum $name {
            $(#[serde(rename = $text)] $variant),+
        }

        impl $name {
            pub const ALL: &'static [Self] = &[$(Self::$variant),+];

            pub fn as_str(self) -> &'static str {
                match self {
                    $(Self::$variant => $text),+
                }
            }

            pub fn parse(text: &str) -> Option<Self> {
                match text {
                    $($text => Some(Self::$variant),)+
                    _ => None,
                }
            }

            #[allow(dead_code)]
            fn allowed() -> String {
                Self::ALL.iter().map(|v| v.as_str()).collect::<Vec<_>>().join(", ")
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.as_str())
            }
        }

        const _: &str = $what;
    };
}

closed_enum!(Profile, "profile", { Json => "json", Yaml => "yaml" });
closed_enum!(CapabilitiesProfile, "capabilities profile", { Json => "json", Yaml => "yaml", Ion => "ion" });

impl From<Profile> for CapabilitiesProfile {
    fn from(value: Profile) -> Self {
        match value {
            Profile::Json => Self::Json,
            Profile::Yaml => Self::Yaml,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VersionTwo;

impl Serialize for VersionTwo {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_u8(2)
    }
}
closed_enum!(Layout, "layout", { Single => "single", Tree => "tree" });
closed_enum!(PathMode, "path", { Current => "current", Pinned => "pinned" });
closed_enum!(Stage, "stage", { Syntax => "syntax", Normalization => "normalization", Semantic => "semantic" });

/// What an adapter says it can do.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Capabilities {
    pub contract_version: AdapterContract,
    pub binding: String,
    pub language: String,
    /// The canonical spelling of `table`, as the adapter sent it.
    pub format_versions: String,
    pub table: SupportTable,
    pub versions: Vec<u32>,
    pub profiles: Vec<CapabilitiesProfile>,
    pub layouts: Vec<Layout>,
    pub paths: Vec<PathMode>,
    /// Node kinds as the kit names them, aliases included.
    pub nodes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TreeFile {
    pub path: String,
    pub content: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WritePolicy {
    pub profile: Profile,
    pub path_budget: u64,
}

/// A request, serialized with the first driver's member order.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "op", rename_all = "camelCase")]
pub enum Request {
    Capabilities,
    #[serde(rename = "capabilities")]
    CapabilitiesV2 {
        #[serde(rename = "contractVersion")]
        contract_version: VersionTwo,
    },
    Decode {
        version: u32,
        profile: Profile,
        path: PathMode,
        strip: bool,
        node: String,
        input: String,
    },
    ReadTree {
        version: u32,
        profile: Profile,
        path: PathMode,
        strip: bool,
        node: String,
        files: Vec<TreeFile>,
    },
    WriteTree {
        version: u32,
        path: PathMode,
        policy: WritePolicy,
        input: String,
    },
    Exit,
}

impl Request {
    pub fn capabilities_v2() -> Self {
        Self::CapabilitiesV2 {
            contract_version: VersionTwo,
        }
    }
    /// The request as one protocol line, without its trailing newline.
    pub fn line(&self, id: u64) -> String {
        let body = serde_json::to_string(self).expect("requests serialize");
        format!("{{\"id\":{id},{}", &body[1..])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Warning {
    pub code: String,
    pub cursor: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diagnostic {
    pub code: String,
    pub stage: Option<Stage>,
    pub cursor: Option<String>,
    pub message: Option<String>,
}

/// The answer to `decode` and `readTree`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecodeResponse {
    Ok {
        kind: String,
        canonical: Vec<(Profile, String)>,
        warnings: Vec<Warning>,
    },
    Rejected(Diagnostic),
}

impl DecodeResponse {
    pub fn canonical(&self, profile: Profile) -> Option<&str> {
        match self {
            Self::Ok { canonical, .. } => canonical
                .iter()
                .find(|(p, _)| *p == profile)
                .map(|(_, text)| text.as_str()),
            Self::Rejected(_) => None,
        }
    }
}

/// The answer to `writeTree`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WriteTreeResponse {
    Ok { files: Vec<TreeFile> },
    Rejected(Diagnostic),
}

type Object = Map<String, Value>;

fn object<'a>(value: &'a Value, what: &str) -> Result<&'a Object, ProtocolError> {
    value
        .as_object()
        .map_or_else(|| fail(format!("{what} must be an object")), Ok)
}

fn known_keys(o: &Object, allowed: &[&str], prefix: &str) -> Result<(), ProtocolError> {
    match o.keys().find(|key| !allowed.contains(&key.as_str())) {
        Some(key) => fail(format!("unknown field \"{prefix}{key}\"")),
        None => Ok(()),
    }
}

fn string<'a>(o: &'a Object, key: &str) -> Result<&'a str, ProtocolError> {
    o.get(key)
        .and_then(Value::as_str)
        .map_or_else(|| fail(format!("\"{key}\" must be a string")), Ok)
}

fn listed<T: Copy>(
    o: &Object,
    key: &str,
    parse: impl Fn(&str) -> Option<T>,
    allowed: &str,
) -> Result<Vec<T>, ProtocolError> {
    let Some(items) = o.get(key).and_then(Value::as_array) else {
        return fail(format!("\"{key}\" must be an array"));
    };
    items
        .iter()
        .map(|item| {
            item.as_str().and_then(&parse).map_or_else(
                || {
                    fail(format!(
                        "\"{key}\" contains {item}, expected one of {allowed}"
                    ))
                },
                Ok,
            )
        })
        .collect()
}

/// A JSON number that is an integer, however it was spelled (`1` or `1.0`).
fn integer(value: &Value) -> Option<i64> {
    value.as_i64().or_else(|| {
        value
            .as_f64()
            .filter(|f| f.fract() == 0.0 && f.abs() < 9.0e15)
            .map(|f| f as i64)
    })
}

/// Splits one protocol line into its id and body.
pub fn parse_envelope(line: &str) -> Result<(u64, Object), ProtocolError> {
    let value: Value = serde_json::from_str(line).map_err(|_| {
        let shown: String = line.chars().take(200).collect();
        ProtocolError(format!("not a JSON line: {shown}"))
    })?;
    let Value::Object(mut body) = value else {
        return fail("message must be a JSON object");
    };
    let Some(id) = body.get("id").and_then(integer) else {
        return fail("missing id");
    };
    if id < 1 {
        return fail(format!("\"id\" must be at least 1, got {id}"));
    }
    body.remove("id");
    Ok((id as u64, body))
}

pub fn parse_capabilities(value: &Value) -> Result<Capabilities, ProtocolError> {
    let o = object(value, "capabilities")?;
    known_keys(
        o,
        &[
            "contractVersion",
            "binding",
            "language",
            "formatVersions",
            "versions",
            "profiles",
            "layouts",
            "paths",
            "nodes",
        ],
        "",
    )?;
    let contract_version = match o.get("contractVersion").and_then(integer) {
        Some(1) => AdapterContract::V1,
        Some(2) => AdapterContract::V2,
        _ => {
            return fail(format!(
                "unsupported contractVersion {}; this driver speaks 1 and {CONTRACT_VERSION}",
                o.get("contractVersion")
                    .map_or_else(|| "undefined".to_owned(), Value::to_string)
            ));
        }
    };
    let versions: Vec<u32> = match o.get("versions").and_then(Value::as_array) {
        Some(items) => items
            .iter()
            .map(|n| {
                integer(n)
                    .filter(|n| *n > 0)
                    .and_then(|n| u32::try_from(n).ok())
            })
            .collect::<Option<_>>()
            .map_or_else(|| fail("\"versions\" must be positive integers"), Ok)?,
        None => return fail("\"versions\" must be positive integers"),
    };
    // An adapter that decodes no node kinds has nothing to say about the kit.
    let nodes: Vec<String> = match o.get("nodes").and_then(Value::as_array) {
        Some(items)
            if items
                .iter()
                .all(|n| n.as_str().is_some_and(|s| !s.is_empty())) =>
        {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        }
        _ => return fail("\"nodes\" must be an array of strings"),
    };
    if nodes.is_empty() {
        return fail("\"nodes\" must list at least one node kind");
    }
    let binding = string(o, "binding")?;
    if binding.is_empty() {
        return fail("\"binding\" must be a non-empty string");
    }
    let language = string(o, "language")?;
    if language.is_empty() {
        return fail("\"language\" must be a non-empty string");
    }

    // "formatVersions" and "versions" describe the same releases at two
    // grains, so a pair that disagrees is refused rather than half believed.
    // Only the canonical spelling goes on the wire, so equal claims compare
    // equal in reports.
    let format_versions = string(o, "formatVersions")?;
    let table = SupportTable::parse(format_versions).map_err(|why| {
        ProtocolError(format!(
            "\"formatVersions\" {} is not a support table: {why}",
            Value::from(format_versions)
        ))
    })?;
    let canonical = table.canonical();
    if canonical != format_versions {
        return fail(format!(
            "\"formatVersions\" must be canonical: got {}, expected {}",
            Value::from(format_versions),
            Value::from(canonical)
        ));
    }
    // A set, so a long hostile list cannot make these checks quadratic.
    let claimed: std::collections::BTreeSet<u32> = versions.iter().copied().collect();
    for &major in &claimed {
        if !table.touches_major(major) {
            return fail(format!(
                "\"versions\" lists {major} but \"formatVersions\" {} has no release of that major",
                Value::from(format_versions)
            ));
        }
    }
    // The converse: every major an interval holds must be listed. A bounded
    // interval is checked up to its upper bound. One with no upper bound
    // reaches majors that do not exist yet, which no list can enumerate, so it
    // is checked from its lower bound up to the highest listed major, which
    // it must reach without a gap (stricter than the first driver, which
    // skipped such intervals; spec/mck/migration.md departure 13).
    let highest = claimed.last().copied().unwrap_or(0);
    for interval in table.intervals() {
        let floor = interval
            .lower
            .map_or(DOMAIN_FLOOR.major, |l| l.release.major);
        let top = interval
            .upper
            .map_or(highest.max(floor), |u| u.release.major);
        // Stops at the first missing major, so even a wide interval is cheap.
        for major in floor..=top {
            if interval.holds_major(major) && !claimed.contains(&major) {
                return fail(format!(
                    "\"formatVersions\" {} touches major {major} but \"versions\" does not list it",
                    Value::from(format_versions)
                ));
            }
        }
    }
    let allowed_profiles = match contract_version {
        AdapterContract::V1 => Profile::allowed(),
        AdapterContract::V2 => CapabilitiesProfile::allowed(),
    };
    Ok(Capabilities {
        contract_version,
        binding: binding.to_owned(),
        language: language.to_owned(),
        format_versions: format_versions.to_owned(),
        table,
        versions,
        profiles: listed(
            o,
            "profiles",
            |profile| match contract_version {
                AdapterContract::V1 => Profile::parse(profile).map(Into::into),
                AdapterContract::V2 => CapabilitiesProfile::parse(profile),
            },
            &allowed_profiles,
        )?,
        layouts: listed(o, "layouts", Layout::parse, &Layout::allowed())?,
        paths: listed(o, "paths", PathMode::parse, &PathMode::allowed())?,
        nodes,
    })
}

fn parse_diagnostic(value: Option<&Value>) -> Result<Diagnostic, ProtocolError> {
    let Some(d) = value.and_then(Value::as_object) else {
        return fail("\"diagnostic\" must be an object");
    };
    known_keys(d, &["code", "stage", "cursor", "message"], "diagnostic.")?;
    let optional = |key: &str| -> Result<Option<String>, ProtocolError> {
        match d.get(key) {
            None => Ok(None),
            Some(_) => string(d, key).map(|s| Some(s.to_owned())),
        }
    };
    let stage = match d.get("stage") {
        None => None,
        Some(stage) => Some(stage.as_str().and_then(Stage::parse).map_or_else(
            || fail("\"stage\" must be syntax, normalization, or semantic"),
            Ok,
        )?),
    };
    Ok(Diagnostic {
        code: string(d, "code")?.to_owned(),
        stage,
        cursor: optional("cursor")?,
        message: optional("message")?,
    })
}

fn parse_files(value: Option<&Value>, key: &str) -> Result<Vec<TreeFile>, ProtocolError> {
    let Some(items) = value.and_then(Value::as_array) else {
        return fail(format!("\"{key}\" must be an array"));
    };
    items
        .iter()
        .enumerate()
        .map(|(i, item)| {
            let Some(file) = item.as_object() else {
                return fail(format!("\"{key}\" entries must be objects"));
            };
            known_keys(file, &["path", "content"], &format!("{key}[{i}]."))?;
            Ok(TreeFile {
                path: string(file, "path")?.to_owned(),
                content: string(file, "content")?.to_owned(),
            })
        })
        .collect()
}

/// `ok` is `true` or `false`; anything else is malformed.
fn ok_flag(o: &Object) -> Result<bool, ProtocolError> {
    o.get("ok")
        .and_then(Value::as_bool)
        .map_or_else(|| fail("\"ok\" must be true or false"), Ok)
}

pub fn parse_decode_response(value: &Value) -> Result<DecodeResponse, ProtocolError> {
    let o = object(value, "response")?;
    if !ok_flag(o)? {
        known_keys(o, &["ok", "diagnostic"], "")?;
        return Ok(DecodeResponse::Rejected(parse_diagnostic(
            o.get("diagnostic"),
        )?));
    }
    known_keys(o, &["ok", "kind", "canonical", "warnings"], "")?;
    let Some(canonical) = o.get("canonical").and_then(Value::as_object) else {
        return fail("\"canonical\" must be an object");
    };
    let canonical = canonical
        .iter()
        .map(|(key, text)| {
            let Some(profile) = Profile::parse(key) else {
                return fail(format!("\"canonical\" has unknown profile \"{key}\""));
            };
            let Some(text) = text.as_str() else {
                return fail(format!("\"canonical.{key}\" must be a string"));
            };
            Ok((profile, text.to_owned()))
        })
        .collect::<Result<Vec<_>, _>>()?;
    let Some(warnings) = o.get("warnings").and_then(Value::as_array) else {
        return fail("\"warnings\" must be an array");
    };
    let warnings = warnings
        .iter()
        .enumerate()
        .map(|(i, w)| {
            let Some(w) = w.as_object() else {
                return fail("\"warnings\" entries must be objects");
            };
            known_keys(w, &["code", "cursor"], &format!("warnings[{i}]."))?;
            Ok(Warning {
                code: string(w, "code")?.to_owned(),
                cursor: string(w, "cursor")?.to_owned(),
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok(DecodeResponse::Ok {
        kind: string(o, "kind")?.to_owned(),
        canonical,
        warnings,
    })
}

pub fn parse_write_tree_response(value: &Value) -> Result<WriteTreeResponse, ProtocolError> {
    let o = object(value, "response")?;
    if !ok_flag(o)? {
        known_keys(o, &["ok", "diagnostic"], "")?;
        return Ok(WriteTreeResponse::Rejected(parse_diagnostic(
            o.get("diagnostic"),
        )?));
    }
    known_keys(o, &["ok", "files"], "")?;
    Ok(WriteTreeResponse::Ok {
        files: parse_files(o.get("files"), "files")?,
    })
}

/// Parses a request, as an adapter or a replay reads one. The runner never
/// needs this; tests and replay adapters do.
pub fn parse_request(value: &Value) -> Result<Request, ProtocolError> {
    let o = object(value, "request")?;
    let op = string(o, "op")?;
    let version = || -> Result<u32, ProtocolError> {
        o.get("version")
            .and_then(integer)
            .and_then(|v| u32::try_from(v).ok())
            .map_or_else(|| fail("\"version\" must be an integer"), Ok)
    };
    let path = || -> Result<PathMode, ProtocolError> {
        o.get("path")
            .and_then(Value::as_str)
            .and_then(PathMode::parse)
            .map_or_else(|| fail("\"path\" must be current or pinned"), Ok)
    };
    let profile = |value: Option<&Value>, what: &str| -> Result<Profile, ProtocolError> {
        value
            .and_then(Value::as_str)
            .and_then(Profile::parse)
            .map_or_else(|| fail(format!("\"{what}\" must be json or yaml")), Ok)
    };
    let strip = || -> Result<bool, ProtocolError> {
        o.get("strip")
            .and_then(Value::as_bool)
            .map_or_else(|| fail("\"strip\" must be a boolean"), Ok)
    };
    match op {
        "capabilities" => {
            known_keys(o, &["op", "contractVersion"], "")?;
            match o.get("contractVersion") {
                None => Ok(Request::Capabilities),
                Some(version) if integer(version) == Some(2) => Ok(Request::capabilities_v2()),
                _ => fail("\"contractVersion\" must be 2 when present"),
            }
        }
        "exit" => {
            known_keys(o, &["op"], "")?;
            Ok(Request::Exit)
        }
        "decode" => {
            known_keys(
                o,
                &["op", "version", "profile", "path", "strip", "node", "input"],
                "",
            )?;
            Ok(Request::Decode {
                version: version()?,
                profile: profile(o.get("profile"), "profile")?,
                path: path()?,
                strip: strip()?,
                node: string(o, "node")?.to_owned(),
                input: string(o, "input")?.to_owned(),
            })
        }
        "readTree" => {
            known_keys(
                o,
                &["op", "version", "profile", "path", "strip", "node", "files"],
                "",
            )?;
            Ok(Request::ReadTree {
                version: version()?,
                profile: profile(o.get("profile"), "profile")?,
                path: path()?,
                strip: strip()?,
                node: string(o, "node")?.to_owned(),
                files: parse_files(o.get("files"), "files")?,
            })
        }
        "writeTree" => {
            known_keys(o, &["op", "version", "path", "policy", "input"], "")?;
            let Some(policy) = o.get("policy").and_then(Value::as_object) else {
                return fail("\"policy\" must be an object");
            };
            known_keys(policy, &["profile", "pathBudget"], "policy.")?;
            let path_budget = policy
                .get("pathBudget")
                .and_then(integer)
                .filter(|b| *b >= 64)
                .map_or_else(
                    || fail("\"policy.pathBudget\" must be an integer of at least 64"),
                    Ok,
                )?;
            Ok(Request::WriteTree {
                version: version()?,
                path: path()?,
                policy: WritePolicy {
                    profile: profile(policy.get("profile"), "policy.profile")?,
                    path_budget: path_budget as u64,
                },
                input: string(o, "input")?.to_owned(),
            })
        }
        other => fail(format!("unknown op \"{other}\"")),
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    fn caps(overrides: Value) -> Value {
        let mut base = json!({
            "contractVersion": 1,
            "binding": "morphir-rust",
            "language": "rust",
            "formatVersions": "[3.0.0,3.2.0),[4.0.0,4.1.0)",
            "versions": [3, 4],
            "profiles": ["json", "yaml"],
            "layouts": ["single", "tree"],
            "paths": ["current", "pinned"],
            "nodes": ["Type", "Distribution"]
        });
        for (key, value) in overrides.as_object().unwrap() {
            if value.is_null() {
                base.as_object_mut().unwrap().remove(key);
            } else {
                base[key] = value.clone();
            }
        }
        base
    }

    fn refused(value: Value, expected: &str) {
        let error = parse_capabilities(&value).unwrap_err().to_string();
        assert!(error.contains(expected), "{error:?} lacks {expected:?}");
    }

    #[test]
    fn accepts_a_well_formed_capabilities_reply() {
        let parsed = parse_capabilities(&caps(json!({}))).unwrap();
        assert_eq!(parsed.format_versions, "[3.0.0,3.2.0),[4.0.0,4.1.0)");
        assert_eq!(parsed.versions, vec![3, 4]);
        assert_eq!(
            parsed.profiles,
            vec![CapabilitiesProfile::Json, CapabilitiesProfile::Yaml]
        );
        assert_eq!(parsed.nodes, vec!["Type", "Distribution"]);
    }

    #[test]
    fn v2_capabilities_can_advertise_ion_but_v1_cannot() {
        let v2 = caps(json!({"contractVersion": 2, "profiles": ["json", "yaml", "ion"]}));
        let parsed = parse_capabilities(&v2).unwrap();
        assert_eq!(parsed.contract_version, AdapterContract::V2);
        assert!(parsed.profiles.contains(&CapabilitiesProfile::Ion));

        refused(
            caps(json!({"profiles": ["json", "ion"]})),
            "expected one of json, yaml",
        );
        refused(
            caps(json!({"contractVersion": 3})),
            "unsupported contractVersion 3",
        );
    }

    #[test]
    fn refuses_capabilities_that_break_the_contract() {
        refused(caps(json!({ "extra": true })), "unknown field \"extra\"");
        refused(
            caps(json!({ "contractVersion": 3 })),
            "unsupported contractVersion 3",
        );
        refused(
            caps(json!({ "contractVersion": null })),
            "unsupported contractVersion undefined",
        );
        refused(caps(json!({ "nodes": [] })), "at least one node kind");
        refused(caps(json!({ "nodes": [""] })), "array of strings");
        refused(caps(json!({ "binding": "" })), "non-empty string");
        refused(caps(json!({ "versions": [0] })), "positive integers");
        refused(
            caps(json!({ "profiles": ["xml"] })),
            "expected one of json, yaml",
        );
        refused(
            caps(json!({ "formatVersions": "4" })),
            "is not a support table",
        );
        refused(
            caps(json!({ "formatVersions": "[4.0.0, 4.1.0)", "versions": [4] })),
            "must be canonical",
        );
        refused(
            caps(json!({ "formatVersions": "[4.0.0,4.1.0)", "versions": [3, 4] })),
            "lists 3 but",
        );
        refused(
            caps(json!({ "formatVersions": "[3.0.0,4.1.0)", "versions": [3] })),
            "touches major 4",
        );
    }

    #[test]
    fn an_open_upper_bound_must_still_list_the_majors_it_certainly_holds() {
        refused(
            caps(json!({ "formatVersions": "[4.0.0,)", "versions": [5] })),
            "touches major 4",
        );
        refused(
            caps(json!({ "formatVersions": "[4.0.0,)", "versions": [4, 6] })),
            "touches major 5",
        );
        assert!(
            parse_capabilities(&caps(
                json!({ "formatVersions": "[4.0.0,)", "versions": [4, 5] })
            ))
            .is_ok()
        );
    }

    #[test]
    fn a_very_wide_claim_is_checked_in_linear_time() {
        let versions: Vec<u32> = (3..=200_000).collect();
        let started = std::time::Instant::now();
        let parsed = parse_capabilities(&caps(
            json!({ "formatVersions": "[3.0.0,200001.0.0)", "versions": versions }),
        ));
        assert!(parsed.is_ok(), "{parsed:?}");
        assert!(
            started.elapsed() < std::time::Duration::from_secs(2),
            "took {:?}",
            started.elapsed()
        );
    }

    #[test]
    fn an_open_upper_bound_needs_no_future_majors_listed() {
        assert!(
            parse_capabilities(&caps(
                json!({ "formatVersions": "[4.0.0,)", "versions": [4] })
            ))
            .is_ok()
        );
        assert!(
            parse_capabilities(&caps(
                json!({ "formatVersions": "[3.0.0,4.0.0)", "versions": [3] })
            ))
            .is_ok()
        );
    }

    #[test]
    fn envelopes_need_an_object_with_a_positive_integer_id() {
        assert_eq!(
            parse_envelope(r#"{"id":3,"ok":true}"#).unwrap(),
            (3, json!({ "ok": true }).as_object().unwrap().clone())
        );
        assert_eq!(parse_envelope(r#"{"id":2.0}"#).unwrap().0, 2);
        for (line, expected) in [
            ("hello", "not a JSON line: hello"),
            ("[1]", "must be a JSON object"),
            ("{}", "missing id"),
            (r#"{"id":"1"}"#, "missing id"),
            (r#"{"id":1.5}"#, "missing id"),
            (r#"{"id":0}"#, "must be at least 1, got 0"),
        ] {
            assert!(
                parse_envelope(line).unwrap_err().0.contains(expected),
                "{line}"
            );
        }
    }

    #[test]
    fn decode_and_write_responses_are_checked_member_by_member() {
        let ok = json!({ "ok": true, "kind": "Unit", "canonical": { "yaml": "Unit: {}\n" }, "warnings": [{ "code": "legacy_spelling", "cursor": "/attrs" }] });
        let parsed = parse_decode_response(&ok).unwrap();
        assert_eq!(parsed.canonical(Profile::Yaml), Some("Unit: {}\n"));
        let rejected = json!({ "ok": false, "diagnostic": { "code": "duplicate_member", "stage": "normalization" } });
        assert!(
            matches!(parse_decode_response(&rejected).unwrap(), DecodeResponse::Rejected(d) if d.code == "duplicate_member")
        );

        for (value, expected) in [
            (json!({ "ok": "yes" }), "\"ok\" must be true or false"),
            (
                json!({ "ok": true, "kind": "K", "canonical": { "xml": "" }, "warnings": [] }),
                "unknown profile \"xml\"",
            ),
            (
                json!({ "ok": true, "kind": "K", "canonical": {}, "warnings": [{ "code": "c" }] }),
                "\"cursor\" must be a string",
            ),
            (
                json!({ "ok": true, "kind": "K", "canonical": {}, "warnings": [], "x": 1 }),
                "unknown field \"x\"",
            ),
            (
                json!({ "ok": false, "diagnostic": { "code": "c", "stage": "late" } }),
                "\"stage\" must be",
            ),
            (
                json!({ "ok": false, "diagnostic": { "code": "c", "why": "?" } }),
                "unknown field \"diagnostic.why\"",
            ),
        ] {
            assert!(
                parse_decode_response(&value)
                    .unwrap_err()
                    .0
                    .contains(expected),
                "{value}"
            );
        }
        let files = json!({ "ok": true, "files": [{ "path": "manifest", "content": "a" }] });
        assert!(
            matches!(parse_write_tree_response(&files).unwrap(), WriteTreeResponse::Ok { files } if files.len() == 1)
        );
        let extra = json!({ "ok": true, "files": [{ "path": "m", "content": "a", "mode": 1 }] });
        assert!(
            parse_write_tree_response(&extra)
                .unwrap_err()
                .0
                .contains("unknown field \"files[0].mode\"")
        );
    }

    #[test]
    fn requests_are_written_in_the_first_drivers_member_order() {
        assert_eq!(
            Request::Capabilities.line(1),
            r#"{"id":1,"op":"capabilities"}"#
        );
        assert_eq!(Request::Exit.line(706), r#"{"id":706,"op":"exit"}"#);
        let decode = Request::Decode {
            version: 4,
            profile: Profile::Yaml,
            path: PathMode::Current,
            strip: true,
            node: "Type".into(),
            input: "Unit: {}\n".into(),
        };
        assert_eq!(
            decode.line(2),
            r#"{"id":2,"op":"decode","version":4,"profile":"yaml","path":"current","strip":true,"node":"Type","input":"Unit: {}\n"}"#
        );
        let write = Request::WriteTree {
            version: 4,
            path: PathMode::Pinned,
            policy: WritePolicy {
                profile: Profile::Json,
                path_budget: 4000,
            },
            input: "{}".into(),
        };
        assert_eq!(
            write.line(9),
            r#"{"id":9,"op":"writeTree","version":4,"path":"pinned","policy":{"profile":"json","pathBudget":4000},"input":"{}"}"#
        );
        let (id, body) = parse_envelope(&write.line(9)).unwrap();
        assert_eq!(id, 9);
        assert_eq!(parse_request(&Value::Object(body)).unwrap(), write);
    }

    #[test]
    fn v2_capabilities_request_names_its_contract_version() {
        assert_eq!(
            Request::capabilities_v2().line(1),
            r#"{"id":1,"op":"capabilities","contractVersion":2}"#
        );
        let (id, body) = parse_envelope(&Request::capabilities_v2().line(1)).unwrap();
        assert_eq!(id, 1);
        assert_eq!(
            parse_request(&Value::Object(body)).unwrap(),
            Request::capabilities_v2()
        );
    }

    #[test]
    fn schema_accepts_v2_ion_capabilities_and_rejects_v1_ion() {
        let schema: Value =
            serde_json::from_str(include_str!("../../../../spec/ir/mck/protocol.schema.json"))
                .unwrap();
        let validator = jsonschema::options().build(&schema).unwrap();

        let mut v2 = caps(json!({"contractVersion": 2, "profiles": ["ion"]}));
        v2["id"] = json!(1);
        assert!(validator.is_valid(&v2));
        assert!(validator.is_valid(&json!({"id": 1, "op": "capabilities", "contractVersion": 2})));

        let mut v1 = v2;
        v1["contractVersion"] = json!(1);
        assert!(!validator.is_valid(&v1));
        assert!(!validator.is_valid(&json!({"id": 1, "op": "capabilities", "contractVersion": 1})));
    }
}

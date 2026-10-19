//! Independent artifact evidence validation. This module does not link the host,
//! generator, UI decoder or transfer owner. Raw replies remain literal strings
//! until strict duplicate-aware parsing here; expected byte hashes are authored.
use super::contract::{OfflineOnly, encoded_size};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::OnceLock,
};
use unicode_casefold::UnicodeCaseFold;
use unicode_normalization::UnicodeNormalization;

pub(super) const MAX_INPUT_BYTES: usize = 1024 * 1024;
const MAX_REPLY_BYTES: usize = 131072;
const MAX_CASE_EXPANSION: usize = 128 * 1024 * 1024;
pub(super) const MAX_CORPUS_EXPANSION: usize = 512 * 1024 * 1024;
const MAX_READS: usize = 4096;
const VERSION: &str = "0.1.0-draft.1";
const PROFILE: &str = "morphir/workbench/artifacts";

pub(super) fn validate_corpus_shape(value: &Value) -> Result<(), String> {
    check("mck-corpus", value)
}
pub(super) fn validate_report_shape(value: &Value) -> Result<(), String> {
    check("mck-report", value)
}
pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    check("mck-observation", value)
}

/// Bound recipe expansion and read work before any adapter starts. Invalid SDK
/// payloads remain deliberate fixture inputs; they are never decoded here.
pub(super) fn validate_input(value: &Value) -> Result<usize, String> {
    encoded_size(value, MAX_INPUT_BYTES)?;
    check("mck-input", value)?;
    let mut expansion = 0usize;
    let mut fixture_bytes = 0usize;
    let mut connections = BTreeSet::new();
    let mut all_reads = 0usize;
    for artifact in value["fixture"]["artifacts"]
        .as_array()
        .expect("schema artifacts")
    {
        let content = &artifact["content"];
        let size = match content["representation"]
            .as_str()
            .expect("schema representation")
        {
            "binary-recipe" => {
                let recipe = &content["recipe"];
                if recipe["kind"] == "hex" {
                    recipe["hex"].as_str().expect("schema hex").len() / 2
                } else {
                    integer(&recipe["length"], 16777217)?
                }
            }
            "utf8-text" => content["content"].as_str().expect("schema text").len(),
            "literal-binary" => {
                content["content"]
                    .as_str()
                    .expect("schema text")
                    .len()
                    .div_ceil(4)
                    * 3
            }
            _ => unreachable!("schema representation"),
        };
        fixture_bytes = fixture_bytes
            .checked_add(size)
            .ok_or("artifact fixture budget overflow")?;
    }
    if fixture_bytes > 67108865 {
        return Err("artifact fixture exceeds decoded recipe budget".into());
    }
    for action in value["actions"].as_array().expect("schema actions") {
        match action["action"].as_str().expect("schema action") {
            "connect" => {
                if !connections.insert(action["connection"].as_str().expect("schema alias"))
                    || connections.len() > 65
                {
                    return Err("artifact fixture duplicate/excess connection".into());
                }
            }
            // Opaque raw text may invoke generation too. Charge conservatively
            // without interpreting hostile bytes or predicting host refusal.
            "generate" | "start-generate" | "raw" => {
                expansion = expansion
                    .checked_add(fixture_bytes)
                    .ok_or("artifact expansion overflow")?;
            }
            "raw-sized" | "generate-sized" => {
                let size = integer(&action["size"], 1048577)?;
                if action["prefix"].as_str().expect("schema prefix").len() > size {
                    return Err("artifact frame prefix exceeds expanded size".into());
                }
                expansion = expansion
                    .checked_add(size)
                    .and_then(|value| value.checked_add(fixture_bytes))
                    .ok_or("artifact frame expansion overflow")?;
            }
            "read-all" => {
                let index = integer(&action["artifactIndex"], 255)?;
                let artifact = value["fixture"]["artifacts"]
                    .get(index)
                    .ok_or("read-all fixture artifact absent")?;
                let content = &artifact["content"];
                let size = match content["representation"].as_str().expect("schema content") {
                    "binary-recipe" if content["recipe"]["kind"] == "hex" => {
                        content["recipe"]["hex"].as_str().expect("schema hex").len() / 2
                    }
                    "binary-recipe" => integer(&content["recipe"]["length"], 16777217)?,
                    "utf8-text" => content["content"].as_str().expect("schema text").len(),
                    _ => return Err("read-all needs a known valid byte recipe".into()),
                };
                all_reads = all_reads
                    .checked_add(size.div_ceil(integer(&action["maxBytes"], 65536)?))
                    .ok_or("artifact reads overflow")?;
            }
            "read" => {
                all_reads += 1;
            }
            _ => {}
        }
    }
    if expansion > MAX_CASE_EXPANSION || all_reads > MAX_READS {
        return Err("artifact fixture exceeds work budget".into());
    }
    Ok(expansion)
}

pub(super) fn identity(value: &Value) -> Result<&str, String> {
    let text = value.as_str().ok_or("artifact identity must be a string")?;
    if text.is_empty() || text.len() > 128 || text.chars().any(char::is_control) {
        return Err("artifact identity exceeds portable bounds".into());
    }
    Ok(text)
}
pub(super) fn producer_version(value: &Value) -> Result<(), String> {
    let text = value
        .as_str()
        .ok_or("artifact producer version must be a string")?;
    let parsed = semver::Version::parse(text).map_err(|e| e.to_string())?;
    if parsed.to_string() != text
        || [parsed.major, parsed.minor, parsed.patch]
            .into_iter()
            .any(|v| v > 9007199254740991)
    {
        return Err("artifact producer version is not portable canonical SemVer".into());
    }
    Ok(())
}

pub(super) fn portable_paths(items: &[Value]) -> Result<(), String> {
    let key = |path: &str| path.nfkc().case_fold().nfc().collect::<String>();
    let mut files = BTreeSet::new();
    let mut directories = BTreeMap::new();
    for item in items {
        let path = item["path"].as_str().ok_or("artifact path is not text")?;
        if path.is_empty()
            || path.len() > 4096
            || path.encode_utf16().count() > 1024
            || path.chars().any(char::is_control)
        {
            return Err("artifact path exceeds portable bounds".into());
        }
        for part in path.split('/') {
            let stem = part
                .split('.')
                .next()
                .unwrap_or_default()
                .trim_end_matches(' ')
                .to_ascii_uppercase();
            let device_number = |s: &str| {
                matches!(
                    s,
                    "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
                )
            };
            let reserved = matches!(
                stem.as_str(),
                "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
            ) || stem.strip_prefix("COM").is_some_and(device_number)
                || stem.strip_prefix("LPT").is_some_and(device_number);
            if part.is_empty()
                || part.len() > 255
                || part.encode_utf16().count() > 255
                || matches!(part, "." | "..")
                || part.ends_with(['.', ' '])
                || part.contains(['<', '>', ':', '"', '\\', '|', '?', '*'])
                || reserved
            {
                return Err("artifact path component is not portable".into());
            }
        }
        let file = key(path);
        if !files.insert(file) {
            return Err("artifact portable paths collide".into());
        }
        for (separator, _) in path.match_indices('/') {
            let directory = &path[..separator];
            if let Some(previous) = directories.insert(key(directory), directory.to_owned())
                && previous != directory
            {
                return Err("artifact directory aliases collide".into());
            }
        }
    }
    if directories
        .keys()
        .any(|directory| files.contains(directory))
    {
        return Err("artifact file/directory prefix conflict".into());
    }
    Ok(())
}
/// Exact decimal integrality, independent of a floating-point conversion.
pub(super) fn integer(value: &Value, bound: usize) -> Result<usize, String> {
    usize::try_from(integer_u64(value, bound as u64)?)
        .map_err(|_| "artifact count exceeds bounds".into())
}
pub(super) fn integer_u64(value: &Value, bound: u64) -> Result<u64, String> {
    let token = value
        .as_number()
        .ok_or("artifact count must be numeric")?
        .to_string();
    let magnitude = token.strip_prefix('-').unwrap_or(&token);
    let (mantissa, exponent) = magnitude.split_once(['e', 'E']).unwrap_or((magnitude, "0"));
    let fraction = mantissa.split_once('.').map_or(0, |(_, f)| f.len());
    let digits = mantissa.replace('.', "");
    let significant = digits.trim_start_matches('0');
    if significant.is_empty() {
        return Ok(0);
    }
    if token.starts_with('-') {
        return Err("negative artifact count".into());
    }
    let core = significant.trim_end_matches('0');
    let scale = exponent
        .parse::<i64>()
        .ok()
        .and_then(|e| e.checked_sub(fraction as i64))
        .and_then(|e| e.checked_add((significant.len() - core.len()) as i64))
        .ok_or("artifact count exponent exceeds bounds")?;
    if !(0..=20).contains(&scale) || core.len() > 20 - scale as usize {
        return Err("artifact count is fractional or out of range".into());
    }
    let mut result = core.parse::<u64>().map_err(|e| e.to_string())?;
    for _ in 0..scale {
        result = result.checked_mul(10).ok_or("artifact count overflow")?;
    }
    if result <= bound {
        Ok(result)
    } else {
        Err("artifact count exceeds bounds".into())
    }
}

#[cfg(test)]
mod integer_tests {
    use super::*;

    #[test]
    fn extreme_exponents_refuse_without_signed_arithmetic_overflow() {
        for token in [
            "1e9223372036854775807",
            "11e9223372036854775807",
            "1e9223372036854775808",
            "1e-9223372036854775808",
        ] {
            let value: Value = serde_json::from_str(token).unwrap();
            assert!(integer_u64(&value, u64::MAX).is_err(), "{token}");
            assert!(integer(&value, usize::MAX).is_err(), "{token}");
        }
    }

    #[test]
    fn exact_u64_bounds_remain_independent_of_the_target_pointer_width() {
        let maximum: Value = serde_json::from_str("18446744073709551615.0").unwrap();
        assert_eq!(integer_u64(&maximum, u64::MAX).unwrap(), u64::MAX);
        assert!(integer_u64(&maximum, u64::MAX - 1).is_err());
        let over: Value = serde_json::from_str("18446744073709551616").unwrap();
        assert!(integer_u64(&over, u64::MAX).is_err());
    }
}
pub(super) fn signed_rpc_code(value: &Value) -> Result<i32, String> {
    let token = value
        .as_number()
        .ok_or("artifact RPC error code is not numeric")?
        .to_string();
    let negative = token.starts_with('-');
    let magnitude = token
        .strip_prefix('-')
        .unwrap_or(&token)
        .parse::<serde_json::Number>()
        .map_err(|e| e.to_string())?;
    let magnitude = integer(
        &Value::Number(magnitude),
        if negative { 2147483648 } else { 2147483647 },
    )? as i64;
    i32::try_from(if negative { -magnitude } else { magnitude }).map_err(|e| e.to_string())
}
fn rpc(raw: &str, request_id: Option<&str>) -> Result<Value, String> {
    if raw.len() > MAX_REPLY_BYTES {
        return Err("artifact raw reply exceeds 128KiB".into());
    }
    let mut value = crate::json::strict::parse_exact(raw)?;
    let fields = value
        .as_object()
        .ok_or("artifact reply must be an object")?;
    if fields.len() != 3
        || value["jsonrpc"] != "2.0"
        || !fields.contains_key("id")
        || !(fields.contains_key("result") ^ fields.contains_key("error"))
    {
        return Err("artifact reply envelope is not closed JSONRPC2".into());
    }
    let id = if value["id"].is_null() && request_id.is_none() && value.get("error").is_some() {
        None
    } else {
        Some(
            value["id"]
                .as_u64()
                .ok_or("artifact reply ID requires exact u64 syntax")?,
        )
    };
    if let Some(expected) = request_id
        && expected.parse::<u64>().ok() != id
    {
        return Err("artifact reply does not match captured request ID".into());
    }
    if let Some(error) = value.get("error") {
        let fields = error
            .as_object()
            .ok_or("artifact RPC error must be an object")?;
        if !(fields.len() == 2 || (fields.len() == 3 && fields.contains_key("data")))
            || !fields.contains_key("code")
            || !fields.contains_key("message")
            || !error["message"].is_string()
        {
            return Err("artifact RPC error is not closed".into());
        }
        let code = signed_rpc_code(&error["code"])?;
        if let Some(data) = error.get("data") {
            let data_fields = data
                .as_object()
                .ok_or("artifact RPC error data must be an object")?;
            if data_fields.len() != 3
                || data["profile"] != PROFILE
                || data["contractVersion"] != VERSION
                || !data["code"].as_str().is_some_and(|code| {
                    matches!(
                        code,
                        "artifacts.invalid_request"
                            | "artifacts.invalid_identity"
                            | "artifacts.invalid_range"
                            | "artifacts.invalid_path"
                            | "artifacts.invalid_path_set"
                            | "artifacts.invalid_content"
                            | "artifacts.file_count"
                            | "artifacts.file_size"
                            | "artifacts.set_size"
                            | "artifacts.reply_limit"
                            | "artifacts.capacity"
                            | "artifacts.active_generation"
                            | "artifacts.unknown_handle"
                            | "artifacts.unavailable"
                            | "artifacts.generation_failed"
                    )
                })
            {
                return Err("artifact RPC error data differs from exact profile".into());
            }
        }
        value["error"]["code"] = json!(code);
    }
    if let Some(result) = value.get("result") {
        encoded_size(
            &json!({"jsonrpc":"2.0","id":u64::MAX,"result":result}),
            MAX_REPLY_BYTES,
        )?;
    }
    Ok(value)
}
struct CapturedGeneration {
    connection: String,
    alias: String,
    live: bool,
    manifest: Value,
}
struct Connection {
    initialized: bool,
    open: bool,
}

pub(super) fn projection(value: &Value) -> Result<Value, String> {
    encoded_size(value, MAX_INPUT_BYTES)?;
    check("mck-projection", value)?;
    let session = identity(&value["sessionId"])?;
    let provider = identity(&value["providerId"])?;
    let mut connections = BTreeMap::<String, Connection>::new();
    let mut generations = BTreeMap::<String, CapturedGeneration>::new();
    let mut captures = BTreeSet::new();
    let mut output = value.clone();
    output["sessionId"] = json!("$session");
    let mut raw_budget = 524288usize;
    let mut reads = 0usize;
    for event in output["events"].as_array_mut().expect("schema events") {
        let kind = event["event"].as_str().expect("schema event").to_owned();
        let connection = event
            .get("connection")
            .and_then(Value::as_str)
            .map(str::to_owned);
        if let Some(connection) = connection.as_deref()
            && kind != "connected"
        {
            let state = connections
                .get(connection)
                .ok_or("artifact event precedes accepted connection")?;
            if !state.open {
                return Err("artifact event follows connection close".into());
            }
            if matches!(kind.as_str(), "transferred" | "started") && !state.initialized {
                return Err("artifact success evidence precedes initialization".into());
            }
        }
        match kind.as_str() {
            "connected" => {
                let key = connection.expect("schema connection");
                if connections.contains_key(&key) {
                    return Err("artifact connection identity reused".into());
                }
                if event["status"] == "accepted" {
                    connections.insert(
                        key,
                        Connection {
                            initialized: false,
                            open: true,
                        },
                    );
                }
            }
            "initialized" => {
                if event["status"] == "initialized" {
                    connections
                        .get_mut(connection.as_deref().expect("schema connection"))
                        .expect("checked connection")
                        .initialized = true;
                }
            }
            "generated" => {
                let raw = event["reply"].as_str().expect("schema raw reply");
                raw_budget = raw_budget
                    .checked_sub(raw.len())
                    .ok_or("artifact captured replies exceed budget")?;
                let mut reply = rpc(raw, event["requestId"].as_str())?;
                if let Some(result) = reply.get_mut("result") {
                    check("generate-result", result)?;
                    if result["status"] == "ready" {
                        if !connections[connection.as_deref().expect("schema connection")]
                            .initialized
                        {
                            return Err("artifact Ready precedes initialization".into());
                        }
                        if identity(&result["sessionId"])? != session
                            || identity(&result["providerId"])? != provider
                        {
                            return Err("artifact manifest captured authority differs".into());
                        }
                        identity(&result["producer"]["id"])?;
                        producer_version(&result["producer"]["version"])?;
                        identity(&result["target"])?;
                        identity(&result["irVersion"])?;
                        let id = identity(&result["generationId"])?.to_owned();
                        let connection = connection.as_ref().expect("schema connection");
                        let alias = identity(&event["generation"])?.to_owned();
                        if generations.contains_key(&id)
                            || !captures.insert((connection.clone(), alias.clone()))
                            || generations
                                .values()
                                .any(|g| g.connection == *connection && g.live)
                        {
                            return Err("artifact generation handle or active owner reused".into());
                        }
                        let mut total = 0usize;
                        let mut ids = BTreeSet::new();
                        portable_paths(result["artifacts"].as_array().expect("schema artifacts"))?;
                        for item in result["artifacts"].as_array().expect("schema artifacts") {
                            if !ids.insert(identity(&item["id"])?) {
                                return Err("artifact IDs duplicate in manifest".into());
                            }
                            total = total
                                .checked_add(integer(&item["byteLength"], 16777216)?)
                                .ok_or("artifact aggregate overflow")?;
                        }
                        if total > 67108864 {
                            return Err("artifact manifest aggregate exceeds64MiB".into());
                        }
                        generations.insert(
                            id,
                            CapturedGeneration {
                                connection: connection.clone(),
                                alias: alias.clone(),
                                live: true,
                                manifest: result.clone(),
                            },
                        );
                        result["sessionId"] = json!("$session");
                        result["generationId"] = json!(format!("{connection}:{alias}"));
                        for (index, item) in result["artifacts"]
                            .as_array_mut()
                            .expect("schema artifacts")
                            .iter_mut()
                            .enumerate()
                        {
                            item["id"] = json!(format!("{connection}:{alias}:{index}"));
                        }
                    }
                }
                event["reply"] = reply;
            }
            "read" => {
                let raw = event["reply"].as_str().expect("schema raw reply");
                raw_budget = raw_budget
                    .checked_sub(raw.len())
                    .ok_or("artifact captured replies exceed budget")?;
                let mut reply = rpc(raw, event["requestId"].as_str())?;
                if let Some(result) = reply.get_mut("result") {
                    if !connections[connection.as_deref().expect("schema connection")].initialized {
                        return Err("artifact read success precedes initialization".into());
                    }
                    check("read-result", result)?;
                    let generation = generations
                        .get(identity(&result["generationId"])?)
                        .ok_or("artifact read references unknown generation")?;
                    if !generation.live
                        || Some(generation.connection.as_str()) != connection.as_deref()
                    {
                        return Err("artifact read escaped live connection ownership".into());
                    }
                    let (index, descriptor) = generation.manifest["artifacts"]
                        .as_array()
                        .expect("schema artifacts")
                        .iter()
                        .enumerate()
                        .find(|(_, d)| d["id"] == result["artifactId"])
                        .ok_or("artifact read references unknown artifact")?;
                    let encoded = result["content"].as_str().expect("schema base64");
                    let bytes = STANDARD.decode(encoded).map_err(|e| e.to_string())?;
                    if bytes.len() > 65536 || STANDARD.encode(&bytes) != encoded {
                        return Err("artifact chunk is not canonical bounded base64".into());
                    }
                    let offset = integer(&result["offset"], 16777216)?;
                    let next = integer(&result["nextOffset"], 16777216)?;
                    if offset.checked_add(bytes.len()) != Some(next)
                        || next > integer(&descriptor["byteLength"], 16777216)?
                    {
                        return Err("artifact chunk progress exceeds declared file".into());
                    }
                    result["generationId"] =
                        json!(format!("{}:{}", generation.connection, generation.alias));
                    result["artifactId"] = json!(format!(
                        "{}:{}:{index}",
                        generation.connection, generation.alias
                    ));
                    result
                        .as_object_mut()
                        .expect("schema result")
                        .remove("content");
                    result["byteLength"] = json!(bytes.len());
                    result["sha256"] = json!(crate::kit::hash::sha256_hex(&bytes));
                }
                reads += 1;
                event["reply"] = reply;
            }
            "transferred" => {
                let connection = connection.as_deref().expect("schema connection");
                let generation = generations
                    .values()
                    .find(|g| {
                        g.connection == connection
                            && g.alias == event["generation"].as_str().expect("schema alias")
                            && g.live
                    })
                    .ok_or("artifact transfer references unknown live capture")?;
                let index = integer(&event["artifactIndex"], 255)?;
                let descriptor = generation.manifest["artifacts"]
                    .get(index)
                    .ok_or("artifact transfer index outside inventory")?;
                let length = integer(&event["byteLength"], 16777216)?;
                if event["sha256"] != descriptor["sha256"]
                    || length != integer(&descriptor["byteLength"], 16777216)?
                {
                    return Err("artifact assembled bytes differ from manifest".into());
                }
                let max = integer(&event["maxBytes"], 65536)?;
                let mut next = 0usize;
                for chunk in event["chunks"].as_array_mut().expect("schema chunks") {
                    reads += 1;
                    if chunk["generationId"] != generation.manifest["generationId"]
                        || chunk["artifactId"] != descriptor["id"]
                    {
                        return Err("artifact chunk summary escaped captured identity".into());
                    }
                    let size = integer(&chunk["byteLength"], 65536)?;
                    if integer(&chunk["offset"], 16777216)? != next
                        || size != max.min(length - next)
                        || size == 0
                    {
                        return Err(
                            "artifact chunk summary has a gap, duplicate or wrong size".into()
                        );
                    }
                    next = next
                        .checked_add(size)
                        .ok_or("artifact chunk summary overflow")?;
                    if integer(&chunk["nextOffset"], 16777216)? != next {
                        return Err("artifact chunk summary nextOffset differs".into());
                    }
                    chunk["generationId"] = json!(format!("{connection}:{}", generation.alias));
                    chunk["artifactId"] =
                        json!(format!("{connection}:{}:{index}", generation.alias));
                }
                if next != length {
                    return Err("artifact transfer is incomplete".into());
                }
            }
            "released" => {
                let raw = event["reply"].as_str().expect("schema reply");
                let reply = rpc(raw, event["requestId"].as_str())?;
                if let Some(result) = reply.get("result") {
                    if !connections[connection.as_deref().expect("schema connection")].initialized {
                        return Err("artifact release success precedes initialization".into());
                    }
                    if result != &json!({}) {
                        return Err("artifact release result is not empty".into());
                    }
                    let generation = generations
                        .values_mut()
                        .find(|g| {
                            Some(g.connection.as_str()) == connection.as_deref()
                                && g.alias == event["generation"].as_str().expect("schema alias")
                        })
                        .ok_or("artifact release lacks captured owner")?;
                    generation.live = false;
                }
                event["reply"] = reply;
            }
            "closed" | "connection-ended" => {
                let connection = connection.as_deref().expect("schema connection");
                connections
                    .get_mut(connection)
                    .expect("checked connection")
                    .open = false;
                for generation in generations
                    .values_mut()
                    .filter(|g| g.connection == connection)
                {
                    generation.live = false;
                }
            }
            "raw" => {
                event["reply"] = rpc(event["reply"].as_str().expect("schema reply"), None)?;
            }
            "usage" | "producer" | "started" => {}
            _ => unreachable!("schema event"),
        }
        if reads > MAX_READS {
            return Err("artifact observation exceeds read work budget".into());
        }
    }
    Ok(output)
}

fn check(name: &str, value: &Value) -> Result<(), String> {
    static VALIDATORS: OnceLock<BTreeMap<&str, jsonschema::Validator>> = OnceLock::new();
    let validators=VALIDATORS.get_or_init(||{
        let texts=[
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-input.schema.json"),
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-projection.schema.json"),
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-observation.schema.json"),
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-capabilities.schema.json"),
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-corpus.schema.json"),
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-report.schema.json"),
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-client-input.schema.json"),
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-client-projection.schema.json"),
            include_str!("../../../../spec/workbench/draft.28/schemas/mck-client-observation.schema.json"),
            include_str!("../../../../spec/workbench/artifacts/0.1.0-draft.1/schemas/generate-result.schema.json"),
            include_str!("../../../../spec/workbench/artifacts/0.1.0-draft.1/schemas/read-result.schema.json"),
        ];
        let resources=texts.map(|text|serde_json::from_str::<Value>(text).expect("artifact schema"));
        resources.iter().map(|schema|{
            let id=schema["$id"].as_str().expect("artifact schemaID");
            let name=match id.rsplit('/').next().expect("schema filename") {
                "mck-input.schema.json"=>"mck-input","mck-projection.schema.json"=>"mck-projection","mck-observation.schema.json"=>"mck-observation","mck-capabilities.schema.json"=>"mck-capabilities","mck-corpus.schema.json"=>"mck-corpus","mck-report.schema.json"=>"mck-report","mck-client-input.schema.json"=>"mck-client-input","mck-client-projection.schema.json"=>"mck-client-projection","mck-client-observation.schema.json"=>"mck-client-observation","generate-result.schema.json"=>"generate-result","read-result.schema.json"=>"read-result",_=>unreachable!("fixed schema")};
            let mut options=jsonschema::options();options.with_retriever(OfflineOnly);
            for resource in &resources {options.with_resource(resource["$id"].as_str().expect("schemaID"),jsonschema::Resource::from_contents(resource.clone()).expect("resource"));}
            (name,options.build(schema).expect("artifact validator"))
        }).collect()
    });
    validators[name]
        .validate(value)
        .map_err(|e| format!("invalid artifact evidence at {}: {e}", e.instance_path))
}

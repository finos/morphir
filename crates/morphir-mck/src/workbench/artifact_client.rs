//! Independent bounded client-scenario vocabulary. This module does not link
//! the Workbench decoder, transfer controller, verified owner, or ZIP writer.
use serde_json::Value;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::OnceLock,
};

const MAX_CASE_WORK: usize = 128 * 1024 * 1024;
pub(super) const MAX_CORPUS_WORK: usize = 512 * 1024 * 1024;
const MAX_DERIVED_BYTES: usize = 8 * 1024 * 1024;

/// Saved evidence has its unchanged 1 MiB bound. Parsed comparison values may
/// expand lossless frames and have a separate finite bound. Reserve complete
/// frame bytes before expansion, then check the exact derived serialization.
struct DerivedProjectionBudget {
    remaining: usize,
}
impl DerivedProjectionBudget {
    fn new(evidence_bytes: usize) -> Result<Self, String> {
        Ok(Self {
            remaining: MAX_DERIVED_BYTES
                .checked_sub(evidence_bytes)
                .ok_or("derived client evidence exceeds budget")?,
        })
    }
    fn reserve_frame(&mut self, bytes: usize) -> Result<(), String> {
        self.remaining = self
            .remaining
            .checked_sub(bytes)
            .ok_or("derived client frame expansion exceeds budget")?;
        Ok(())
    }
}

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct AttemptAlias(String);
impl AttemptAlias {
    fn parse(value: &Value) -> Result<Self, String> {
        let text = value.as_str().ok_or("client attempt alias must be text")?;
        if text.is_empty()
            || text.len() > 64
            || !text.as_bytes()[0].is_ascii_alphabetic()
            || !text
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-'))
        {
            return Err("invalid client attempt alias".into());
        }
        Ok(Self(text.into()))
    }
}
#[derive(Clone, Copy, Debug, Default)]
struct WorkUnits(usize);
impl WorkUnits {
    fn charge(&mut self, amount: usize) -> Result<(), String> {
        let total = self
            .0
            .checked_add(amount)
            .ok_or("client scenario work overflow")?;
        if total > MAX_CASE_WORK {
            return Err("client scenario exceeds pre-allocation work budget".into());
        }
        self.0 = total;
        Ok(())
    }
}
#[derive(Debug, Default)]
pub(super) struct ClientInputBudget {
    decoded_and_reads: WorkUnits,
    raw_frames: WorkUnits,
    observations: WorkUnits,
}
impl ClientInputBudget {
    pub(super) fn work(&self) -> [usize; 3] {
        [
            self.decoded_and_reads.0,
            self.raw_frames.0,
            self.observations.0,
        ]
    }
}
fn check_schema(name: &str, value: &Value) -> Result<(), String> {
    static VALIDATORS: OnceLock<BTreeMap<String, jsonschema::Validator>> = OnceLock::new();
    let validators = VALIDATORS.get_or_init(|| {
        let texts = [
            include_str!(
                "../../../../spec/workbench/draft.28/schemas/mck-client-input.schema.json"
            ),
            include_str!(
                "../../../../spec/workbench/draft.28/schemas/mck-client-projection.schema.json"
            ),
            include_str!(
                "../../../../spec/workbench/draft.28/schemas/mck-client-observation.schema.json"
            ),
        ];
        let resources =
            texts.map(|text| serde_json::from_str::<Value>(text).expect("client schema"));
        resources
            .iter()
            .map(|schema| {
                let id = schema["$id"].as_str().expect("client schema ID");
                let name = id.rsplit('/').next().expect("schema filename");
                let mut options = jsonschema::options();
                options.with_retriever(super::contract::OfflineOnly);
                for resource in &resources {
                    options.with_resource(
                        resource["$id"].as_str().expect("schema ID"),
                        jsonschema::Resource::from_contents(resource.clone())
                            .expect("client resource"),
                    );
                }
                (
                    name.to_owned(),
                    options.build(schema).expect("client validator"),
                )
            })
            .collect()
    });
    validators[name].validate(value).map_err(|error| {
        format!(
            "invalid client evidence at {}: {error}",
            error.instance_path
        )
    })
}
pub(super) fn validate_observation_shape(value: &Value) -> Result<(), String> {
    check_schema("mck-client-observation.schema.json", value)
}
fn recipe_bytes(value: &Value) -> Result<usize, String> {
    match value["kind"].as_str().expect("schema byte recipe") {
        "hex" => Ok(value["hex"].as_str().expect("schema hex").len() / 2),
        "cycle-u8" | "chunk-indexed-u8" | "repeat-u8" => {
            if let Some(seed) = value.get("seed") {
                super::artifacts::integer(seed, 255)?;
            }
            if let Some(byte) = value.get("byte") {
                super::artifacts::integer(byte, 255)?;
            }
            super::artifacts::integer(&value["length"], 16_777_217)
        }
        _ => unreachable!("closed recipe schema"),
    }
}
fn local_value_work(attempt: &Value) -> Result<(usize, usize), String> {
    let mut decoded = 0usize;
    let mut escaped = 0usize;
    for recipe in attempt
        .get("localValues")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let count = super::artifacts::integer(&recipe["count"], 1_048_577)?;
        let byte = super::artifacts::integer(&recipe["byte"], 127)?;
        let width = match byte {
            8 | 9 | 10 | 12 | 13 | 34 | 92 => 2,
            0..=31 => 6,
            _ => 1,
        };
        decoded = decoded
            .checked_add(count)
            .ok_or("local caller-value work overflow")?;
        escaped = escaped
            .checked_add(
                count
                    .checked_mul(width)
                    .ok_or("local JSON escaping overflow")?,
            )
            .ok_or("local JSON escaping work overflow")?;
        if decoded > 1_048_577 {
            return Err("local caller-value recipes exceed aggregate bound".into());
        }
    }
    Ok((decoded, escaped))
}
fn existing_slot<'a>(
    caller: &'a mut Value,
    field: &str,
    path: &[Value],
) -> Result<&'a mut Value, String> {
    let mut slot = caller.get_mut(field).ok_or("unknown local input field")?;
    for step in path {
        slot = if step["kind"] == "member" {
            slot.as_object_mut()
                .and_then(|object| object.get_mut(step["key"].as_str().expect("schema member")))
        } else {
            let index = super::artifacts::integer(&step["index"], 2_147_483_647)?;
            slot.as_array_mut().and_then(|array| array.get_mut(index))
        }
        .ok_or("local input path does not exist")?;
    }
    Ok(slot)
}
/// Validate structural effects only. Scalar replacements need no repeated
/// strings or malformed Unicode allocation, and a renamed malformed key is
/// unreachable by every well-formed authored path after its original is removed.
fn validate_local_paths(input: &Value) -> Result<(), String> {
    let definitions = input["attempts"]
        .as_array()
        .expect("schema attempts")
        .iter()
        .map(|attempt| (attempt["id"].as_str().expect("schema alias"), attempt))
        .collect::<BTreeMap<_, _>>();
    let mut callers = definitions
        .iter()
        .map(|(id, attempt)| (*id, attempt["input"].clone()))
        .collect::<BTreeMap<_, _>>();
    for action in input["actions"].as_array().expect("schema actions") {
        let Some(id) = action.get("attempt").and_then(Value::as_str) else {
            continue;
        };
        if action["action"] == "replace-caller" {
            callers.get_mut(id).expect("validated reference")
                [action["field"].as_str().expect("schema field")] = action["value"].clone();
        } else if action["action"] == "start" {
            let mut shape = callers[id].clone();
            let definition = definitions[id];
            for value in definition
                .get("localValues")
                .and_then(Value::as_array)
                .into_iter()
                .flatten()
            {
                *existing_slot(
                    &mut shape,
                    value["field"].as_str().expect("schema field"),
                    value["path"].as_array().expect("schema path"),
                )? = Value::Null;
            }
            for fault in definition["localFaults"].as_array().expect("schema faults") {
                let field = fault["field"].as_str().expect("schema field");
                let path = fault["path"].as_array().expect("schema path");
                if fault["kind"] == "unpaired-surrogate-key" {
                    let (last, parent) = path
                        .split_last()
                        .ok_or("key fault requires a final object member")?;
                    let key = last
                        .get("key")
                        .and_then(Value::as_str)
                        .ok_or("key fault requires a final object member")?;
                    existing_slot(&mut shape, field, parent)?
                        .as_object_mut()
                        .and_then(|object| object.remove(key))
                        .ok_or("key fault requires an existing object member")?;
                } else {
                    *existing_slot(&mut shape, field, path)? = Value::Null;
                }
            }
        }
    }
    Ok(())
}
fn canonical_reply_work(attempt: &Value, effect: &str) -> Result<usize, String> {
    let reply = |result| serde_json::json!({"jsonrpc":"2.0","id":u64::MAX,"result":result});
    let profile = "morphir/workbench/artifacts";
    let version = "0.1.0-draft.1";
    let peer = &attempt["peer"];
    let result = match effect {
        "initialize" => serde_json::json!({"protocolVersion":1}),
        "release" => serde_json::json!({}),
        "generate" if peer["kind"] == "failed" => {
            serde_json::json!({"profile":profile,"contractVersion":version,"status":"failed","diagnostics":peer["diagnostics"]})
        }
        "generate" => {
            let files = peer["artifacts"].as_array().expect("schema artifacts").iter().map(|file| Ok(serde_json::json!({"id":file["id"],"path":file["path"],"kind":file["kind"],"byteLength":recipe_bytes(&file["content"])? ,"sha256":"0".repeat(64)}))).collect::<Result<Vec<_>, String>>()?;
            serde_json::json!({"profile":profile,"contractVersion":version,"status":"ready","sessionId":attempt["input"]["sessionId"],"providerId":attempt["offer"]["id"],"generationId":peer["generationId"],"producer":peer["producer"],"target":attempt["input"]["target"],"irVersion":attempt["input"]["irVersion"],"artifacts":files,"diagnostics":peer["diagnostics"]})
        }
        "read" => {
            // Reserve the complete maximum canonical base64 chunk plus the
            // largest actual metadata envelope before any chunk is allocated.
            let mut metadata = 0;
            let missing = serde_json::json!({"id":""});
            let files = peer.get("artifacts").and_then(Value::as_array);
            for file in files.into_iter().flatten().chain(std::iter::once(&missing)) {
                let result = serde_json::json!({"profile":profile,"contractVersion":version,"generationId":peer["generationId"],"artifactId":file["id"],"offset":16_777_217,"nextOffset":16_777_217,"content":""});
                metadata = metadata.max(super::contract::encoded_size(
                    &reply(result),
                    MAX_CASE_WORK,
                )?);
            }
            return metadata
                .checked_add(65_536usize.div_ceil(3) * 4)
                .ok_or_else(|| "canonical reply work overflow".into());
        }
        _ => return Err("unknown canonical wire effect".into()),
    };
    super::contract::encoded_size(&reply(result), MAX_CASE_WORK)
}
fn local_context(value: &Value) -> Result<(), String> {
    if value.is_null() {
        return Ok(());
    }
    let source = value["sourceId"].as_str().expect("schema source identity");
    if source.encode_utf16().count() > 128 || source.chars().any(char::is_control) {
        return Err("client source identity exceeds limits".into());
    }
    super::artifacts::integer(&value["revision"], 2_147_483_647)?;
    super::artifacts::integer(&value["epoch"], 2_147_483_647)?;
    Ok(())
}
/// Account byte recipes, read expansion, raw deliveries and observations before
/// starting an adapter. This never materializes a recipe or infers a successful
/// client outcome from the input script.
pub(super) fn validate_input(value: &Value) -> Result<ClientInputBudget, String> {
    super::contract::encoded_size(value, 1_048_576)?;
    check_schema("mck-client-input.schema.json", value)?;
    let mut fixtures = BTreeMap::new();
    for attempt in value["attempts"].as_array().expect("schema attempts") {
        let alias = AttemptAlias::parse(&attempt["id"])?;
        local_context(&attempt["context"])?;
        let mut size = 0usize;
        if let Some(files) = attempt["peer"].get("artifacts") {
            for file in files.as_array().expect("schema artifacts") {
                size = size
                    .checked_add(recipe_bytes(&file["content"])?)
                    .ok_or("client fixture byte overflow")?;
                if size > 67_108_865 {
                    return Err("client fixture exceeds generation byte bound".into());
                }
            }
        }
        if fixtures.insert(alias, size).is_some() {
            return Err("duplicate client attempt alias".into());
        }
        for fault in attempt["localFaults"]
            .as_array()
            .expect("schema local faults")
        {
            for step in fault["path"].as_array().expect("schema path") {
                if step["kind"] == "index" {
                    super::artifacts::integer(&step["index"], 2_147_483_647)?;
                }
            }
        }
    }
    let all_fixture_bytes = fixtures.values().try_fold(0usize, |total, size| {
        total
            .checked_add(*size)
            .ok_or("client fixture sum overflow")
    })?;
    let mut budget = ClientInputBudget::default();
    let mut started = BTreeSet::new();
    let mut views = BTreeSet::new();
    let mut reads = 0usize;
    for action in value["actions"].as_array().expect("schema actions") {
        let kind = action["action"].as_str().expect("schema action");
        let attempt_value = action.get("attempt").or_else(|| {
            action
                .get("effect")
                .and_then(|effect| effect.get("attempt"))
        });
        let fixture_size = if let Some(alias) = attempt_value {
            let alias = AttemptAlias::parse(alias)?;
            *fixtures
                .get(&alias)
                .ok_or("client action references unknown attempt")?
        } else {
            0
        };
        match kind {
            "start" => {
                if !started.insert(AttemptAlias::parse(&action["attempt"])?) {
                    return Err("client attempt starts twice".into());
                }
                budget.decoded_and_reads.charge(fixture_size)?;
                budget.observations.charge(fixture_size)?;
                let definition = value["attempts"]
                    .as_array()
                    .expect("schema attempts")
                    .iter()
                    .find(|attempt| attempt["id"] == action["attempt"])
                    .expect("validated attempt reference");
                let (decoded, escaped) = local_value_work(definition)?;
                budget.decoded_and_reads.charge(decoded)?;
                budget.raw_frames.charge(escaped)?;
            }
            "deliver" | "reject" => {
                super::artifacts::integer(&action["effect"]["index"], 4095)?;
                let effect = action["effect"]["kind"]
                    .as_str()
                    .expect("schema effect kind");
                if kind == "deliver" {
                    let delivery = action["value"]["kind"].as_str().expect("schema delivery");
                    let compatible = match delivery {
                        "connect" => effect == "connect",
                        "digest" | "digest-mutated-input" => effect == "digest",
                        "peer" | "raw" => {
                            matches!(effect, "initialize" | "generate" | "read" | "release")
                        }
                        _ => unreachable!("closed delivery schema"),
                    };
                    if !compatible {
                        return Err("client delivery differs from declared effect kind".into());
                    }
                    if delivery == "digest-mutated-input" {
                        super::artifacts::integer(&action["value"]["xor"], 255)?;
                    }
                    if effect == "read" {
                        reads += 1;
                        budget.decoded_and_reads.charge(65_536)?;
                    }
                    if delivery == "peer" {
                        let attempt = value["attempts"]
                            .as_array()
                            .expect("schema attempts")
                            .iter()
                            .find(|attempt| attempt["id"] == action["effect"]["attempt"])
                            .expect("validated reference");
                        budget
                            .raw_frames
                            .charge(canonical_reply_work(attempt, effect)?)?;
                    }
                    if delivery == "raw" {
                        let raw = &action["value"]["frame"];
                        let frame = ClientFrame::parse(raw, FrameBoundary::Reply)?;
                        if let Some(segments) = raw.get("segments")
                            && segments
                                .as_array()
                                .expect("schema segments")
                                .iter()
                                .any(|segment| {
                                    segment["kind"] == "literal"
                                        && segment["source"].as_str().expect("schema literal").len()
                                            > 16_384
                                })
                        {
                            return Err("client input recipe literal exceeds byte bound".into());
                        }
                        budget.raw_frames.charge(frame.byte_len())?;
                    }
                }
            }
            "drain-reads" => {
                let count = super::artifacts::integer(&action["maxReads"], 4096)?;
                reads = reads
                    .checked_add(count)
                    .ok_or("client read count overflow")?;
                budget.decoded_and_reads.charge(
                    count
                        .checked_mul(65_536)
                        .ok_or("client read work overflow")?,
                )?;
                let attempt = value["attempts"]
                    .as_array()
                    .expect("schema attempts")
                    .iter()
                    .find(|attempt| attempt["id"] == action["attempt"])
                    .expect("validated reference");
                budget.raw_frames.charge(
                    count
                        .checked_mul(canonical_reply_work(attempt, "read")?)
                        .ok_or("canonical read reply work overflow")?,
                )?;
            }
            "set-current" => local_context(&action["context"])?,
            "publish" => {
                let view = action["views"].as_str().expect("schema view alias");
                if !views.insert(view) {
                    return Err("client view alias published twice".into());
                }
                budget.observations.charge(fixture_size)?;
            }
            "mutate-copy" => {
                super::artifacts::integer(&action["offset"], 16_777_217)?;
                super::artifacts::integer(&action["xor"], 255)?;
                budget.observations.charge(fixture_size)?;
            }
            "download" | "archive" => {
                let selected = &action["views"];
                if !views.contains(selected["views"].as_str().expect("schema views")) {
                    return Err("client selection references unknown views".into());
                }
                for index in selected["indices"].as_array().expect("schema indices") {
                    super::artifacts::integer(index, 256)?;
                }
                for mutation in selected["mutations"].as_array().expect("schema mutations") {
                    super::artifacts::integer(&mutation["index"], 256)?;
                    if mutation["kind"] == "reference" {
                        super::artifacts::integer(&mutation["fromIndex"], 256)?;
                        if !views
                            .contains(mutation["fromViews"].as_str().expect("schema reference"))
                        {
                            return Err("client mutation references unknown views".into());
                        }
                    }
                }
                budget.observations.charge(
                    all_fixture_bytes
                        .checked_mul(if kind == "archive" { 3 } else { 1 })
                        .ok_or("client observation work overflow")?,
                )?;
            }
            "replace-caller"
            | "replace-effect-functions"
            | "cancel"
            | "close-channel"
            | "clear-registry"
            | "observe" => {}
            _ => unreachable!("closed action schema"),
        }
        if reads > 4096 {
            return Err("client scenario exceeds read count bound".into());
        }
    }
    if started.len() != fixtures.len() {
        return Err("every client definition must start exactly once".into());
    }
    validate_local_paths(value)?;
    Ok(budget)
}

#[derive(Clone, Copy, Debug)]
enum FrameBoundary {
    Generate,
    Control,
    Reply,
}
impl FrameBoundary {
    fn byte_limit(self) -> usize {
        match self {
            Self::Generate => 1_048_576,
            Self::Control => 16_384,
            Self::Reply => 131_073,
        }
    }
}
#[derive(Clone, Copy, Debug)]
struct FrameByteLength(usize);
#[derive(Debug)]
enum FrameSegment<'a> {
    Literal(&'a str),
    RepeatAscii { byte: u8, count: usize },
}
/// The literal strings remain borrowed. No repetition allocation occurs until
/// every segment and the aggregate UTF-8 byte length have been checked.
#[derive(Debug)]
struct ClientFrame<'a> {
    segments: Vec<FrameSegment<'a>>,
    bytes: FrameByteLength,
}
fn closed<'a>(
    value: &'a Value,
    fields: &[&str],
) -> Result<&'a serde_json::Map<String, Value>, String> {
    let object = value.as_object().ok_or("client frame must be an object")?;
    if object.len() != fields.len() || fields.iter().any(|field| !object.contains_key(*field)) {
        return Err("client frame contains missing or unknown members".into());
    }
    Ok(object)
}
impl<'a> ClientFrame<'a> {
    fn parse(value: &'a Value, boundary: FrameBoundary) -> Result<Self, String> {
        let mut segments = Vec::new();
        let mut bytes = 0usize;
        let mut push = |segment: FrameSegment<'a>| -> Result<(), String> {
            let length = match &segment {
                FrameSegment::Literal(source) => source.len(),
                FrameSegment::RepeatAscii { count, .. } => *count,
            };
            bytes = bytes
                .checked_add(length)
                .ok_or("client frame byte count overflow")?;
            if bytes > boundary.byte_limit() {
                return Err("client frame exceeds expanded byte limit".into());
            }
            segments.push(segment);
            Ok(())
        };
        match value["kind"].as_str() {
            Some("text") => {
                let object = closed(value, &["kind", "source"])?;
                push(FrameSegment::Literal(
                    object["source"]
                        .as_str()
                        .ok_or("client frame source must be text")?,
                ))?;
            }
            Some("segments") => {
                let object = closed(value, &["kind", "segments"])?;
                let values = object["segments"]
                    .as_array()
                    .ok_or("client frame segments must be an array")?;
                if values.is_empty() || values.len() > 32 {
                    return Err("client frame segment count exceeds bounds".into());
                }
                for segment in values {
                    match segment["kind"].as_str() {
                        Some("literal") => {
                            let object = closed(segment, &["kind", "source"])?;
                            push(FrameSegment::Literal(
                                object["source"]
                                    .as_str()
                                    .ok_or("client frame literal must be text")?,
                            ))?;
                        }
                        Some("repeat-ascii") => {
                            let object = closed(segment, &["kind", "byte", "count"])?;
                            let byte = super::artifacts::integer(&object["byte"], 127)? as u8;
                            let count =
                                super::artifacts::integer(&object["count"], boundary.byte_limit())?;
                            push(FrameSegment::RepeatAscii { byte, count })?;
                        }
                        _ => return Err("unknown client frame segment".into()),
                    }
                }
            }
            _ => return Err("unknown client frame encoding".into()),
        }
        Ok(Self {
            segments,
            bytes: FrameByteLength(bytes),
        })
    }
    fn byte_len(&self) -> usize {
        self.bytes.0
    }
    fn expand(&self) -> String {
        let mut output = String::with_capacity(self.bytes.0);
        for segment in &self.segments {
            match segment {
                FrameSegment::Literal(source) => output.push_str(source),
                FrameSegment::RepeatAscii { byte, count } => {
                    output.extend(std::iter::repeat_n(char::from(*byte), *count));
                }
            }
        }
        output
    }
    fn parse_json(&self) -> Result<Value, String> {
        crate::json::strict::parse_exact(&self.expand())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn lossless_frames_retain_literal_json_number_and_duplicate_evidence() {
        let source =
            "{\"id\":1e0,\"x\":1,\"x\":2,\"ir\":{\"$serde_json::private::RawValue\":\"true\"}}";
        let input = json!({"kind":"text","source":source});
        let frame = ClientFrame::parse(&input, FrameBoundary::Generate).unwrap();
        assert_eq!(frame.expand(), source);
        assert!(crate::json::strict::parse_exact(&frame.expand()).is_err());
        let marker = "{\"ir\":{\"$serde_json::private::RawValue\":\"true\"}}";
        let parsed = ClientFrame::parse(
            &json!({"kind":"text","source":marker}),
            FrameBoundary::Generate,
        )
        .unwrap()
        .parse_json()
        .unwrap();
        assert_eq!(parsed["ir"]["$serde_json::private::RawValue"], "true");
    }

    #[test]
    fn lossless_frames_admit_uncompressible_large_literal_segments() {
        let source = "a".repeat(600_000);
        let input = json!({"kind":"segments","segments":[{"kind":"literal","source":source}]});
        let frame = ClientFrame::parse(&input, FrameBoundary::Generate).unwrap();
        assert_eq!(frame.byte_len(), 600_000);
        assert_eq!(frame.expand(), source);
    }

    #[test]
    fn lossless_frames_check_expansion_before_allocation() {
        for count in [1_048_577u64, u64::MAX] {
            let raw = json!({"kind":"segments","segments":[{"kind":"repeat-ascii","byte":32,"count":count}]});
            assert!(ClientFrame::parse(&raw, FrameBoundary::Generate).is_err());
        }
        let exactly = json!({"kind":"segments","segments":[{"kind":"repeat-ascii","byte":32,"count":1_048_576}]});
        assert_eq!(
            ClientFrame::parse(&exactly, FrameBoundary::Generate)
                .unwrap()
                .byte_len(),
            1_048_576
        );
        assert!(ClientFrame::parse(&exactly, FrameBoundary::Control).is_err());
    }

    #[test]
    fn lossless_frames_count_utf8_and_reject_nonascii_repeat_units() {
        let exactly = json!({"kind":"text","source":"😀".repeat(4096)});
        assert_eq!(
            ClientFrame::parse(&exactly, FrameBoundary::Control)
                .unwrap()
                .byte_len(),
            16_384
        );
        let over = json!({"kind":"text","source":"😀".repeat(4096)+"x"});
        assert!(ClientFrame::parse(&over, FrameBoundary::Control).is_err());
        let bad =
            json!({"kind":"segments","segments":[{"kind":"repeat-ascii","byte":128,"count":1}]});
        assert!(ClientFrame::parse(&bad, FrameBoundary::Generate).is_err());
    }

    #[test]
    fn lossless_frames_preserve_exact_integral_counts_and_reject_rounding() {
        for token in ["1", "1.0", "1e0", "-0"] {
            let raw = crate::json::strict::parse_exact(&format!("{{\"kind\":\"segments\",\"segments\":[{{\"kind\":\"repeat-ascii\",\"byte\":32,\"count\":{token}}}]}}" )).unwrap();
            assert!(
                ClientFrame::parse(&raw, FrameBoundary::Generate).is_ok(),
                "{token}"
            );
        }
        for token in [
            "1.5",
            "1e-999",
            "1.0000000000000001",
            "-1",
            "18446744073709551616",
        ] {
            let raw = crate::json::strict::parse_exact(&format!("{{\"kind\":\"segments\",\"segments\":[{{\"kind\":\"repeat-ascii\",\"byte\":32,\"count\":{token}}}]}}" )).unwrap();
            assert!(
                ClientFrame::parse(&raw, FrameBoundary::Generate).is_err(),
                "{token}"
            );
        }
    }

    #[test]
    fn lossless_frames_are_closed_and_bound_segment_count() {
        for raw in [
            json!({"kind":"text","source":"x","extra":true}),
            json!({"kind":"segments","segments":[]}),
            json!({"kind":"segments","segments":vec![json!({"kind":"literal","source":""});33]}),
            json!({"kind":"segments","segments":[{"kind":"repeat-ascii","byte":32,"count":1,"extra":true}]}),
            json!({"kind":"segments","segments":[{"kind":"unknown","source":"x"}]}),
        ] {
            assert!(
                ClientFrame::parse(&raw, FrameBoundary::Generate).is_err(),
                "{raw}"
            );
        }
    }
}

#[cfg(test)]
mod literal_envelope_tests {
    use serde_json::json;
    #[test]
    fn shared_observation_preserves_nested_private_marker_maps_literally() {
        let value = json!({"ir":{"$serde_json::private::Number":"1"},"options":{"$serde_json::private::RawValue":"{\"x\":1,\"x\":2}"}});
        let observation =
            super::super::contract::Observation::parse(json!({"status":"ok","value":value}))
                .unwrap();
        let super::super::contract::Observation::Ok { value: actual } = observation else {
            panic!("ok expected")
        };
        assert_eq!(actual, value);
    }
}

#[cfg(test)]
mod scenario_budget_tests {
    use super::*;
    use serde_json::{Value, json};
    fn input() -> Value {
        crate::json::strict::parse_exact(include_str!(
            "../../../../spec/workbench/mck/draft.28/client/cases.json"
        ))
        .unwrap()["cases"][0]["input"]
            .clone()
    }
    #[test]
    fn client_scenario_admits_independently_authored_first_input() {
        let budget = validate_input(&input()).unwrap();
        assert_eq!(budget.decoded_and_reads.0, 65_536);
        assert!(budget.raw_frames.0 > 87_384);
        assert_eq!(budget.observations.0, 0);
    }
    #[test]
    fn client_scenario_work_is_checked_without_expanding_peer_bytes() {
        let mut value = input();
        value["attempts"][0]["peer"]["artifacts"] = json!((0..4).map(|index| json!({"id":format!("file-{index}"),"path":format!("file-{index}.bin"),"kind":"binary","content":{"kind":"chunk-indexed-u8","length":16_777_216,"seed":index}})).collect::<Vec<_>>());
        value["actions"] = json!([
            {"action":"start","attempt":"A"},
            {"action":"drain-reads","attempt":"A","maxReads":1024}
        ]);
        assert_eq!(
            validate_input(&value).unwrap().decoded_and_reads.0,
            134_217_728
        );
        value["actions"][1]["maxReads"] = json!(1025);
        assert!(validate_input(&value).is_err());
        value["actions"][1]["maxReads"] = json!(1024);
        value["attempts"][0]["peer"]["artifacts"][0]["content"]["length"] = json!(16_777_218);
        assert!(validate_input(&value).is_err());
    }
    #[test]
    fn client_scenario_repeated_observers_cannot_bypass_copy_work_budget() {
        let mut value = input();
        value["attempts"][0]["peer"]["artifacts"][0]["content"] =
            json!({"kind":"repeat-u8","length":16_777_216,"byte":0});
        value["actions"] = json!(std::iter::once(json!({"action":"start","attempt":"A"})).chain((0..9).map(|index|json!({"action":"publish","attempt":"A","views":format!("views-{index}")}))).collect::<Vec<_>>());
        assert!(validate_input(&value).is_err());
    }
    #[test]
    fn client_scenario_refs_and_start_inventory_are_closed() {
        for mutation in [
            "duplicate-attempt",
            "unknown-ref",
            "missing-start",
            "duplicate-start",
            "wrong-kind",
            "noninteger-index",
        ] {
            let mut value = input();
            match mutation {
                "duplicate-attempt" => {
                    let duplicate = value["attempts"][0].clone();
                    value["attempts"].as_array_mut().unwrap().push(duplicate);
                }
                "unknown-ref" => value["actions"][2]["effect"]["attempt"] = json!("other"),
                "missing-start" => {
                    value["actions"].as_array_mut().unwrap().remove(1);
                }
                "duplicate-start" => value["actions"]
                    .as_array_mut()
                    .unwrap()
                    .push(json!({"action":"start","attempt":"A"})),
                "wrong-kind" => value["actions"][2]["effect"]["kind"] = json!("invented"),
                "noninteger-index" => {
                    value["actions"][2]["effect"]["index"] =
                        crate::json::strict::parse_exact("1e-999").unwrap()
                }
                _ => unreachable!(),
            }
            assert!(validate_input(&value).is_err(), "{mutation}");
        }
    }
    #[test]
    fn client_scenario_preserves_literal_caller_objects_without_second_decode() {
        let mut value = input();
        value["attempts"][0]["input"]["ir"] = json!({"$serde_json::private::Number":"1"});
        value["attempts"][0]["input"]["options"] =
            json!({"$serde_json::private::RawValue":"{\"x\":1,\"x\":2}"});
        validate_input(&value).unwrap();
        assert!(value["attempts"][0]["input"]["ir"].is_object());
        assert_eq!(
            value["attempts"][0]["input"]["options"]["$serde_json::private::RawValue"],
            "{\"x\":1,\"x\":2}"
        );
    }
}

#[cfg(test)]
mod evidence_tests {
    use super::*;
    use serde_json::{Value, json};
    fn evidence() -> Value {
        crate::json::strict::parse_exact(include_str!(
            "../../../../spec/workbench/mck/draft.28/client/cases.json"
        ))
        .unwrap()["cases"][0]["expected"]["value"]
            .clone()
    }
    #[test]
    fn first_authored_evidence_has_independent_normalized_request_and_byte_evidence() {
        let projected = projection(&evidence()).unwrap();
        assert_eq!(
            projected["events"][2]["argument"]["request"]["id"],
            "exchange-1"
        );
        assert_eq!(
            projected["attempts"][0]["result"]["inventory"][0]["bytes"]["sha256"],
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert!(
            projected["checkpoints"][10]["actionResult"]["archive"]
                .get("encodedByteLength")
                .is_none()
        );
    }
    #[test]
    fn evidence_rejects_forged_context_progress_provenance_counts_and_terminal_state() {
        for (pointer, bad) in [
            ("/attempts/0/capture/sessionId", json!("another-session")),
            (
                "/attempts/0/result/manifest/producer/version",
                json!("9007199254740992.0.0"),
            ),
            ("/attempts/0/result/manifest/providerId", json!("stolen")),
            (
                "/attempts/0/result/cleanup/generationId",
                json!("another-generation"),
            ),
            ("/attempts/0/effects/read", json!(0)),
            ("/attempts/0/closeCalls", json!(0)),
            ("/attempts/0/result/inventory/0/bytes/byteLength", json!(1)),
            ("/events/0/index", json!(1)),
            ("/events/1/index", json!(99)),
            ("/events/8/argument/sha256", json!("0".repeat(64))),
            ("/checkpoints/13/attempts/0/terminal/kind", json!("pending")),
        ] {
            let mut bad_value = evidence();
            *bad_value.pointer_mut(pointer).unwrap() = bad;
            assert!(projection(&bad_value).is_err(), "{pointer}");
        }
        let mut bad = evidence();
        let mut request = crate::json::strict::parse_exact(
            bad["events"][6]["argument"]["frame"]["source"]
                .as_str()
                .unwrap(),
        )
        .unwrap();
        request["params"]["offset"] = json!(1);
        bad["events"][6]["argument"]["frame"]["source"] = json!(request.to_string());
        assert!(projection(&bad).is_err());
    }
    #[test]
    fn evidence_requires_lossless_raw_request_and_refuses_duplicate_members() {
        let mut value = evidence();
        value["events"][4]["argument"]["frame"]["source"] = json!(
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"id\":2,\"method\":\"morphir.artifacts.generate\",\"params\":{}}"
        );
        assert!(projection(&value).is_err());
        let mut value = evidence();
        value["events"][4]["argument"] = json!({"request":{"jsonrpc":"2.0","id":2,"method":"morphir.artifacts.generate","params":{}}});
        assert!(projection(&value).is_err());
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum EffectKind {
    Connect,
    Initialize,
    Generate,
    Read,
    Digest,
    Release,
}
impl EffectKind {
    fn parse(value: &Value) -> Result<Self, String> {
        match value.as_str() {
            Some("connect") => Ok(Self::Connect),
            Some("initialize") => Ok(Self::Initialize),
            Some("generate") => Ok(Self::Generate),
            Some("read") => Ok(Self::Read),
            Some("digest") => Ok(Self::Digest),
            Some("release") => Ok(Self::Release),
            _ => Err("unknown client effect kind".into()),
        }
    }
    fn name(self) -> &'static str {
        match self {
            Self::Connect => "connect",
            Self::Initialize => "initialize",
            Self::Generate => "generate",
            Self::Read => "read",
            Self::Digest => "digest",
            Self::Release => "release",
        }
    }
    fn method(self) -> Option<&'static str> {
        match self {
            Self::Initialize => Some("morphir.session.initialize"),
            Self::Generate => Some("morphir.artifacts.generate"),
            Self::Read => Some("morphir.artifacts.read"),
            Self::Release => Some("morphir.artifacts.release"),
            _ => None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Settlement {
    Pending,
    Resolved,
    Rejected,
}
#[derive(Debug)]
struct TraceEffect {
    kind: EffectKind,
    settlement: Settlement,
    argument: Value,
}
#[derive(Debug, Default)]
struct ReadCoverage {
    requests: usize,
    next_request_offset: usize,
}
#[derive(Debug, Default)]
struct AttemptTrace {
    effects: Vec<TraceEffect>,
    closes: usize,
    generation: Option<String>,
    read_order: Vec<String>,
    reads: BTreeMap<String, ReadCoverage>,
    request_ids: BTreeSet<String>,
}
fn capture(value: &Value) -> Result<(), String> {
    for field in ["providerId", "sessionId", "target", "irVersion"] {
        super::artifacts::identity(&value[field])?;
    }
    Ok(())
}
fn diagnostics(value: &Value) -> Result<(), String> {
    for diagnostic in value
        .as_array()
        .ok_or("client diagnostics must be an array")?
    {
        if !diagnostic["location"].is_null() {
            for position in ["start", "end"] {
                for unit in ["line", "character"] {
                    super::artifacts::integer(
                        &diagnostic["location"]["range"][position][unit],
                        4_294_967_295,
                    )?;
                }
            }
        }
    }
    Ok(())
}
fn measured(value: &Value, max: usize) -> Result<usize, String> {
    let length = super::artifacts::integer(&value["byteLength"], max)?;
    if length == 0
        && value["sha256"] != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    {
        return Err("empty client bytes have a nonempty digest".into());
    }
    Ok(length)
}
fn text_measurement(value: &Value, max: usize) -> Result<(), String> {
    let units = super::artifacts::integer(&value["utf16Length"], max)?;
    let bytes = measured(
        &value["utf8"],
        max.checked_mul(3).ok_or("client text budget overflow")?,
    )?;
    if bytes < units || (units == 0 && bytes != 0) {
        return Err("client text byte/unit measurements disagree".into());
    }
    Ok(())
}
fn failure(value: &Value) -> Result<(), String> {
    if value["kind"] == "protocol" && value["failure"]["kind"] == "remote" {
        super::artifacts::signed_rpc_code(&value["failure"]["rpcCode"])?;
    }
    if value["kind"] == "other"
        && value["message"]
            .as_str()
            .expect("schema error message")
            .encode_utf16()
            .count()
            > 512
    {
        return Err("client error message exceeds UTF16 budget".into());
    }
    Ok(())
}
fn bind_generation(trace: &mut AttemptTrace, value: &Value) -> Result<(), String> {
    let id = super::artifacts::identity(value)?;
    if trace
        .generation
        .as_deref()
        .is_some_and(|existing| existing != id)
    {
        return Err("client request escaped captured generation".into());
    }
    trace.generation = Some(id.into());
    Ok(())
}
fn request(
    trace: &mut AttemptTrace,
    binding: &Value,
    kind: EffectKind,
    raw: &ClientFrame<'_>,
) -> Result<Value, String> {
    let mut value = raw.parse_json()?;
    closed(&value, &["jsonrpc", "id", "method", "params"])?;
    if value["jsonrpc"] != "2.0" || value["method"] != kind.method().expect("wire effect") {
        return Err("client raw request method differs from effect".into());
    }
    let id = value["id"]
        .as_u64()
        .ok_or("client request ID requires connected-protocol u64 syntax")?
        .to_string();
    if !trace.request_ids.insert(id) {
        return Err("client request reuses an exchange ID".into());
    }
    if trace
        .effects
        .iter()
        .any(|effect| effect.kind.method().is_some() && effect.settlement == Settlement::Pending)
    {
        return Err("client opened concurrent wire exchanges".into());
    }
    if !trace.effects.iter().any(|effect| {
        effect.kind == EffectKind::Connect && effect.settlement == Settlement::Resolved
    }) {
        return Err("client wire request precedes an owned connection".into());
    }
    let params = &value["params"];
    match kind {
        EffectKind::Initialize => {
            closed(params, &["protocolVersion", "sessionId"])?;
            if super::artifacts::integer(&params["protocolVersion"], 1)? != 1
                || params["sessionId"] != binding["sessionId"]
            {
                return Err("client initialize escaped captured session".into());
            }
        }
        EffectKind::Generate => {
            closed(params, &["contractVersion", "providerId", "generation"])?;
            closed(
                &params["generation"],
                &["ir", "irVersion", "target", "options"],
            )?;
            if params["providerId"] != binding["providerId"]
                || params["generation"]["target"] != binding["target"]
                || params["generation"]["irVersion"] != binding["irVersion"]
            {
                return Err("client generation escaped captured input metadata".into());
            }
        }
        EffectKind::Read => {
            closed(
                params,
                &[
                    "contractVersion",
                    "generationId",
                    "artifactId",
                    "offset",
                    "maxBytes",
                ],
            )?;
            bind_generation(trace, &params["generationId"])?;
            let artifact = super::artifacts::identity(&params["artifactId"])?.to_owned();
            let offset = super::artifacts::integer(&params["offset"], 16_777_216)?;
            if super::artifacts::integer(&params["maxBytes"], 65_536)? != 65_536 {
                return Err("client kit requires the declared maximum-chunk policy".into());
            }
            if !trace.reads.contains_key(&artifact) {
                trace.read_order.push(artifact.clone());
            }
            if trace.read_order.last() != Some(&artifact) {
                return Err("client read inventory order moved backwards".into());
            }
            let coverage = trace.reads.entry(artifact).or_default();
            if coverage.next_request_offset != offset {
                return Err("client read offset skipped or repeated bytes".into());
            }
            coverage.requests += 1;
            coverage.next_request_offset = offset
                .checked_add(65_536)
                .ok_or("client read progress overflow")?;
        }
        EffectKind::Release => {
            closed(params, &["contractVersion", "generationId"])?;
            bind_generation(trace, &params["generationId"])?;
        }
        _ => unreachable!("wire kind"),
    }
    if kind != EffectKind::Initialize && params["contractVersion"] != "0.1.0-draft.1" {
        return Err("client request changed exact artifact draft".into());
    }
    let prior = |wanted| {
        trace
            .effects
            .iter()
            .any(|effect| effect.kind == wanted && effect.settlement == Settlement::Resolved)
    };
    if kind == EffectKind::Generate && !prior(EffectKind::Initialize) {
        return Err("client generation preceded initialization".into());
    }
    if matches!(kind, EffectKind::Read | EffectKind::Release) && !prior(EffectKind::Generate) {
        return Err("client handle request preceded generation".into());
    }
    value["id"] = serde_json::json!(format!("exchange-{}", trace.effects.len()));
    Ok(value)
}
fn apply_event(
    event: &Value,
    traces: &mut BTreeMap<AttemptAlias, AttemptTrace>,
    definitions: &BTreeMap<AttemptAlias, &Value>,
    frames: &mut WorkUnits,
    derived: &mut DerivedProjectionBudget,
) -> Result<Value, String> {
    let alias = AttemptAlias::parse(&event["attempt"])?;
    let trace = traces
        .get_mut(&alias)
        .ok_or("client event references unknown attempt")?;
    let definition = definitions[&alias];
    let mut projected = event.clone();
    match event["kind"].as_str().expect("schema event") {
        "effect" => {
            let index = super::artifacts::integer(&event["index"], 4095)?;
            if index != trace.effects.len() {
                return Err("client effect inventory is not sequential".into());
            }
            let kind = EffectKind::parse(&event["effect"])?;
            if kind != EffectKind::Read
                && kind != EffectKind::Digest
                && trace.effects.iter().any(|effect| effect.kind == kind)
            {
                return Err("client repeated a one-shot effect".into());
            }
            if kind == EffectKind::Connect && !trace.effects.is_empty() {
                return Err("client connect is not the first effect".into());
            }
            let argument = if kind.method().is_some() {
                let frame = ClientFrame::parse(
                    &event["argument"]["frame"],
                    if kind == EffectKind::Generate {
                        FrameBoundary::Generate
                    } else {
                        FrameBoundary::Control
                    },
                )?;
                frames.charge(frame.byte_len())?;
                derived.reserve_frame(frame.byte_len())?;
                let request = request(trace, &definition["capture"], kind, &frame)?;
                let argument = serde_json::json!({"request":request});
                projected["argument"] = argument.clone();
                argument
            } else {
                if kind == EffectKind::Connect && event["argument"]["signalAborted"] != false {
                    return Err("client started a connection after cancellation".into());
                }
                if kind == EffectKind::Digest {
                    measured(&event["argument"], 16_777_216)?;
                    if trace.effects.iter().any(|effect| {
                        effect.kind == EffectKind::Read && effect.settlement == Settlement::Pending
                    }) {
                        return Err("client digest preceded read completion".into());
                    }
                }
                event["argument"].clone()
            };
            trace.effects.push(TraceEffect {
                kind,
                settlement: Settlement::Pending,
                argument,
            });
        }
        "settled" => {
            let index = super::artifacts::integer(&event["index"], 4095)?;
            let effect = trace
                .effects
                .get_mut(index)
                .ok_or("client settled an unknown effect")?;
            if effect.settlement != Settlement::Pending {
                return Err("client effect settled twice".into());
            }
            effect.settlement = if event["settlement"] == "resolved" {
                Settlement::Resolved
            } else {
                Settlement::Rejected
            };
        }
        "close" => {
            if !trace.effects.iter().any(|effect| {
                effect.kind == EffectKind::Connect && effect.settlement == Settlement::Resolved
            }) {
                return Err("client closed a connection it never owned".into());
            }
            trace.closes += 1;
        }
        "cancel-result" => cleanup(&event["cleanup"], trace)?,
        _ => unreachable!("closed event schema"),
    }
    Ok(projected)
}
fn cleanup(value: &Value, trace: &AttemptTrace) -> Result<(), String> {
    if let Some(id) = value.get("generationId").filter(|id| !id.is_null()) {
        let id = super::artifacts::identity(id)?;
        if trace
            .generation
            .as_deref()
            .is_some_and(|generation| generation != id)
        {
            return Err("client cleanup escaped generation ownership".into());
        }
    }
    if value["kind"] == "released"
        && !trace.effects.iter().any(|effect| {
            effect.kind == EffectKind::Release && effect.settlement == Settlement::Resolved
        })
    {
        return Err("client claimed release without an acknowledged release exchange".into());
    }
    Ok(())
}
fn final_attempt(value: &Value, trace: &AttemptTrace) -> Result<(), String> {
    if trace
        .effects
        .iter()
        .any(|effect| effect.settlement == Settlement::Pending)
    {
        return Err("final client evidence contains unsettled effects".into());
    }
    if super::artifacts::integer(&value["closeCalls"], 4096)? != trace.closes {
        return Err("client close count differs from actual trace".into());
    }
    for kind in [
        EffectKind::Connect,
        EffectKind::Initialize,
        EffectKind::Generate,
        EffectKind::Read,
        EffectKind::Digest,
        EffectKind::Release,
    ] {
        if super::artifacts::integer(&value["effects"][kind.name()], 4096)?
            != trace
                .effects
                .iter()
                .filter(|effect| effect.kind == kind)
                .count()
        {
            return Err("client effect count differs from actual trace".into());
        }
    }
    if trace.effects.iter().any(|effect| {
        effect.kind == EffectKind::Connect && effect.settlement == Settlement::Resolved
    }) && trace.closes == 0
    {
        return Err("client retained an owned connection after completion".into());
    }
    let result = &value["result"];
    if result["kind"] == "construction-refused" {
        if !value["capture"].is_null()
            || !trace.effects.is_empty()
            || value["phase"] != "construction-refused"
        {
            return Err("construction refusal contains a captured attempt or effects".into());
        }
        return failure(&result["failure"]);
    }
    capture(&value["capture"])?;
    if value["phase"] != "finished" {
        return Err("client final attempt is not terminal".into());
    }
    cleanup(&result["cleanup"], trace)?;
    match result["kind"].as_str().expect("schema run result") {
        "verified" => {
            if result["cleanup"]["kind"] != "released" {
                return Err("client verified owner escaped before release".into());
            }
            let manifest = &result["manifest"];
            capture(manifest)?;
            for key in [
                "profile",
                "contractVersion",
                "providerId",
                "sessionId",
                "target",
                "irVersion",
            ] {
                if manifest[key] != value["capture"][key] {
                    return Err("client owner manifest differs from capture".into());
                }
            }
            if manifest["generationId"] != result["cleanup"]["generationId"] {
                return Err("client manifest and cleanup generation differ".into());
            }
            super::artifacts::identity(&manifest["generationId"])?;
            super::artifacts::identity(&manifest["producer"]["id"])?;
            super::artifacts::producer_version(&manifest["producer"]["version"])?;
            diagnostics(&manifest["diagnostics"])?;
            let inventory = result["inventory"].as_array().expect("schema inventory");
            super::artifacts::portable_paths(inventory)?;
            let digests = trace
                .effects
                .iter()
                .filter(|effect| effect.kind == EffectKind::Digest)
                .collect::<Vec<_>>();
            if digests.len() != inventory.len() || trace.read_order.len() != inventory.len() {
                return Err("client verified inventory differs from read/hash inventory".into());
            }
            let mut total = 0usize;
            for (index, file) in inventory.iter().enumerate() {
                if file["id"] != format!("file-{index}") {
                    return Err("client file alias differs from inventory order".into());
                }
                let length = measured(&file["bytes"], 16_777_216)?;
                total = total
                    .checked_add(length)
                    .ok_or("client inventory overflow")?;
                if digests[index].argument != file["bytes"]
                    || digests[index].settlement != Settlement::Resolved
                {
                    return Err("client byte owner differs from actual digest input".into());
                }
                let coverage = &trace.reads[&trace.read_order[index]];
                if coverage.requests != length.div_ceil(65_536).max(1) {
                    return Err(
                        "client read inventory does not cover complete original bytes".into(),
                    );
                }
                let preview = &file["preview"];
                match preview["kind"].as_str().expect("schema preview") {
                    "binary" => {
                        if file["declaredKind"] != "binary"
                            || measured(&preview["prefix"], 65_536)? != length.min(65_536)
                        {
                            return Err("client binary preview exceeds original prefix".into());
                        }
                    }
                    "text" | "text-prefix" => {
                        if file["declaredKind"] != "utf8-text" {
                            return Err("client text preview changed declared kind".into());
                        }
                        text_measurement(&preview["text"], 65_536)?;
                    }
                    "invalid-utf8" => {
                        if file["declaredKind"] != "utf8-text" {
                            return Err(
                                "client invalid text preview has no text declaration".into()
                            );
                        }
                    }
                    _ => unreachable!("closed preview schema"),
                }
            }
            if total > 67_108_864 {
                return Err("client verified byte inventory exceeds generation bound".into());
            }
        }
        "generation-failed" => {
            diagnostics(&result["diagnostics"])?;
            if result["cleanup"]["kind"] != "not-retained"
                || trace.effects.iter().any(|effect| {
                    matches!(
                        effect.kind,
                        EffectKind::Read | EffectKind::Digest | EffectKind::Release
                    )
                })
            {
                return Err("generation failure retained handles or exposed output".into());
            }
        }
        "failed" => failure(&result["failure"])?,
        "discarded" => {}
        _ => unreachable!("closed terminal schema"),
    }
    Ok(())
}
/// Parse the raw outbound frames independently and reconcile the measured
/// owner/effect/checkpoint evidence before normalization. No implementation
/// decoder or expected fixture output participates in this projection.
pub(super) fn projection(value: &Value) -> Result<Value, String> {
    let evidence_bytes = super::contract::encoded_size(value, 1_048_576)?;
    let mut derived = DerivedProjectionBudget::new(evidence_bytes)?;
    check_schema("mck-client-projection.schema.json", value)?;
    let mut canonical = value.clone();
    canonical_numbers(&mut canonical, false)?;
    let value = &canonical;
    let definitions = value["attempts"]
        .as_array()
        .expect("schema attempts")
        .iter()
        .map(|attempt| Ok((AttemptAlias::parse(&attempt["id"])?, attempt)))
        .collect::<Result<BTreeMap<_, _>, String>>()?;
    if definitions.len() != value["attempts"].as_array().expect("schema attempts").len() {
        return Err("duplicate final client attempt identity".into());
    }
    let mut traces = definitions
        .keys()
        .cloned()
        .map(|id| (id, AttemptTrace::default()))
        .collect::<BTreeMap<_, _>>();
    let mut frames = WorkUnits::default();
    let mut cursor = 0usize;
    let mut events = Vec::new();
    let mut labels = BTreeSet::new();
    let raw_events = value["events"].as_array().expect("schema events");
    let checkpoints = value["checkpoints"].as_array().expect("schema checkpoints");
    for (index, checkpoint) in checkpoints.iter().enumerate() {
        if super::artifacts::integer(&checkpoint["actionIndex"], 511)? != index {
            return Err("client checkpoint action inventory differs".into());
        }
        if !checkpoint["label"].is_null()
            && !labels.insert(checkpoint["label"].as_str().expect("schema label"))
        {
            return Err("client checkpoint label reused".into());
        }
        let target = super::artifacts::integer(&checkpoint["eventCount"], 4096)?;
        if target < cursor || target > raw_events.len() {
            return Err("client checkpoint event prefix differs".into());
        }
        while cursor < target {
            events.push(apply_event(
                &raw_events[cursor],
                &mut traces,
                &definitions,
                &mut frames,
                &mut derived,
            )?);
            cursor += 1;
        }
        local_context(&checkpoint["currentContext"])?;
        let snapshots = checkpoint["attempts"]
            .as_array()
            .expect("schema attempt snapshots");
        if snapshots.len() != definitions.len() {
            return Err("client checkpoint attempt inventory differs".into());
        }
        let mut seen = BTreeSet::new();
        for snapshot in snapshots {
            let id = AttemptAlias::parse(&snapshot["id"])?;
            if !seen.insert(id.clone()) {
                return Err("client checkpoint duplicated an attempt".into());
            }
            let trace = traces
                .get(&id)
                .ok_or("client checkpoint references unknown attempt")?;
            if super::artifacts::integer(&snapshot["closeCalls"], 4096)? != trace.closes {
                return Err("checkpoint close count differs from trace prefix".into());
            }
            let pending=trace.effects.iter().enumerate().filter(|(_,effect)|effect.settlement==Settlement::Pending).map(|(index,effect)|serde_json::json!({"index":index,"effect":effect.kind.name()})).collect::<Vec<_>>();
            if snapshot["pending"] != serde_json::json!(pending) {
                return Err("checkpoint pending inventory differs from trace prefix".into());
            }
            let terminal = &snapshot["terminal"];
            if terminal["kind"] != "pending"
                && (!pending.is_empty()
                    || snapshot["phase"] != "finished"
                        && snapshot["phase"] != "construction-refused")
            {
                return Err("client terminal checkpoint contains live work".into());
            }
        }
    }
    if cursor != raw_events.len() {
        return Err("client events lack final checkpoint coverage".into());
    }
    let last = checkpoints
        .last()
        .ok_or("client scenario requires final checkpoint")?;
    for (alias, definition) in &definitions {
        let trace = &traces[alias];
        final_attempt(definition, trace)?;
        let snapshot = last["attempts"]
            .as_array()
            .expect("schema snapshots")
            .iter()
            .find(|snapshot| snapshot["id"] == definition["id"])
            .ok_or("missing final attempt checkpoint")?;
        if snapshot["phase"] != definition["phase"]
            || snapshot["terminal"]["kind"] != definition["result"]["kind"]
        {
            return Err("client final checkpoint and terminal result differ".into());
        }
        if definition["result"]["kind"] != "construction-refused"
            && snapshot["terminal"]["cleanup"] != definition["result"]["cleanup"]
        {
            return Err("client final cleanup checkpoints differ".into());
        }
    }
    let mut output = value.clone();
    output["events"] = Value::Array(events);
    for checkpoint in output["checkpoints"]
        .as_array_mut()
        .expect("schema checkpoints")
    {
        match checkpoint["actionResult"]["kind"]
            .as_str()
            .expect("schema action result")
        {
            "archive" => {
                let archive = &mut checkpoint["actionResult"]["archive"];
                let encoded =
                    super::artifacts::integer(&archive["encodedByteLength"], 134_217_728)?;
                if encoded < 22 {
                    return Err("client archive lacks a ZIP envelope".into());
                }
                archive
                    .as_object_mut()
                    .expect("schema archive")
                    .remove("encodedByteLength");
                for file in archive["entries"].as_array().expect("schema entries") {
                    measured(&file["bytes"], 16_777_216)?;
                }
            }
            "download" => {
                for file in checkpoint["actionResult"]["files"]
                    .as_array()
                    .expect("schema download")
                {
                    measured(&file["bytes"], 16_777_216)?;
                }
            }
            "published" => {
                for view in checkpoint["actionResult"]["artifacts"]
                    .as_array()
                    .expect("schema views")
                {
                    text_measurement(&view["content"], 65_536)?;
                    if !view["binaryPreview"].is_null() {
                        measured(&view["binaryPreview"], 65_536)?;
                    }
                }
            }
            "refused" => {
                if checkpoint["actionResult"]["message"]
                    .as_str()
                    .expect("schema refusal")
                    .encode_utf16()
                    .count()
                    > 512
                {
                    return Err("client refusal message exceeds UTF16 bound".into());
                }
                checkpoint["actionResult"]
                    .as_object_mut()
                    .expect("schema refusal")
                    .remove("message");
            }
            "none" => {}
            _ => unreachable!("closed action result"),
        }
    }
    // UI prose remains complete in the saved observation. Machine-readable
    // reason/operation/outcome/cleanup carries compatibility meaning. Remote
    // RPC messages remain wire data and are deliberately not removed.
    for attempt in output["attempts"].as_array_mut().expect("schema attempts") {
        if let Some(failure) = attempt["result"].get_mut("failure")
            && failure["kind"] == "other"
        {
            failure
                .as_object_mut()
                .expect("schema generic failure")
                .remove("message");
        }
    }
    canonical_numbers(&mut output, false)?;
    super::contract::encoded_size(&output, MAX_DERIVED_BYTES)?;
    Ok(output)
}

/// Evidence counters and protocol metadata are exact mathematical integers.
/// Caller IR/options, by contrast, enter a JavaScript Json API whose numeric
/// values are finite IEEE-754 Numbers. Never apply that conversion to offsets,
/// revisions, RPC codes, or other literal-aware protocol metadata.
fn canonical_numbers(value: &mut Value, caller_json: bool) -> Result<(), String> {
    match value {
        Value::Number(_) if caller_json => {
            let number = value
                .as_f64()
                .filter(|number| number.is_finite())
                .ok_or("nonfinite caller JSON number")?;
            *value = if number == 0.0 {
                serde_json::json!(0)
            } else {
                serde_json::json!(number)
            };
        }
        Value::Number(_) => {
            *value = serde_json::json!(super::artifacts::integer(value, usize::MAX)?)
        }
        Value::Array(items) => {
            for item in items {
                canonical_numbers(item, caller_json)?;
            }
        }
        Value::Object(members) => {
            let generate = !caller_json
                && members
                    .get("method")
                    .is_some_and(|method| method == "morphir.artifacts.generate");
            for (key, child) in members {
                if !caller_json && key == "rpcCode" {
                    *child = serde_json::json!(super::artifacts::signed_rpc_code(child)?);
                } else if generate && key == "params" {
                    for (field, parameter) in child
                        .as_object_mut()
                        .ok_or("generation parameters must be an object")?
                    {
                        if field == "generation" {
                            for (field, operand) in parameter
                                .as_object_mut()
                                .ok_or("generation must be an object")?
                            {
                                canonical_numbers(
                                    operand,
                                    matches!(field.as_str(), "ir" | "options"),
                                )?;
                            }
                        } else {
                            canonical_numbers(parameter, false)?;
                        }
                    }
                } else {
                    canonical_numbers(child, caller_json)?;
                }
            }
        }
        _ => {}
    }
    Ok(())
}

#[cfg(test)]
mod shared_runner_tests {
    use super::super::*;
    use serde_json::{Value, json};
    fn kit() -> std::path::PathBuf {
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../spec/workbench/mck/draft.28/client")
    }
    struct AuthoredInfrastructure(std::collections::VecDeque<Value>);
    impl Testee for AuthoredInfrastructure {
        fn exchange(&mut self, request: &Value) -> Result<Value, String> {
            assert!(request.get("expected").is_none() && request.get("caseId").is_none());
            if request["op"] == "capabilities" {
                Ok(
                    json!({"suite":"workbench","contractVersion":"0.1.0-draft.28","binding":"checker-infrastructure-only","language":"rust","operations":["artifact-client"],"formats":["json"]}),
                )
            } else {
                self.0
                    .pop_front()
                    .ok_or("missing authored observation".into())
            }
        }
    }
    /// This only qualifies shared-checker infrastructure against fixed authored
    /// evidence. It is not a production adapter or client compatibility claim.
    #[test]
    fn independently_authored_client_kit_checks_and_saved_evidence_rejects_forgery() {
        let corpus = load(&kit()).unwrap();
        assert_eq!(corpus.case_count(), 102);
        let answers = corpus
            .cases
            .iter()
            .map(|case| serde_json::to_value(&case.expected).unwrap())
            .collect();
        let report = execute(&corpus, &mut AuthoredInfrastructure(answers));
        assert!(report.qualified, "{:?}", report.errors);
        let saved = Report::from_json(&report.to_json()).unwrap();
        check_report(&kit(), &saved).unwrap();
        for (pointer, bad) in [
            ("/qualified", json!(false)),
            ("/records/0/result", json!("fail")),
            (
                "/records/0/observed/value/attempts/0/result/inventory/0/bytes/sha256",
                json!("0".repeat(64)),
            ),
            (
                "/records/0/observed/value/checkpoints/10/actionResult/archive/entries/0/bytes/sha256",
                json!("0".repeat(64)),
            ),
            (
                "/records/0/observed/value/checkpoints/8/actionResult/artifacts/0/reference/views",
                json!("foreign"),
            ),
            (
                "/records/0/observed/value/checkpoints/13/eventCount",
                json!(12),
            ),
        ] {
            let mut forged = serde_json::to_value(&saved).unwrap();
            *forged.pointer_mut(pointer).unwrap() = bad;
            let result = Report::from_json(&forged.to_string())
                .and_then(|report| check_report(&kit(), &report));
            assert!(result.is_err(), "{pointer}");
        }
    }
    #[test]
    fn scoped_client_capability_cannot_claim_server_or_another_draft() {
        let caps = json!({"suite":"workbench","contractVersion":"0.1.0-draft.28","binding":"independent-client","language":"typescript","operations":["artifact-client"],"formats":["json"]});
        let parsed = Capabilities::parse(caps.clone(), "0.1.0-draft.28").unwrap();
        assert!(parsed.supports(Operation::ArtifactClient, Format::Json));
        assert!(!parsed.supports(Operation::ArtifactServer, Format::Json));
        assert!(Capabilities::parse(caps, "0.1.0-draft.27").is_err());
    }
    #[test]
    fn client_corpus_loader_preserves_nested_literal_caller_maps() {
        let file = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../spec/workbench/mck/draft.28/client/cases.json");
        let mut value =
            crate::json::strict::parse_exact(&std::fs::read_to_string(file).unwrap()).unwrap();
        let literal = json!({"$serde_json::private::RawValue":"{\"x\":1,\"x\":2}","nested":{"$serde_json::private::Number":"1"}});
        value["cases"][0]["input"]["attempts"][0]["input"]["ir"] = literal.clone();
        let source =
            &mut value["cases"][0]["expected"]["value"]["events"][4]["argument"]["frame"]["source"];
        let mut request = crate::json::strict::parse_exact(source.as_str().unwrap()).unwrap();
        request["params"]["generation"]["ir"] = literal.clone();
        *source = Value::String(request.to_string());
        let directory = tempfile::tempdir().unwrap();
        std::fs::write(directory.path().join("cases.json"), value.to_string()).unwrap();
        let corpus = load(directory.path()).unwrap();
        assert_eq!(corpus.cases[0].input["attempts"][0]["input"]["ir"], literal);
    }
}

fn same_json_number_model(left: &Value, right: &Value) -> bool {
    match (left, right) {
        (Value::Number(a), Value::Number(b)) => a
            .as_f64()
            .zip(b.as_f64())
            .is_some_and(|(a, b)| a.is_finite() && b.is_finite() && a == b),
        (Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b).all(|(a, b)| same_json_number_model(a, b))
        }
        (Value::Object(a), Value::Object(b)) => {
            a.len() == b.len()
                && a.iter()
                    .all(|(key, a)| b.get(key).is_some_and(|b| same_json_number_model(a, b)))
        }
        _ => left == right,
    }
}
fn same_context(left: &Value, right: &Value) -> Result<bool, String> {
    if left.is_null() || right.is_null() {
        return Ok(left.is_null() && right.is_null());
    }
    Ok(left["sourceId"] == right["sourceId"]
        && super::artifacts::integer(&left["revision"], 2_147_483_647)?
            == super::artifacts::integer(&right["revision"], 2_147_483_647)?
        && super::artifacts::integer(&left["epoch"], 2_147_483_647)?
            == super::artifacts::integer(&right["epoch"], 2_147_483_647)?)
}
fn replace_local_value(caller: &mut Value, recipe: &Value) -> Result<(), String> {
    let field = recipe["field"].as_str().expect("schema local field");
    let mut target = &mut caller[field];
    for step in recipe["path"].as_array().expect("schema path") {
        target = if step["kind"] == "member" {
            target
                .as_object_mut()
                .and_then(|object| object.get_mut(step["key"].as_str().expect("schema path key")))
        } else {
            let index = super::artifacts::integer(&step["index"], 2_147_483_647)?;
            target.as_array_mut().and_then(|array| array.get_mut(index))
        }
        .ok_or("local value path does not exist")?;
    }
    let byte = super::artifacts::integer(&recipe["byte"], 127)? as u8;
    let count = super::artifacts::integer(&recipe["count"], 1_048_577)?;
    *target = Value::String(std::iter::repeat_n(char::from(byte), count).collect());
    Ok(())
}
fn sorted_files(files: &[Value]) -> Result<Vec<Value>, String> {
    super::artifacts::portable_paths(files)?;
    let mut files = files.to_vec();
    files.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    Ok(files)
}
/// Reconcile observed context, caller capture and registry operations against the
/// authored action script. This is an invariant checker, not a reimplementation
/// of the client decoder or an expected-output generator.
pub(super) fn validate_for_input(input: &Value, evidence: &Value) -> Result<(), String> {
    validate_input(input)?;
    let normalized = projection(evidence)?;
    let mut canonical_evidence = evidence.clone();
    canonical_numbers(&mut canonical_evidence, false)?;
    let evidence = &canonical_evidence;
    let definitions = input["attempts"]
        .as_array()
        .expect("schema attempts")
        .iter()
        .map(|definition| (definition["id"].as_str().expect("schema alias"), definition))
        .collect::<BTreeMap<_, _>>();
    let actual = evidence["attempts"]
        .as_array()
        .expect("schema evidence attempts")
        .iter()
        .map(|attempt| (attempt["id"].as_str().expect("schema alias"), attempt))
        .collect::<BTreeMap<_, _>>();
    if definitions.keys().ne(actual.keys()) {
        return Err("client evidence definition inventory differs".into());
    }
    let mut callers = definitions
        .iter()
        .map(|(id, definition)| (*id, definition["input"].clone()))
        .collect::<BTreeMap<_, _>>();
    let mut captured_callers = BTreeMap::new();
    let mut first_terminals = BTreeSet::new();
    let mut current = Value::Null;
    let mut published: BTreeMap<String, (&Value, Vec<Value>)> = BTreeMap::new();
    let mut registry: Option<String> = None;
    let actions = input["actions"].as_array().expect("schema actions");
    let checkpoints = evidence["checkpoints"]
        .as_array()
        .expect("schema checkpoints");
    if actions.len() != checkpoints.len() {
        return Err("client checkpoint inventory differs from action script".into());
    }
    for (action, checkpoint) in actions.iter().zip(checkpoints) {
        let kind = action["action"].as_str().expect("schema action");
        match kind {
            "set-current" => current = action["context"].clone(),
            "replace-caller" => {
                let id = action["attempt"].as_str().expect("schema alias");
                let field = action["field"].as_str().expect("schema field");
                callers.get_mut(id).expect("validated reference")[field] = action["value"].clone();
            }
            "start" => {
                let id = action["attempt"].as_str().expect("schema alias");
                let definition = definitions[id];
                let mut caller = callers[id].clone();
                local_value_work(definition)?;
                for recipe in definition
                    .get("localValues")
                    .and_then(Value::as_array)
                    .into_iter()
                    .flatten()
                {
                    replace_local_value(&mut caller, recipe)?;
                }
                captured_callers.insert(id, caller);
                if !definition["localFaults"]
                    .as_array()
                    .expect("schema faults")
                    .is_empty()
                    && actual[id]["result"]["kind"] != "construction-refused"
                {
                    return Err("invalid local scalar escaped construction".into());
                }
            }
            "clear-registry" => registry = None,
            _ => {}
        }
        if !same_context(&current, &checkpoint["currentContext"])? {
            return Err("client current context differs from authored actions".into());
        }
        if kind == "observe" {
            if checkpoint["label"] != action["label"] {
                return Err("client observation label differs from action".into());
            }
        } else if !checkpoint["label"].is_null() {
            return Err("client action acquired an unauthored observation label".into());
        }
        for snapshot in checkpoint["attempts"].as_array().expect("schema snapshots") {
            let id = snapshot["id"].as_str().expect("schema alias");
            if !captured_callers.contains_key(id) {
                if snapshot["phase"] != "not-started" {
                    return Err("client evidence started an unauthored attempt".into());
                }
                continue;
            }
            let terminal = snapshot["terminal"]["kind"]
                .as_str()
                .expect("schema terminal");
            if terminal != "pending" && first_terminals.insert(id) {
                let is_current = same_context(&current, &definitions[id]["context"])?
                    && snapshot["signalAborted"] != true;
                if terminal != "construction-refused" && ((terminal == "discarded") == is_current) {
                    return Err(
                        "client terminal publication escaped current-attempt reconciliation".into(),
                    );
                }
            }
        }
        let result = &checkpoint["actionResult"];
        if kind == "publish" {
            let id = action["attempt"].as_str().expect("schema alias");
            let snapshot = checkpoint["attempts"]
                .as_array()
                .expect("schema snapshots")
                .iter()
                .find(|snapshot| snapshot["id"] == id)
                .expect("validated inventory");
            if snapshot["terminal"]["kind"] == "verified" {
                let views = action["views"].as_str().expect("schema views");
                if result["kind"] != "published" || result["views"] != views {
                    return Err("verified owner publication lacks actual view evidence".into());
                }
                let owner = &actual[id]["result"];
                let inventory = owner["inventory"].as_array().expect("schema inventory");
                let output = result["artifacts"]
                    .as_array()
                    .expect("schema view evidence");
                if output.len() != inventory.len() {
                    return Err("published views differ from owner inventory".into());
                }
                let limit = 65_536.min(1_048_576 / inventory.len().max(1));
                for (file, view) in inventory.iter().zip(output) {
                    if view["file"] != file["id"]
                        || view["path"] != file["path"]
                        || view["binary"] != (file["declaredKind"] == "binary")
                        || view["byteLength"] != file["bytes"]["byteLength"]
                        || view["reference"]["views"] != views
                        || view["reference"]["file"] != file["id"]
                    {
                        return Err("published view reference escaped actual owner".into());
                    }
                    text_measurement(&view["content"], limit.max(128))?;
                    if !view["binaryPreview"].is_null() {
                        measured(&view["binaryPreview"], limit)?;
                    }
                }
                published.insert(views.into(), (owner, output.clone()));
                registry = Some(views.into());
            } else if result["kind"] != "refused" || result["operation"] != "publish" {
                return Err("unverified attempt acquired downloadable views".into());
            }
        } else if matches!(kind, "download" | "archive") {
            let selection = &action["views"];
            let selected = selection["views"].as_str().expect("schema views");
            let (source_owner, source_views) = published
                .get(selected)
                .ok_or("selection has no actual published views")?;
            let _ = source_owner;
            let mut requested = Vec::new();
            let mut valid = true;
            for index in selection["indices"].as_array().expect("schema indices") {
                if let Some(view) = source_views.get(super::artifacts::integer(index, 256)?) {
                    requested.push(view.clone());
                } else {
                    valid = false;
                }
            }
            for mutation in selection["mutations"].as_array().expect("schema mutations") {
                if let Some(view) =
                    requested.get_mut(super::artifacts::integer(&mutation["index"], 256)?)
                {
                    if mutation["kind"] == "path" {
                        view["path"] = mutation["path"].clone();
                    } else {
                        let from = mutation["fromViews"].as_str().expect("schema reference");
                        let index = super::artifacts::integer(&mutation["fromIndex"], 256)?;
                        if let Some((_, views)) = published.get(from) {
                            if let Some(reference) = views.get(index) {
                                view["reference"] = reference["reference"].clone();
                            } else {
                                valid = false;
                            }
                        } else {
                            valid = false;
                        }
                    }
                } else {
                    valid = false;
                }
            }
            let mut expected_files = Vec::new();
            let mut seen = BTreeSet::new();
            if let Some((owner, _)) = registry.as_ref().and_then(|current| published.get(current)) {
                let inventory = owner["inventory"].as_array().expect("schema owner");
                let complete = kind == "archive" || action["complete"] == true;
                if requested.is_empty()
                    || requested.len() != if complete { inventory.len() } else { 1 }
                {
                    valid = false;
                }
                for view in requested {
                    let id = view["reference"]["file"]
                        .as_str()
                        .expect("schema file alias");
                    if Some(
                        view["reference"]["views"]
                            .as_str()
                            .expect("schema view reference"),
                    ) != registry.as_deref()
                        || !seen.insert(id.to_owned())
                    {
                        valid = false;
                    }
                    if let Some(file) = inventory.iter().find(|file| file["id"] == id) {
                        if view["path"] != file["path"] {
                            valid = false;
                        }
                        expected_files
                            .push(serde_json::json!({"path":file["path"],"bytes":file["bytes"]}));
                    } else {
                        valid = false;
                    }
                }
            } else {
                valid = false;
            }
            if valid {
                if result["kind"] != kind {
                    return Err("valid registry selection lost original bytes".into());
                }
                let files = if kind == "archive" {
                    result["archive"]["entries"]
                        .as_array()
                        .expect("schema archive")
                } else {
                    result["files"].as_array().expect("schema download")
                };
                if sorted_files(files)? != sorted_files(&expected_files)? {
                    return Err("download or ZIP entries differ from private owner bytes".into());
                }
            } else if result["kind"] != "refused" || result["operation"] != kind {
                return Err("invalid or stale registry selection exposed original bytes".into());
            }
        } else if result["kind"] != "none" && kind != "mutate-copy" {
            return Err("client action returned unrelated publication evidence".into());
        }
        let wanted_registry = registry.as_ref().map_or_else(
            || serde_json::json!({"kind":"empty"}),
            |views| serde_json::json!({"kind":"published","views":views}),
        );
        if checkpoint["registry"] != wanted_registry {
            return Err(
                "client registry transition differs from explicit publish/clear actions".into(),
            );
        }
    }
    for (id, definition) in &definitions {
        let observed = actual[id];
        if !observed["capture"].is_null() {
            for field in ["sessionId", "target", "irVersion"] {
                if observed["capture"][field] != definition["input"][field] {
                    return Err("client capture differs from original metadata".into());
                }
            }
            if observed["capture"]["providerId"] != definition["offer"]["id"] {
                return Err("client capture differs from selected provider".into());
            }
        }
    }
    for event in normalized["events"].as_array().expect("projected events") {
        if event["kind"] == "effect" && event["effect"] == "generate" {
            let id = event["attempt"].as_str().expect("schema alias");
            let expected = captured_callers
                .get(id)
                .ok_or("generation preceded source capture")?;
            let generation = &event["argument"]["request"]["params"]["generation"];
            if !same_json_number_model(&generation["ir"], &expected["ir"])
                || !same_json_number_model(&generation["options"], &expected["options"])
            {
                return Err("client generation changed captured literal caller input".into());
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod client_boundary_regressions {
    use super::super::contract::{Observation, Operation};
    use super::*;
    use serde_json::{Value, json};
    fn case(id: &str) -> Value {
        crate::json::strict::parse_exact(include_str!(
            "../../../../spec/workbench/mck/draft.28/client/cases.json"
        ))
        .unwrap()["cases"]
            .as_array()
            .unwrap()
            .iter()
            .find(|case| case["id"] == id)
            .unwrap()
            .clone()
    }
    #[test]
    fn local_faults_require_existing_sequential_shapes_before_adapter_work() {
        let original = case("client-local-unicode-ir-value-high")["input"].clone();
        for path in [
            json!([{"kind":"member","key":"missing"}]),
            json!([{"kind":"index","index":999}]),
        ] {
            let mut value = original.clone();
            value["attempts"][0]["localFaults"][0]["path"] = path;
            assert!(validate_input(&value).is_err(), "missing path");
        }
        let mut value = original.clone();
        value["attempts"][0]["localFaults"][0]["kind"] = json!("unpaired-surrogate-key");
        value["attempts"][0]["localFaults"][0]["path"] = json!([]);
        assert!(validate_input(&value).is_err(), "root key fault");
        let mut value = original.clone();
        value["attempts"][0]["input"]["ir"] = json!({"present":{"child":1}});
        value["attempts"][0]["localFaults"] = json!([
            {"kind":"unpaired-surrogate-value","field":"ir","path":[{"kind":"member","key":"present"}],"unit":"high"},
            {"kind":"unpaired-surrogate-value","field":"ir","path":[{"kind":"member","key":"present"},{"kind":"member","key":"child"}],"unit":"low"}
        ]);
        assert!(
            validate_input(&value).is_err(),
            "earlier scalar replacement"
        );
        value["attempts"][0]["localFaults"][0]["kind"] = json!("unpaired-surrogate-key");
        assert!(validate_input(&value).is_err(), "earlier removed key");
    }
    #[test]
    fn canonical_peer_reply_expansion_has_its_own_preallocation_budget() {
        let mut value = case("client-request-one-mib-oneover")["input"].clone();
        value["attempts"][0]["localValues"] = json!([]);
        value["actions"] = json!([
            {"action":"start","attempt":"A"},
            {"action":"drain-reads","attempt":"A","maxReads":2048}
        ]);
        assert!(
            validate_input(&value).is_err(),
            "canonical base64 expansion exceeds128MiB before allocation"
        );
    }
    #[test]
    fn local_path_validation_respects_caller_replacement_and_scalar_recipe_order() {
        let mut value = case("client-local-unicode-ir-value-high")["input"].clone();
        value["attempts"][0]["input"]["ir"] = json!({"old":1});
        value["attempts"][0]["localFaults"] = json!([{"kind":"unpaired-surrogate-value","field":"ir","path":[{"kind":"member","key":"new"},{"kind":"member","key":"child"}],"unit":"high"}]);
        value["actions"].as_array_mut().unwrap().insert(1, json!({"action":"replace-caller","attempt":"A","field":"ir","value":{"new":{"child":1}}}));
        validate_input(&value).unwrap();
        value["attempts"][0]["localValues"] = json!([{"kind":"repeat-ascii-value","field":"ir","path":[{"kind":"member","key":"new"}],"byte":97,"count":1_048_577}]);
        assert!(
            validate_input(&value).is_err(),
            "local recipe removes child before faults, without expansion"
        );
        value["attempts"][0]["localFaults"][0]["path"] = json!([{"kind":"member","key":"new"}]);
        validate_input(&value).unwrap();
        value["attempts"][0]["localValues"][0]["path"] = json!([{"kind":"member","key":"missing"}]);
        assert!(
            validate_input(&value).is_err(),
            "local value recipe path must exist too"
        );
    }
    #[test]
    fn local_value_work_counts_json_escaping_and_rejects_aggregate_before_expansion() {
        let mut value = case("client-request-one-mib-oneover")["input"].clone();
        for (byte, width) in [(0, 6), (8, 2), (10, 2), (34, 2), (92, 2), (97, 1), (127, 1)] {
            value["attempts"][0]["localValues"][0]["count"] = json!(1_048_577);
            value["attempts"][0]["localValues"][0]["byte"] = json!(byte);
            let budget = validate_input(&value).unwrap();
            assert_eq!(budget.decoded_and_reads.0, 1_048_577);
            assert_eq!(budget.raw_frames.0, 1_048_577 * width);
        }
        let second = value["attempts"][0]["localValues"][0].clone();
        value["attempts"][0]["localValues"]
            .as_array_mut()
            .unwrap()
            .push(second);
        assert!(validate_input(&value).unwrap_err().contains("aggregate"));
        value["attempts"][0]["localValues"] = json!([{"kind":"repeat-ascii-value","field":"options","path":[],"byte":97,"count":1_048_578}]);
        assert!(validate_input(&value).is_err());
    }
    #[test]
    fn complete_one_mib_frame_has_separate_finite_derived_projection_budget() {
        let value = case("client-request-one-mib-exact");
        validate_for_input(&value["input"], &value["expected"]["value"]).unwrap();
        let projected = projection(&value["expected"]["value"]).unwrap();
        assert!(serde_json::to_vec(&projected).unwrap().len() > 1_048_576);
        let mut budget = DerivedProjectionBudget::new(1_048_576).unwrap();
        budget.reserve_frame(7 * 1_048_576).unwrap();
        assert!(budget.reserve_frame(1).is_err());
    }
    #[test]
    fn ui_explanation_normalization_preserves_typed_failures_and_remote_messages() {
        for id in [
            "client-rejected-connect",
            "client-registry-renamed-path-refusal",
        ] {
            let value = case(id);
            let expected = Observation::parse(value["expected"].clone()).unwrap();
            let mut changed = value["expected"].clone();
            if id == "client-rejected-connect" {
                changed["value"]["attempts"][0]["result"]["failure"]["message"] =
                    json!("Another bounded UI explanation.");
            } else {
                for checkpoint in changed["value"]["checkpoints"].as_array_mut().unwrap() {
                    if checkpoint["actionResult"]["kind"] == "refused" {
                        checkpoint["actionResult"]["message"] =
                            json!("Another bounded UI explanation.");
                    }
                }
            }
            assert!(
                expected
                    .matches(
                        &Observation::parse(changed).unwrap(),
                        Operation::ArtifactClient
                    )
                    .unwrap()
            );
        }
        for id in [
            "client-local-unicode-ir-value-high",
            "client-manifest-duplicate-member",
            "client-digest-wrong-32",
        ] {
            let value = case(id);
            let expected = Observation::parse(value["expected"].clone()).unwrap();
            let mut changed = value["expected"].clone();
            changed["value"]["attempts"][0]["result"]["failure"] = json!({"kind":"other","message":"A generic error cannot stand in for a typed failure."});
            assert!(
                !expected
                    .matches(
                        &Observation::parse(changed).unwrap(),
                        Operation::ArtifactClient
                    )
                    .unwrap()
            );
        }
        let value = case("client-remote-error-exact-code-message");
        let expected = Observation::parse(value["expected"].clone()).unwrap();
        let mut changed = value["expected"].clone();
        changed["value"]["attempts"][0]["result"]["failure"]["failure"]["message"] =
            json!("Different remote wire data.");
        assert!(
            !expected
                .matches(
                    &Observation::parse(changed).unwrap(),
                    Operation::ArtifactClient
                )
                .unwrap()
        );
    }
    #[test]
    fn authored_actions_bind_current_context_registry_and_original_caller() {
        let value = case("client-captures-caller-before-connect");
        for pointer in [
            "/checkpoints/0/currentContext/revision",
            "/checkpoints/1/currentContext/epoch",
        ] {
            let mut changed = value["expected"]["value"].clone();
            *changed.pointer_mut(pointer).unwrap() = json!(99);
            assert!(validate_for_input(&value["input"], &changed).is_err());
        }
        let value = case("client-registry-clear-refuses-old-download-and-zip");
        let mut changed = value["expected"]["value"].clone();
        let checkpoint = changed["checkpoints"]
            .as_array_mut()
            .unwrap()
            .iter_mut()
            .rev()
            .find(|item| item["registry"]["kind"] == "empty")
            .unwrap();
        checkpoint["registry"] = json!({"kind":"published","views":"views-A"});
        assert!(validate_for_input(&value["input"], &changed).is_err());
    }
}

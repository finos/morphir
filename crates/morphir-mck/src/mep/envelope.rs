//! Complete successful model-envelope admission, including optional evidence.
use super::{binary, decode_payload, require};
use ion_rs::Element;
use serde_json::Value;

const CRITICAL: &[&str] = &[
    "envelopeVersion",
    "modelId",
    "revision",
    "irVersion",
    "profile",
    "payload",
    "payload.codec",
    "payload.layout",
    "payload.decodedByteLength",
    "payload.sha256",
    "payload.content",
    "evidence",
    "critical",
];

#[derive(Default)]
struct Budget {
    encoded: usize,
    decoded: usize,
    nodes: usize,
}
enum Decoded {
    Ion(Element),
    Json,
}

impl Budget {
    fn payload(&mut self, payload: &Value) -> Result<Decoded, String> {
        let encoded = payload["content"]
            .as_str()
            .ok_or("payload content missing")?
            .len();
        let decoded = payload["decodedByteLength"]
            .as_u64()
            .and_then(|n| usize::try_from(n).ok())
            .ok_or("decoded payload length must be an integer")?;
        self.encoded = self
            .encoded
            .checked_add(encoded)
            .ok_or("aggregate encoded payload overflow")?;
        self.decoded = self
            .decoded
            .checked_add(decoded)
            .ok_or("aggregate decoded payload overflow")?;
        require(
            self.encoded <= 1000000 && self.decoded <= 750000,
            "aggregate model and evidence payload exceeds negotiated bounds",
        )?;
        let bytes = decode_payload(payload)?;
        let remaining = 100000usize.saturating_sub(self.nodes);
        let (value, nodes) = match payload["codec"].as_str() {
            Some("ion-binary") => {
                let (value, nodes) = binary::read_counted(&bytes, remaining)?;
                (Decoded::Ion(value), nodes)
            }
            Some("morphir-json") => {
                let text = std::str::from_utf8(&bytes).map_err(|_| "evidence JSON is not UTF-8")?;
                let value = crate::json::strict::parse_exact(text)?;
                let nodes = json_nodes(&value, remaining)?;
                (Decoded::Json, nodes)
            }
            _ => return Err("unsupported evidence payload codec".into()),
        };
        self.nodes += nodes;
        Ok(value)
    }
}

fn json_nodes(root: &Value, max: usize) -> Result<usize, String> {
    let mut pending = vec![(root, 1)];
    let mut nodes = 0;
    while let Some((value, depth)) = pending.pop() {
        nodes += 1;
        require(
            depth <= 128 && nodes <= max,
            "aggregate model and evidence structural limit exceeded",
        )?;
        match value {
            Value::Object(fields) => pending.extend(fields.values().map(|v| (v, depth + 1))),
            Value::Array(values) => pending.extend(values.iter().map(|v| (v, depth + 1))),
            _ => {}
        }
    }
    Ok(nodes)
}

fn nonempty<'a>(value: &'a Value, key: &str) -> Result<&'a str, String> {
    value[key]
        .as_str()
        .filter(|s| !s.trim().is_empty())
        .ok_or_else(|| format!("evidence {key} must be a nonempty string"))
}

pub(super) fn validate(model: &Value, context: &str) -> Result<Element, String> {
    if let Some(critical) = model.get("critical") {
        for path in critical.as_array().ok_or("critical must be an array")? {
            let path = path.as_str().ok_or("critical path must be a string")?;
            if !CRITICAL.contains(&path) {
                return Err(format!("unknown critical model path: {path}"));
            }
        }
    }
    let mut budget = Budget::default();
    let root = match budget.payload(&model["payload"])? {
        Decoded::Ion(root) => root,
        Decoded::Json => return Err("compiled model must use Ion".into()),
    };
    if let Some(evidence) = model.get("evidence") {
        for evidence in evidence.as_array().ok_or("evidence must be an array")? {
            let guarantee = nonempty(evidence, "guarantee")?;
            require(
                guarantee.contains(':'),
                "evidence guarantee must be namespaced",
            )?;
            for key in [
                "modelId",
                "modelRevision",
                "contextDigest",
                "scope",
                "producer",
            ] {
                nonempty(evidence, key)?;
            }
            require(
                evidence["modelId"] == model["modelId"]
                    && evidence["modelRevision"] == model["revision"]
                    && evidence["contextDigest"] == context,
                "evidence model/revision/context mismatch",
            )?;
            budget.payload(&evidence["evidence"])?;
        }
    }
    Ok(root)
}

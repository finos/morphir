//! A private transitional boundary until devkit publishes the typed accessor.
//! RawValue protects opaque extras from secondary Value deserialization and
//! preserves duplicate declaration evidence. Historical TaskResult is untouched.
use super::domain::*;
use morphir_devkit::IrDescriptor;
use morphir_distribution::Sha256Digest;
use serde::{
    Deserialize, Deserializer,
    de::{MapAccess, Visitor},
};
use serde_json::{Value, value::RawValue};
use std::{collections::BTreeMap, fmt};

struct RawRecord<'a>(BTreeMap<String, &'a RawValue>);
impl<'de> Deserialize<'de> for RawRecord<'de> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct Fields;
        impl<'de> Visitor<'de> for Fields {
            type Value = RawRecord<'de>;
            fn expecting(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str("compile record object")
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let mut fields = BTreeMap::new();
                while let Some(key) = map.next_key::<String>()? {
                    let value = map.next_value::<&RawValue>()?;
                    if fields.insert(key, value).is_some() {
                        return Err(serde::de::Error::custom("duplicate compile record member"));
                    }
                }
                Ok(RawRecord(fields))
            }
        }
        deserializer.deserialize_map(Fields)
    }
}

pub(super) fn decode(
    raw: Vec<u8>,
    module: &SelectedModule,
    scope: CaptureScope,
) -> Result<(CapturedRecord, Declaration), CaptureError> {
    let fields: RawRecord<'_> =
        serde_json::from_slice(&raw).map_err(|_| CaptureError::InvalidRecord)?;
    fn get<'a, T: Deserialize<'a>>(
        fields: &BTreeMap<String, &'a RawValue>,
        key: &str,
    ) -> Result<T, CaptureError> {
        serde_json::from_str(fields.get(key).ok_or(CaptureError::InvalidRecord)?.get())
            .map_err(|_| CaptureError::InvalidRecord)
    }
    let schema: u32 = get(&fields.0, "schema")?;
    let task: String = get(&fields.0, "task")?;
    let recorded_module: String = get(&fields.0, "module")?;
    let _: String = get(&fields.0, "completedAt")?;
    let tombstone: bool = fields
        .0
        .get("tombstone")
        .map(|value| serde_json::from_str(value.get()))
        .transpose()
        .map_err(|_| CaptureError::InvalidRecord)?
        .unwrap_or(false);
    if schema != 1 || task != "compile" || recorded_module != module.as_str() || tombstone {
        return Err(CaptureError::InvalidRecord);
    }
    // Decode a closed descriptor through the duplicate-aware boundary before
    // decoding its scalar typed fields. Unknown extras never enter Value.
    let descriptor_raw = fields.0.get("ir").ok_or(CaptureError::InvalidRecord)?.get();
    let descriptor_value = morphir_mck::json::parse_exact_document(descriptor_raw)
        .map_err(|_| CaptureError::InvalidRecord)?;
    let descriptor_fields = descriptor_value
        .as_object()
        .ok_or(CaptureError::InvalidRecord)?;
    if descriptor_fields.len() != 4
        || ["path", "layout", "format", "version"]
            .iter()
            .any(|key| !descriptor_fields.contains_key(*key))
    {
        return Err(CaptureError::InvalidRecord);
    }
    let descriptor = CapturedDescriptor::parse(
        serde_json::from_str::<IrDescriptor>(descriptor_raw)
            .map_err(|_| CaptureError::InvalidRecord)?,
    )?;
    let declaration = if scope == CaptureScope::Primary {
        Declaration::Absent
    } else {
        fields
            .0
            .get("morphirModelOriginals")
            .map_or(Declaration::Absent, |value| {
                declaration(value.get()).unwrap_or(Declaration::Invalid)
            })
    };
    Ok((
        CapturedRecord {
            digest: Sha256Digest::of_bytes(&raw),
            byte_length: raw.len(),
            module: module.clone(),
            descriptor,
        },
        declaration,
    ))
}

fn declaration(raw: &str) -> Result<Declaration, CaptureError> {
    let value = morphir_mck::json::parse_exact_document(raw)
        .map_err(|_| CaptureError::InvalidDeclaration)?;
    let fields = value.as_object().ok_or(CaptureError::InvalidDeclaration)?;
    if fields.len() != 2
        || fields.get("contractVersion").and_then(Value::as_str) != Some(CONTRACT_VERSION)
    {
        return Err(CaptureError::InvalidDeclaration);
    }
    let roots = fields
        .get("companions")
        .and_then(Value::as_array)
        .ok_or(CaptureError::InvalidDeclaration)?;
    if roots.len() >= MAX_ROOTS {
        return Err(CaptureError::InvalidDeclaration);
    }
    let roots = roots
        .iter()
        .map(|value| {
            let fields = value.as_object().ok_or(CaptureError::InvalidDeclaration)?;
            if fields.len() != 2 {
                return Err(CaptureError::InvalidDeclaration);
            }
            let kind = match fields.get("kind").and_then(Value::as_str) {
                Some("file") => SourceKind::File,
                Some("directory") => SourceKind::Directory,
                _ => return Err(CaptureError::InvalidDeclaration),
            };
            let path = SourcePath::parse(
                fields
                    .get("path")
                    .and_then(Value::as_str)
                    .ok_or(CaptureError::InvalidDeclaration)?,
            )
            .map_err(|_| CaptureError::InvalidDeclaration)?;
            SourceRoot::new(kind, path).map_err(|_| CaptureError::InvalidDeclaration)
        })
        .collect::<Result<_, _>>()?;
    Ok(Declaration::Declared(roots))
}

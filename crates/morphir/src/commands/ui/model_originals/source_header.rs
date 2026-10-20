//! Header evidence from captured primary bytes, separate from semantic support.

use super::SourceFormat;
use morphir_core::format_version::{NormalizedFormatVersion, ScalarValue, default_support_table};
use morphir_core::ir::decode::{
    DecodeBudget, JsonDecodeError, YamlDecodeError, read_json, read_yaml,
};
use serde_json::Value;

/// Physical header recognition does not require a supported semantic decoder.
#[derive(Debug)]
pub(in crate::commands::ui) enum SourceHeader {
    Reported(NormalizedFormatVersion),
    NotReported,
}

/// A failed physical probe is distinct from a successfully parsed absent or
/// invalid header. The caller may retain originals and report `not-reported`;
/// it must not replace this evidence with the storage descriptor's version.
#[derive(Debug, thiserror::Error)]
pub(in crate::commands::ui) enum SourceHeaderError {
    #[error(transparent)]
    Json(JsonDecodeError),
    #[error(transparent)]
    Yaml(YamlDecodeError),
    #[error("A bounded Ion header probe is not available.")]
    BoundedIonProbeUnavailable,
}

/// Inspect already captured primary bytes under the caller's aggregate source
/// budget. This never opens a live path, assembles typed IR, or builds a semantic
/// projection. Parsing the complete physical source prevents a prefix header
/// from making invalid trailing bytes appear valid.
///
/// Published SDK readers provide before-growth value/depth/string checks for
/// JSON and YAML. Ion's current public codec eagerly materializes an Element
/// tree without those hooks; it is deliberately not called here. This explicit
/// unavailable probe supports the profile's `not-reported` evidence case, and
/// does not qualify bounded Ion header recognition.
pub(in crate::commands::ui) fn inspect(
    format: SourceFormat,
    bytes: &[u8],
    budget: &mut DecodeBudget,
) -> Result<SourceHeader, SourceHeaderError> {
    let value = match format {
        SourceFormat::Json => read_json(bytes, budget).map_err(SourceHeaderError::Json)?,
        SourceFormat::Yaml => read_yaml(bytes, budget).map_err(SourceHeaderError::Yaml)?,
        SourceFormat::Ion => return Err(SourceHeaderError::BoundedIonProbeUnavailable),
    };
    Ok(header(&value))
}

fn header(value: &Value) -> SourceHeader {
    // A release has at most three u32 components and two separators. Avoid a
    // second potentially source-sized string copy before normalization. This
    // is a grammar-derived bound, not a new accepted-source quota.
    const MAX_RELEASE_BYTES: usize = 3 * 10 + 2;
    let scalar = match value.get("formatVersion") {
        Some(Value::Number(number)) => number.as_u64().map(ScalarValue::Integer),
        Some(Value::String(text)) if text.len() <= MAX_RELEASE_BYTES => {
            Some(ScalarValue::String(text.clone()))
        }
        _ => None,
    };
    scalar
        .and_then(|scalar| {
            NormalizedFormatVersion::from_scalar(&scalar, &default_support_table()).ok()
        })
        .map_or(SourceHeader::NotReported, SourceHeader::Reported)
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_core::format_version::Compatibility;
    use morphir_core::ir::decode::{DecodeBudget, DecodeLimits, DecodePhase};

    fn budget() -> DecodeBudget {
        DecodeBudget::new(DecodeLimits::model_originals())
    }

    #[test]
    fn actual_json_and_yaml_headers_preserve_release_and_family() {
        for (format, bytes, release, family) in [
            (
                SourceFormat::Json,
                br#"{"formatVersion":4}"#.as_slice(),
                "4.0.0",
                4,
            ),
            (
                SourceFormat::Json,
                br#"{"opaque":[1],"formatVersion":"3.1.0"}"#.as_slice(),
                "3.1.0",
                3,
            ),
            (
                SourceFormat::Yaml,
                b"opaque: [1]\nformatVersion: 4\n".as_slice(),
                "4.0.0",
                4,
            ),
            (
                SourceFormat::Yaml,
                b"formatVersion: '3.1.0'\n".as_slice(),
                "3.1.0",
                3,
            ),
        ] {
            let mut owner = budget();
            let SourceHeader::Reported(header) = inspect(format, bytes, &mut owner).unwrap() else {
                panic!("actual header missing");
            };
            assert_eq!(header.release.to_exact_string(), release);
            assert_eq!(header.release.major(), family);
            assert_eq!(owner.source_bytes(), bytes.len());
            assert_eq!(owner.usage(DecodePhase::Assembled).values(), 0);
        }
    }

    #[test]
    fn recognized_unsupported_major_is_still_source_evidence() {
        for (format, bytes, release) in [
            (
                SourceFormat::Json,
                br#"{"formatVersion":2}"#.as_slice(),
                "2.0.0",
            ),
            (
                SourceFormat::Json,
                br#"{"formatVersion":99}"#.as_slice(),
                "99.0.0",
            ),
            (
                SourceFormat::Yaml,
                b"formatVersion: 2\n".as_slice(),
                "2.0.0",
            ),
            (
                SourceFormat::Yaml,
                b"formatVersion: 99\n".as_slice(),
                "99.0.0",
            ),
        ] {
            let SourceHeader::Reported(header) = inspect(format, bytes, &mut budget()).unwrap()
            else {
                panic!("unsupported evidence was lost");
            };
            assert_eq!(header.release.to_exact_string(), release);
            assert_eq!(header.compatibility, Compatibility::UnsupportedMajor);
        }
    }

    #[test]
    fn invalid_or_missing_header_never_uses_descriptor_version() {
        for bytes in [
            br#"{}"#.as_slice(),
            br#"[]"#,
            br#"{"formatVersion":null}"#,
            br#"{"formatVersion":0}"#,
            br#"{"formatVersion":-1}"#,
            br#"{"formatVersion":1.5}"#,
            br#"{"formatVersion":"04.0.0"}"#,
            br#"{"formatVersion":"4.0.0-preview"}"#,
            br#"{"formatVersion":4294967296}"#,
            br#"{"formatVersion":{"major":4}}"#,
            br#"{"formatVersion":"12345678901234567890123456789012345"}"#,
        ] {
            assert!(matches!(
                inspect(SourceFormat::Json, bytes, &mut budget()).unwrap(),
                SourceHeader::NotReported
            ));
        }
    }

    #[test]
    fn physical_failure_after_header_is_not_accepted_as_evidence() {
        assert!(matches!(
            inspect(
                SourceFormat::Json,
                br#"{"formatVersion":4,"bad":[}"#,
                &mut budget()
            ),
            Err(SourceHeaderError::Json(_))
        ));
        assert!(matches!(
            inspect(
                SourceFormat::Yaml,
                b"formatVersion: 4\nbad: [}\n",
                &mut budget()
            ),
            Err(SourceHeaderError::Yaml(_))
        ));
    }

    #[test]
    fn ion_probe_unavailability_is_explicit_without_eager_decoding() {
        let mut owner = budget();
        assert!(matches!(
            inspect(SourceFormat::Ion, b"{formatVersion:\"4.0.0\"}", &mut owner),
            Err(SourceHeaderError::BoundedIonProbeUnavailable)
        ));
        assert_eq!(owner.source_bytes(), 0);
        assert_eq!(owner.usage(DecodePhase::Source).values(), 0);
    }

    #[test]
    fn bounded_reader_refuses_before_forbidden_child_and_shares_source_owner() {
        let mut owner = DecodeBudget::new(DecodeLimits::new(128, 1, 3, 64).unwrap());
        inspect(SourceFormat::Json, br#"{"formatVersion":4}"#, &mut owner).unwrap();
        assert_eq!(owner.usage(DecodePhase::Source).values(), 2);
        assert!(matches!(
            inspect(SourceFormat::Yaml, b"formatVersion: 4\n", &mut owner),
            Err(SourceHeaderError::Yaml(_))
        ));
        assert_eq!(owner.usage(DecodePhase::Source).values(), 3);
        let bytes = br#"{"formatVersion":4}"#;
        let mut small = DecodeBudget::new(DecodeLimits::new(bytes.len() - 1, 1, 10, 64).unwrap());
        assert!(matches!(
            inspect(SourceFormat::Json, bytes, &mut small),
            Err(SourceHeaderError::Json(_))
        ));
        assert_eq!(small.usage(DecodePhase::Source).values(), 0);
    }
}

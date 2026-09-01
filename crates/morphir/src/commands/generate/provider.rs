//! Morphir IR version detection used for backend provider resolution.

use crate::error::CliError;
use morphir_core::format_version::{NormalizedFormatVersion, ScalarValue, SupportTable};
use serde_json::Value;

pub(super) fn detect_ir_major(ir: &Value) -> Result<String, CliError> {
    let format_version = ir.get("formatVersion");
    if format_version == Some(&Value::from(4)) {
        return Ok("4".into());
    }
    let classic_ir = match format_version.and_then(Value::as_str) {
        Some(version) => {
            let scalar = ScalarValue::from_json(format_version.expect("string version exists"))
                .map_err(|_| unsupported_version(version))?;
            let normalized =
                NormalizedFormatVersion::from_scalar(&scalar, &SupportTable::reference())
                    .map_err(|_| unsupported_version(version))?;
            if !normalized.is_supported() {
                return Err(unsupported_version(version));
            }
            match normalized.release.major() {
                4 => return Ok("4".into()),
                3 => {}
                _ => return Err(unsupported_version(version)),
            }
            let mut normalized = ir.clone();
            normalized["formatVersion"] = Value::from(3);
            normalized
        }
        None => ir.clone(),
    };
    let classic = serde_json::from_value::<morphir_core::ir::classic::Distribution>(classic_ir)
        .map_err(|error| CliError::Extension {
            message: format!("Cannot detect a supported Morphir IR version: {error}"),
        })?;
    if classic.format_version != 3 {
        return Err(unsupported_version(&classic.format_version.to_string()));
    }
    Ok("3".into())
}

fn unsupported_version(version: &str) -> CliError {
    CliError::Extension {
        message: format!(
            "Cannot detect a supported Morphir IR version: unsupported formatVersion {version}"
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::detect_ir_major;
    use serde_json::json;

    fn classic_ir(format_version: serde_json::Value) -> serde_json::Value {
        json!({
            "formatVersion": format_version,
            "distribution": ["Library", [], [], {"modules": []}]
        })
    }

    #[test]
    fn detects_numeric_v4() {
        assert_eq!(
            detect_ir_major(&json!({"formatVersion": 4, "distribution": {}})).unwrap(),
            "4"
        );
    }

    #[test]
    fn detects_semantic_v4_string() {
        assert_eq!(
            detect_ir_major(&json!({"formatVersion": "4.0.0", "distribution": {}})).unwrap(),
            "4"
        );
    }

    #[test]
    fn detects_numeric_v3() {
        assert_eq!(detect_ir_major(&classic_ir(json!(3))).unwrap(), "3");
    }

    #[test]
    fn detects_semantic_v3_string() {
        assert_eq!(detect_ir_major(&classic_ir(json!("3.0.0"))).unwrap(), "3");
    }

    #[test]
    fn rejects_unsupported_v4_minor_versions() {
        let error = detect_ir_major(&json!({
            "formatVersion": "4.1.0",
            "distribution": {}
        }))
        .unwrap_err();

        assert!(
            error
                .to_string()
                .contains("unsupported formatVersion 4.1.0")
        );
    }
}

//! Select and validate the concrete IR requested from a frontend.

use super::{CliError, CompileResult, IrDescriptor, IrSection, IrVersion};
use crate::commands::ir_storage::{self, IrStorage};
use morphir_core::ir::{classic, v4};
use std::path::Path;

/// Parse a supported compile version at the CLI boundary.
pub fn parse_ir_version(text: &str) -> Result<IrVersion, String> {
    match text {
        "3" | "3.0.0" => Ok(IrVersion::V3),
        "4" | "4.0.0" => Ok(IrVersion::V4),
        _ => Err("Expected IR version 3 or 4".into()),
    }
}

pub(super) fn selected_ir_version(
    explicit: Option<IrVersion>,
    config: Option<&IrSection>,
) -> Result<IrVersion, CliError> {
    if let Some(version) = explicit {
        return Ok(version);
    }
    match config.map(|section| section.format_version).unwrap_or(4) {
        3 => Ok(IrVersion::V3),
        4 => Ok(IrVersion::V4),
        version => Err(CliError::Validation {
            message: format!(
                "IR format version {version} is not supported for compilation; use 3 or 4"
            ),
        }),
    }
}

pub(super) enum VersionedIr {
    V3(classic::Distribution),
    V4(v4::IRFile),
}

impl VersionedIr {
    pub(super) fn validate(result: &CompileResult, requested: IrVersion) -> Result<Self, CliError> {
        match requested {
            IrVersion::V4 => super::validate_v4_compile_result(result).map(Self::V4),
            IrVersion::V3 => {
                if !matches!(result.ir_version.as_deref(), Some("3" | "3.0.0")) {
                    return Err(CliError::Compilation {
                        message: "Frontend did not return requested IR version 3".into(),
                    });
                }
                let ir = result.ir.as_ref().ok_or_else(|| CliError::Compilation {
                    message: "Frontend returned success without IR".into(),
                })?;
                let model: classic::Distribution =
                    serde_json::from_value(ir.clone()).map_err(|error| CliError::Compilation {
                        message: format!("Frontend returned invalid Morphir IR v3: {error}"),
                    })?;
                if model.format_version != 3 {
                    return Err(CliError::Compilation {
                        message: "Embedded IR version does not match requested version 3".into(),
                    });
                }
                Ok(Self::V3(model))
            }
        }
    }

    pub(super) fn write(&self, dest: &Path, storage: &IrStorage) -> Result<IrDescriptor, CliError> {
        match self {
            Self::V3(ir) => ir_storage::write_v3(dest, storage, ir),
            Self::V4(ir) => ir_storage::write_v4(dest, storage, ir),
        }
    }

    pub(super) fn json(&self) -> Result<serde_json::Value, CliError> {
        match self {
            Self::V3(ir) => serde_json::to_value(ir),
            Self::V4(ir) => serde_json::to_value(ir),
        }
        .map_err(|error| CliError::Compilation {
            message: format!("Failed to serialize compiled IR: {error}"),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn v3_result_must_match_requested_and_embedded_versions() {
        let result = CompileResult {
            success: true,
            ir_version: Some("3".into()),
            ir: Some(
                json!({"formatVersion":3,"distribution":["Library",[["example"]],[],{"modules":[]}]}),
            ),
            modules: vec![],
            module_results: vec![],
            context_digest: None,
            diagnostics: vec![],
        };
        assert!(VersionedIr::validate(&result, IrVersion::V3).is_ok());
        assert!(VersionedIr::validate(&result, IrVersion::V4).is_err());
        let mut wrong = result.clone();
        wrong.ir_version = Some("4".into());
        assert!(VersionedIr::validate(&wrong, IrVersion::V3).is_err());
        let mut wrong = result;
        wrong.ir.as_mut().unwrap()["formatVersion"] = json!(4);
        assert!(VersionedIr::validate(&wrong, IrVersion::V3).is_err());
    }
}

use std::fs::File;
use std::io::Read;
use std::path::Path;

use morphir_common::ir_transport::{
    FormatId, IrVersion, Layout, Stage, TransportDiagnostic, discover_document_tree_format,
};
use morphir_common::vfs::physical_root;
use morphir_core::traversal::IrCursor;
use serde_saphyr::granit_parser::{Scanner, StrInput, TokenType};

const PROBE_BYTES: u64 = 64 * 1024;

#[derive(Clone, Debug)]
pub(super) struct InputSelection {
    pub format: FormatId,
    pub version: IrVersion,
    pub layout: Layout,
}

pub(super) fn resolve_output_format(
    explicit: Option<FormatId>,
    output: Option<&Path>,
    layout: Layout,
    json_stdout: bool,
) -> Result<FormatId, TransportDiagnostic> {
    if output.is_none() && json_stdout {
        return Ok(FormatId::json());
    }
    if layout == Layout::DocumentTree {
        return Ok(explicit.unwrap_or_else(FormatId::yaml));
    }
    let extension = output.and_then(format_from_extension);
    if let (Some(explicit), Some(extension)) = (&explicit, &extension)
        && explicit != extension
    {
        return Err(detection_error(
            "morphir::ir::detection::output_format_conflict",
            format!(
                "--output-format '{explicit}' conflicts with the destination extension for '{}'",
                output.unwrap().display()
            ),
            "make --output-format agree with the destination extension or use an unknown extension",
        ));
    }
    Ok(explicit.or(extension).unwrap_or_else(FormatId::yaml))
}

pub(super) fn resolve_input(
    path: &Path,
    explicit: Option<FormatId>,
) -> Result<InputSelection, TransportDiagnostic> {
    if path.is_dir() {
        let detected = discover_document_tree_format(&physical_root(path))?;
        if explicit.as_ref().is_some_and(|format| format != &detected) {
            return Err(detection_error(
                "morphir::ir::detection::input_format_conflict",
                format!(
                    "--input-format '{}' conflicts with the tree's {} manifest",
                    explicit.unwrap(),
                    detected
                ),
                "select the manifest's format or convert the complete tree first",
            ));
        }
        return Ok(InputSelection {
            format: detected,
            version: IrVersion::V4,
            layout: Layout::DocumentTree,
        });
    }
    let mut input = Vec::new();
    File::open(path)
        .and_then(|reader| reader.take(PROBE_BYTES).read_to_end(&mut input))
        .map_err(|error| {
            detection_error(
                "morphir::ir::detection::read_failed",
                format!("failed to inspect {}: {error}", path.display()),
                "verify that the input path is a readable IR artifact",
            )
        })?;
    let format = explicit
        .or_else(|| format_from_extension(path))
        .unwrap_or_else(|| detect_format(&input));
    let version = detect_version(&input, &format)?;
    Ok(InputSelection {
        format,
        version,
        layout: Layout::SingleFile,
    })
}

fn format_from_extension(path: &Path) -> Option<FormatId> {
    match path
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase)
        .as_deref()
    {
        Some("json") => Some(FormatId::json()),
        Some("yaml" | "yml") => Some(FormatId::yaml()),
        _ => None,
    }
}

fn detect_format(input: &[u8]) -> FormatId {
    match input
        .iter()
        .copied()
        .find(|byte| !byte.is_ascii_whitespace())
    {
        Some(b'{' | b'[') => FormatId::json(),
        _ => FormatId::yaml(),
    }
}

fn detect_version(input: &[u8], format: &FormatId) -> Result<IrVersion, TransportDiagnostic> {
    let source = std::str::from_utf8(input).map_err(|error| {
        detection_error(
            "morphir::ir::detection::invalid_utf8",
            error.to_string(),
            "encode the IR artifact as UTF-8",
        )
    })?;
    let value = if format == &FormatId::json() {
        let key = source
            .find("\"formatVersion\"")
            .ok_or_else(|| missing_version(format))?;
        let suffix = &source[key + "\"formatVersion\"".len()..];
        let colon = suffix.find(':').ok_or_else(|| missing_version(format))?;
        scalar_token(&suffix[colon + 1..]).to_owned()
    } else {
        yaml_root_scalar(source, "formatVersion").ok_or_else(|| missing_version(format))?
    };
    let normalized = value.trim_matches(['\'', '"']);
    if normalized == "3" || normalized.starts_with("3.") {
        Ok(IrVersion::V3)
    } else if normalized == "4" || normalized.starts_with("4.") {
        Ok(IrVersion::V4)
    } else {
        Err(detection_error(
            "morphir::ir::detection::unsupported_version",
            format!("unsupported formatVersion '{normalized}'"),
            "select concrete IR version 3 or 4",
        ))
    }
}

#[derive(Clone, Copy)]
enum RootMappingSlot {
    Key,
    Value,
}

fn yaml_root_scalar(source: &str, requested_key: &str) -> Option<String> {
    let mut collections = Vec::new();
    let mut slot = RootMappingSlot::Key;
    let mut requested_value = false;

    for scanned in Scanner::new(StrInput::new(source)) {
        let (_, token) = scanned.ok()?.into_parts();
        let at_root_mapping = collections.as_slice() == [true];
        match token {
            TokenType::BlockMappingStart | TokenType::FlowMappingStart => {
                if at_root_mapping && matches!(slot, RootMappingSlot::Value) && requested_value {
                    return None;
                }
                collections.push(true);
            }
            TokenType::BlockSequenceStart | TokenType::FlowSequenceStart => {
                if at_root_mapping && matches!(slot, RootMappingSlot::Value) && requested_value {
                    return None;
                }
                collections.push(false);
            }
            TokenType::BlockEnd | TokenType::FlowMappingEnd | TokenType::FlowSequenceEnd => {
                collections.pop();
            }
            TokenType::Key if at_root_mapping => slot = RootMappingSlot::Key,
            TokenType::Value if at_root_mapping => slot = RootMappingSlot::Value,
            TokenType::Scalar(_, value) if at_root_mapping => match slot {
                RootMappingSlot::Key => {
                    let key: &str = value.as_ref();
                    requested_value = key == requested_key;
                }
                RootMappingSlot::Value => {
                    if requested_value {
                        return Some(value.into_owned());
                    }
                }
            },
            TokenType::Alias(_)
                if at_root_mapping && matches!(slot, RootMappingSlot::Value) && requested_value =>
            {
                return None;
            }
            _ => {}
        }
    }
    None
}

fn scalar_token(source: &str) -> &str {
    let source = source.trim_start();
    if let Some(quote @ ('\'' | '"')) = source.chars().next() {
        let remainder = &source[quote.len_utf8()..];
        return remainder
            .find(quote)
            .map(|end| &source[..end + 2])
            .unwrap_or(source);
    }
    source
        .split(|character: char| character.is_ascii_whitespace() || matches!(character, ',' | '}'))
        .next()
        .unwrap_or(source)
}

fn missing_version(format: &FormatId) -> TransportDiagnostic {
    detection_error(
        "morphir::ir::detection::missing_format_version",
        format!("no formatVersion was found in the bounded {format} header probe"),
        "place formatVersion before the distribution or select the correct input format",
    )
}

fn detection_error(
    code: &'static str,
    message: impl Into<String>,
    guidance: &'static str,
) -> TransportDiagnostic {
    TransportDiagnostic::error(code, Stage::Detection, IrCursor::root(), message)
        .with_guidance(guidance)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn output_resolution_uses_flag_then_extension_then_yaml() {
        assert_eq!(
            resolve_output_format(
                Some(FormatId::yaml()),
                Some(Path::new("model.yaml")),
                Layout::SingleFile,
                false,
            )
            .unwrap(),
            FormatId::yaml()
        );
        assert_eq!(
            resolve_output_format(
                None,
                Some(Path::new("model.yml")),
                Layout::SingleFile,
                false,
            )
            .unwrap(),
            FormatId::yaml()
        );
        assert_eq!(
            resolve_output_format(
                None,
                Some(Path::new("model.json")),
                Layout::SingleFile,
                false,
            )
            .unwrap(),
            FormatId::json()
        );
        assert_eq!(
            resolve_output_format(
                None,
                Some(Path::new("model.data")),
                Layout::SingleFile,
                false,
            )
            .unwrap(),
            FormatId::yaml()
        );
    }

    #[test]
    fn explicit_output_conflict_is_rejected() {
        let diagnostic = resolve_output_format(
            Some(FormatId::json()),
            Some(Path::new("model.yaml")),
            Layout::SingleFile,
            false,
        )
        .unwrap_err();
        assert_eq!(
            diagnostic.code(),
            "morphir::ir::detection::output_format_conflict"
        );
    }

    #[test]
    fn yaml_version_detection_accepts_quoted_and_flow_mapping_keys() {
        for source in [
            "\"formatVersion\": 4\ndistribution: {}\n",
            "{\"formatVersion\": 4, distribution: {}}\n",
        ] {
            assert_eq!(
                detect_version(source.as_bytes(), &FormatId::yaml()).unwrap(),
                IrVersion::V4
            );
        }
    }

    #[test]
    fn bounded_yaml_version_detection_stops_before_a_truncated_body() {
        let bounded_prefix = "\"formatVersion\": 4\ndistribution:\n  modules:\n    -";

        assert_eq!(
            detect_version(bounded_prefix.as_bytes(), &FormatId::yaml()).unwrap(),
            IrVersion::V4
        );
    }
}

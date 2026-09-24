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
pub(crate) struct InputSelection {
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

pub(crate) fn resolve_input(
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
        let version = if detected == FormatId::ion() {
            // An Ion tree is v3 or v4, and its manifest says which.
            detect_version(&probe(&path.join("manifest.ion"))?, &detected)?
        } else {
            json_or_yaml_tree_version(path, &detected)
        };
        return Ok(InputSelection {
            format: detected,
            version,
            layout: Layout::DocumentTree,
        });
    }
    let input = probe(path)?;
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

/// The version of a JSON or YAML tree. It is v3 only when its manifest positively says 3.x.
/// Every other manifest, including one the probe cannot read, goes to the v4 transport, which
/// reports its faults with the kit's diagnostics.
fn json_or_yaml_tree_version(path: &Path, format: &FormatId) -> IrVersion {
    let manifest = if format == &FormatId::json() {
        path.join("manifest.json")
    } else if path.join("manifest.yaml").is_file() {
        path.join("manifest.yaml")
    } else {
        path.join("manifest.yml")
    };
    match probe(&manifest).and_then(|input| detect_version(&input, format)) {
        Ok(IrVersion::V3) => IrVersion::V3,
        _ => IrVersion::V4,
    }
}

/// The first `PROBE_BYTES` of a file.
fn probe(path: &Path) -> Result<Vec<u8>, TransportDiagnostic> {
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
    Ok(input)
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
        Some("ion") => Some(FormatId::ion()),
        _ => None,
    }
}

fn ion_datagram(input: &[u8]) -> bool {
    std::str::from_utf8(input)
        .ok()
        .is_some_and(|text| text.trim_start().starts_with("morphir::"))
}

fn detect_format(input: &[u8]) -> FormatId {
    match input
        .iter()
        .copied()
        .find(|byte| !byte.is_ascii_whitespace())
    {
        Some(b'{' | b'[') => FormatId::json(),
        Some(_) if ion_datagram(input) => FormatId::ion(),
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
    } else if format == &FormatId::ion() {
        ion_header_scalar(source, "formatVersion").ok_or_else(|| missing_version(format))?
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
                    requested_value = AsRef::<str>::as_ref(&value) == requested_key;
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

/// The scalar after the first `key:` in an Ion header. The field name may be a bare, quoted, or
/// single-quoted symbol, so the name is matched on its own and the separator after it.
fn ion_header_scalar(source: &str, key: &str) -> Option<String> {
    let mut rest = source;
    while let Some(at) = rest.find(key) {
        let after = rest[at + key.len()..].trim_start_matches(['\'', '"']);
        if let Some(value) = after.trim_start().strip_prefix(':') {
            return Some(scalar_token(value).to_owned());
        }
        rest = &rest[at + key.len()..];
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

    const ION_V3_HEADER: &str = "morphir::{\n  ionVersion: \"0.1.0-draft.1\",\n  formatVersion: \"3.0.0\",\n  kind: library,\n  packageName: \"example\",\n}\n";

    #[test]
    fn an_ion_file_reports_its_header_version() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("model.ion");
        std::fs::write(&path, format!("{ION_V3_HEADER}morphir_footer::{{}}\n")).unwrap();

        let selection = resolve_input(&path, None).unwrap();

        assert_eq!(selection.format, FormatId::ion());
        assert_eq!(selection.version, IrVersion::V3);
    }

    #[test]
    fn an_ion_tree_reports_its_manifest_version() {
        let temp = tempfile::tempdir().unwrap();
        std::fs::write(temp.path().join("manifest.ion"), ION_V3_HEADER).unwrap();

        let selection = resolve_input(temp.path(), None).unwrap();

        assert_eq!(selection.format, FormatId::ion());
        assert_eq!(selection.layout, Layout::DocumentTree);
        assert_eq!(selection.version, IrVersion::V3);
    }

    #[test]
    fn a_v3_json_tree_reports_its_manifest_version() {
        let temp = tempfile::tempdir().unwrap();
        std::fs::write(
            temp.path().join("manifest.json"),
            r#"{"formatVersion":"3.1.0","distribution":"Library","package":"example","pathBudget":4000}"#,
        )
        .unwrap();

        let selection = resolve_input(temp.path(), None).unwrap();

        assert_eq!(selection.format, FormatId::json());
        assert_eq!(selection.layout, Layout::DocumentTree);
        assert_eq!(selection.version, IrVersion::V3);
    }

    #[test]
    fn a_json_or_yaml_tree_manifest_that_is_not_v3_goes_to_the_v4_reader() {
        for (name, manifest) in [
            ("manifest.json", r#"{"distribution":"Library"}"#),
            (
                "manifest.json",
                r#"{"formatVersion":5,"distribution":"Library"}"#,
            ),
            (
                "manifest.json",
                r#"{"formatVersion":4,"distribution":"Library"}"#,
            ),
            ("manifest.yaml", "formatVersion: [unclosed\n"),
            ("manifest.yml", "distribution: Library\n"),
        ] {
            let temp = tempfile::tempdir().unwrap();
            std::fs::write(temp.path().join(name), manifest).unwrap();

            let selection = resolve_input(temp.path(), None).unwrap();

            assert_eq!(selection.layout, Layout::DocumentTree, "{name}: {manifest}");
            assert_eq!(selection.version, IrVersion::V4, "{name}: {manifest}");
        }
    }

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

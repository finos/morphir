//! Write and read IR in the storage declared by `[ir]` and the task record.

use crate::commands::migrate::format::resolve_input;
use crate::error::CliError;
use morphir_common::config::model::IrSection;
use morphir_common::ir_transport::{
    CodecOptions, CodecRegistry, FormatId, IrVersion, Layout, read_document_tree_with_options,
    write_document_tree_with_options,
};
use morphir_common::vfs::physical_root;
use morphir_core::ir::v4::IRFile;
use morphir_devkit::{IrDescriptor, IrLayout};
use std::io::Cursor;
use std::path::{Path, PathBuf};

/// Base name for IR under `.dest`: `morphir-ir.json`/`morphir-ir.yaml` for
/// single-file storage, `morphir-ir/` for the document-tree directory.
const IR_STEM: &str = "morphir-ir";

/// Storage compile writes, from `[ir].layout` and `[ir].format`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IrStorage {
    /// Single file or document tree.
    pub layout: IrLayout,
    /// `json` or `yaml`.
    pub format: FormatId,
}

impl IrStorage {
    /// Parse the `[ir]` section. Missing section means single-file JSON.
    pub fn from_config(ir: Option<&IrSection>) -> Result<Self, CliError> {
        let layout_text = ir
            .map(|section| section.layout.as_str())
            .unwrap_or("single-file");
        let format_text = ir.map(|section| section.format.as_str()).unwrap_or("json");
        let layout = layout_text
            .parse::<IrLayout>()
            .map_err(|_error| CliError::Validation {
                message: format!(
                    "ir.layout '{layout_text}' is not supported; use single-file or document-tree"
                ),
            })?;
        let format = match format_text {
            "json" => FormatId::json(),
            "yaml" => FormatId::yaml(),
            other => {
                return Err(CliError::Validation {
                    message: format!("ir.format '{other}' is not supported; use json or yaml"),
                });
            }
        };
        Ok(Self { layout, format })
    }

    /// File or directory name inside `.dest`.
    pub fn relative_path(&self) -> &'static str {
        match (self.layout, self.format.as_str()) {
            (IrLayout::DocumentTree, _) => IR_STEM,
            (IrLayout::SingleFile, "yaml") => "morphir-ir.yaml",
            (IrLayout::SingleFile, _) => "morphir-ir.json",
        }
    }
}

/// Write a v4 IR file into `dest` and describe where it went.
pub fn write_v4(dest: &Path, storage: &IrStorage, ir: &IRFile) -> Result<IrDescriptor, CliError> {
    std::fs::create_dir_all(dest).map_err(|error| CliError::FileSystem { error })?;
    let target = dest.join(storage.relative_path());
    match storage.layout {
        IrLayout::SingleFile if storage.format == FormatId::json() => {
            let bytes = serde_json::to_vec_pretty(ir).map_err(|error| CliError::Extension {
                message: format!("Failed to serialize Morphir IR v4: {error}"),
            })?;
            std::fs::write(&target, bytes).map_err(|error| CliError::FileSystem { error })?;
        }
        IrLayout::SingleFile => {
            let json = serde_json::to_vec(ir).map_err(|error| CliError::Extension {
                message: format!("Failed to serialize Morphir IR v4: {error}"),
            })?;
            let registry = CodecRegistry::with_builtins();
            let json_codec = codec(&registry, &FormatId::json())?;
            let out_codec = codec(&registry, &storage.format)?;
            let mut file =
                std::fs::File::create(&target).map_err(|error| CliError::FileSystem { error })?;
            let out_options =
                CodecOptions::new(IrVersion::V4, Layout::SingleFile, storage.format.clone());
            let mut sink = out_codec
                .encoder(&mut file, &out_options)
                .map_err(transport)?;
            json_codec
                .decode(
                    &mut Cursor::new(json),
                    &CodecOptions::new(IrVersion::V4, Layout::SingleFile, FormatId::json()),
                    sink.as_mut(),
                )
                .map_err(transport)?;
        }
        IrLayout::DocumentTree => {
            std::fs::create_dir_all(&target).map_err(|error| CliError::FileSystem { error })?;
            write_document_tree_with_options(
                &physical_root(&target),
                ir,
                &CodecOptions::new(IrVersion::V4, Layout::DocumentTree, storage.format.clone()),
            )
            .map_err(transport)?;
        }
    }
    Ok(IrDescriptor {
        path: storage.relative_path().to_owned(),
        layout: storage.layout,
        format: storage.format.as_str().to_owned(),
        version: "v4".to_owned(),
    })
}

/// Descriptor for the classic (v3) JSON file single-file Elm compile writes.
pub fn v3_json_descriptor() -> IrDescriptor {
    IrDescriptor {
        path: "morphir-ir.json".to_owned(),
        layout: IrLayout::SingleFile,
        format: "json".to_owned(),
        version: "v3".to_owned(),
    }
}

/// Load the IR described by `descriptor` (relative to `base`) as a JSON value.
pub fn read_value(base: &Path, descriptor: &IrDescriptor) -> Result<serde_json::Value, CliError> {
    let target = base.join(&descriptor.path);
    let format =
        FormatId::new(descriptor.format.clone()).map_err(|error| CliError::Validation {
            message: format!("task record has an invalid IR format: {error}"),
        })?;
    let version = match descriptor.version.as_str() {
        "v3" => IrVersion::V3,
        _ => IrVersion::V4,
    };
    match descriptor.layout {
        IrLayout::SingleFile if format == FormatId::json() && version == IrVersion::V3 => {
            // A v3 file's `formatVersion` may still read as the historical
            // `"3.0.0"` string. Round-tripping through the typed classic
            // distribution (as the pre-record-based `load_ir` always did)
            // normalizes it to the bare integer `3` that backends expect on
            // the wire, the same way single-file JSON v3 output ever was.
            let bytes = std::fs::read(&target).map_err(|error| CliError::FileSystem { error })?;
            let distribution: morphir_core::ir::classic::Distribution =
                serde_json::from_slice(&bytes).map_err(|error| CliError::Validation {
                    message: format!("{} is not valid v3 IR JSON: {error}", target.display()),
                })?;
            serde_json::to_value(&distribution).map_err(|error| CliError::Extension {
                message: format!("Failed to serialize Morphir IR v3: {error}"),
            })
        }
        IrLayout::SingleFile if format == FormatId::json() => {
            let bytes = std::fs::read(&target).map_err(|error| CliError::FileSystem { error })?;
            serde_json::from_slice(&bytes).map_err(|error| CliError::Validation {
                message: format!("{} is not valid JSON: {error}", target.display()),
            })
        }
        IrLayout::SingleFile => {
            let registry = CodecRegistry::with_builtins();
            let in_codec = codec(&registry, &format)?;
            let json_codec = codec(&registry, &FormatId::json())?;
            let mut reader = std::io::BufReader::new(
                std::fs::File::open(&target).map_err(|error| CliError::FileSystem { error })?,
            );
            let mut json = Vec::new();
            {
                let mut sink = json_codec
                    .encoder(
                        &mut json,
                        &CodecOptions::new(version, Layout::SingleFile, FormatId::json()),
                    )
                    .map_err(transport)?;
                in_codec
                    .decode(
                        &mut reader,
                        &CodecOptions::new(version, Layout::SingleFile, format.clone()),
                        sink.as_mut(),
                    )
                    .map_err(transport)?;
            }
            serde_json::from_slice(&json).map_err(|error| CliError::Validation {
                message: format!("{} did not convert to JSON: {error}", target.display()),
            })
        }
        IrLayout::DocumentTree => {
            let ir = read_document_tree_with_options(
                &physical_root(&target),
                &CodecOptions::new(version, Layout::DocumentTree, format),
            )
            .map_err(transport)?;
            serde_json::to_value(&ir).map_err(|error| CliError::Extension {
                message: format!("Failed to serialize Morphir IR v4: {error}"),
            })
        }
    }
}

/// Probe an explicit `-i` path: an IR file, a document-tree directory (a
/// `manifest.json`/`manifest.yaml` root), or a compile-output directory (a
/// `.dest` directory, or any older directory shaped like one) that holds
/// `morphir-ir.json`, `morphir-ir.yaml`, or a `morphir-ir/` document tree.
pub fn probe_external(path: &Path) -> Result<(PathBuf, IrDescriptor), CliError> {
    if path.is_dir() && !is_document_tree_root(path) {
        return probe_compile_output_directory(path);
    }
    let selection = resolve_input(path, None).map_err(transport)?;
    let name = path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .ok_or_else(|| CliError::Validation {
            message: format!("IR input path '{}' has no file name", path.display()),
        })?;
    let base = path.parent().map(Path::to_path_buf).unwrap_or_default();
    Ok((
        base,
        IrDescriptor {
            path: name,
            layout: IrLayout::from(selection.layout),
            format: selection.format.as_str().to_owned(),
            version: match selection.version {
                IrVersion::V3 => "v3".to_owned(),
                IrVersion::V4 => "v4".to_owned(),
            },
        },
    ))
}

/// Whether `path` has a document-tree manifest at its root. Only checks for
/// presence — an ambiguous pair (`manifest.json` *and* `manifest.yaml`) is
/// still surfaced by `discover_document_tree_format`'s own diagnostic once
/// `resolve_input` runs.
fn is_document_tree_root(path: &Path) -> bool {
    ["manifest.json", "manifest.yaml"]
        .into_iter()
        .any(|name| path.join(name).is_file())
}

/// Probe a directory that is not itself a document-tree root for the IR
/// artifact it holds. `discover_document_tree_format`'s "no supported
/// manifest" diagnostic is correct for a hand-authored document tree missing
/// its manifest, but misleading for a compile-output directory (a `.dest`
/// directory, or any directory shaped like the classic `morphir-ir.json`
/// compile output) — such a directory was never meant to have one, so this
/// looks for what it *does* produce instead: a single-file JSON/YAML
/// artifact, or its own nested `morphir-ir/` document tree.
fn probe_compile_output_directory(path: &Path) -> Result<(PathBuf, IrDescriptor), CliError> {
    for name in ["morphir-ir.json", "morphir-ir.yaml"] {
        let candidate = path.join(name);
        if candidate.is_file() {
            return probe_external(&candidate);
        }
    }
    let tree = path.join(IR_STEM);
    if tree.is_dir() {
        return probe_external(&tree);
    }
    Err(CliError::Validation {
        message: format!(
            "'{}' has no Morphir IR: looked for a document-tree manifest \
             (manifest.json, manifest.yaml), a single-file artifact \
             (morphir-ir.json, morphir-ir.yaml), and a morphir-ir/ document tree",
            path.display()
        ),
    })
}

fn codec<'registry>(
    registry: &'registry CodecRegistry,
    format: &FormatId,
) -> Result<&'registry dyn morphir_common::ir_transport::IrCodec, CliError> {
    registry.codec(format).ok_or_else(|| CliError::Validation {
        message: format!("no codec is registered for '{format}'"),
    })
}

fn transport(error: morphir_common::ir_transport::TransportDiagnostic) -> CliError {
    CliError::Validation {
        message: error.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use indexmap::IndexMap;
    use morphir_common::config::model::IrSection;
    use morphir_core::ir::v4::{
        Distribution, FormatVersion, IRFile, LibraryContent, PackageDefinition,
    };
    use morphir_core::naming::PackageName;

    fn sample_ir() -> IRFile {
        IRFile {
            format_version: FormatVersion::Integer(4),
            distribution: Distribution::Library(LibraryContent {
                package_name: PackageName::parse("acme/app"),
                dependencies: IndexMap::new(),
                def: PackageDefinition {
                    modules: IndexMap::new(),
                },
            }),
        }
    }

    fn section(layout: &str, format: &str) -> IrSection {
        serde_json::from_value(serde_json::json!({"layout": layout, "format": format})).unwrap()
    }

    #[test]
    fn storage_from_config_defaults_to_single_file_json() {
        let storage = IrStorage::from_config(None).unwrap();
        assert_eq!(storage.layout, IrLayout::SingleFile);
        assert_eq!(storage.format, FormatId::json());
        assert_eq!(storage.relative_path(), "morphir-ir.json");
        assert_eq!(
            IrStorage::from_config(Some(&section("single-file", "yaml")))
                .unwrap()
                .relative_path(),
            "morphir-ir.yaml"
        );
        assert_eq!(
            IrStorage::from_config(Some(&section("document-tree", "yaml")))
                .unwrap()
                .relative_path(),
            "morphir-ir"
        );
        // An unrecognized `ir.layout` value can no longer reach here through
        // ordinary config loading — `IrSection`'s `Deserialize` now rejects it
        // first — but `IrStorage::from_config` keeps its own check too, in
        // case a record or config value is ever built by hand rather than
        // decoded. Bypass `Deserialize` to exercise that fallback directly.
        let unrecognized_layout = IrSection {
            format_version: 4,
            layout: "blob".to_owned(),
            format: "json".to_owned(),
            mode: None,
            strict_mode: false,
        };
        assert!(IrStorage::from_config(Some(&unrecognized_layout)).is_err());
    }

    #[test]
    fn json_single_file_round_trips() {
        let temp = tempfile::tempdir().unwrap();
        let storage = IrStorage::from_config(None).unwrap();
        let descriptor = write_v4(temp.path(), &storage, &sample_ir()).unwrap();
        assert_eq!(descriptor.path, "morphir-ir.json");
        assert_eq!(descriptor.version, "v4");
        let value = read_value(temp.path(), &descriptor).unwrap();
        assert_eq!(value["formatVersion"], 4);
    }

    #[test]
    fn yaml_single_file_round_trips() {
        let temp = tempfile::tempdir().unwrap();
        let storage = IrStorage::from_config(Some(&section("single-file", "yaml"))).unwrap();
        let descriptor = write_v4(temp.path(), &storage, &sample_ir()).unwrap();
        assert!(temp.path().join("morphir-ir.yaml").is_file());
        let value = read_value(temp.path(), &descriptor).unwrap();
        assert_eq!(value["distribution"]["Library"]["packageName"], "acme/app");
    }

    #[test]
    fn document_tree_round_trips() {
        let temp = tempfile::tempdir().unwrap();
        let storage = IrStorage::from_config(Some(&section("document-tree", "json"))).unwrap();
        let descriptor = write_v4(temp.path(), &storage, &sample_ir()).unwrap();
        assert_eq!(descriptor.layout, IrLayout::DocumentTree);
        assert!(temp.path().join("morphir-ir/manifest.json").is_file());
        let value = read_value(temp.path(), &descriptor).unwrap();
        assert_eq!(value["formatVersion"], 4);
    }

    #[test]
    fn probe_external_detects_files_and_trees() {
        let temp = tempfile::tempdir().unwrap();
        let storage = IrStorage::from_config(Some(&section("document-tree", "yaml"))).unwrap();
        write_v4(temp.path(), &storage, &sample_ir()).unwrap();
        let (base, descriptor) = probe_external(&temp.path().join("morphir-ir")).unwrap();
        assert_eq!(base, temp.path());
        assert_eq!(descriptor.path, "morphir-ir");
        assert_eq!(descriptor.layout, IrLayout::DocumentTree);
        assert_eq!(descriptor.format, "yaml");

        let json = IrStorage::from_config(None).unwrap();
        write_v4(temp.path(), &json, &sample_ir()).unwrap();
        let (_, descriptor) = probe_external(&temp.path().join("morphir-ir.json")).unwrap();
        assert_eq!(descriptor.layout, IrLayout::SingleFile);
        assert_eq!(descriptor.format, "json");
    }

    #[test]
    fn probe_external_finds_the_single_file_artifact_in_a_manifest_less_directory() {
        // A `.dest` directory (or any older compile-output directory) is
        // not itself a document-tree root: it holds `morphir-ir.json`
        // directly, with no `manifest.json`/`manifest.yaml`. `probe_external`
        // must still resolve the directory to that file rather than treating
        // it as a malformed document tree.
        let temp = tempfile::tempdir().unwrap();
        let compile_dest = temp.path().join("compile.dest");
        let storage = IrStorage::from_config(None).unwrap();
        write_v4(&compile_dest, &storage, &sample_ir()).unwrap();
        assert!(!compile_dest.join("manifest.json").exists());

        let (base, descriptor) = probe_external(&compile_dest).unwrap();

        assert_eq!(base, compile_dest);
        assert_eq!(descriptor.path, "morphir-ir.json");
        assert_eq!(descriptor.layout, IrLayout::SingleFile);
        assert_eq!(descriptor.format, "json");
        let value = read_value(&base, &descriptor).unwrap();
        assert_eq!(value["formatVersion"], 4);
    }

    #[test]
    fn probe_external_reports_what_it_looked_for_in_an_empty_directory() {
        let temp = tempfile::tempdir().unwrap();
        let empty = temp.path().join("empty");
        std::fs::create_dir_all(&empty).unwrap();

        let error = probe_external(&empty).unwrap_err();

        let message = error.to_string();
        assert!(message.contains(&empty.display().to_string()), "{message}");
        assert!(message.contains("morphir-ir.json"), "{message}");
        assert!(message.contains("morphir-ir.yaml"), "{message}");
        assert!(message.contains("manifest"), "{message}");
    }
}

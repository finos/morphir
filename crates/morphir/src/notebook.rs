//! The shared Morphir nbformat profile: cells, metadata and workspace files.
//! Execution roles belong to consumers such as `itest`, not this reader.
use anyhow::{Context, Result, ensure};
use serde::Deserialize;
use serde_json::Value;
use std::{collections::HashSet, fs, io::Write, path::Path};
use unicode_casefold::UnicodeCaseFold as _;
use unicode_normalization::UnicodeNormalization as _;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CellKind {
    Markdown,
    Code,
    Raw,
}

#[derive(Debug)]
pub struct Cell {
    id: String,
    kind: CellKind,
    source: String,
    morphir: Value,
}
impl Cell {
    pub fn id(&self) -> &str {
        &self.id
    }
    pub fn kind(&self) -> CellKind {
        self.kind
    }
    pub fn source(&self) -> &str {
        &self.source
    }
    pub fn morphir(&self) -> &Value {
        &self.morphir
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct FileMetadata {
    path: String,
    language: String,
}

#[derive(Debug)]
struct WorkspaceFile {
    path: String,
    source: String,
}

#[derive(Debug)]
pub struct Notebook {
    document: Value,
    cells: Vec<Cell>,
    files: Vec<WorkspaceFile>,
}

fn object<'a>(value: &'a Value, label: &str) -> Result<&'a serde_json::Map<String, Value>> {
    value
        .as_object()
        .with_context(|| format!("{label} must be an object"))
}
fn string<'a>(value: &'a Value, label: &str) -> Result<&'a str> {
    value
        .as_str()
        .with_context(|| format!("{label} must be a string"))
}

impl Notebook {
    pub fn parse(text: &str) -> Result<Self> {
        let document: Value = serde_json::from_str(text).context("invalid notebook JSON")?;
        object(&document, "notebook")?;
        ensure!(
            document["nbformat"] == 4 && document["nbformat_minor"] == 5,
            "expected nbformat 4.5"
        );
        object(&document["metadata"], "notebook metadata")?;
        let profile = &document["metadata"]["morphir"];
        if !profile.is_null() {
            object(profile, "Morphir notebook metadata")?;
            ensure!(
                profile["version"] == 1,
                "unsupported Morphir notebook profile version"
            );
        }
        let raw_cells = document["cells"]
            .as_array()
            .context("notebook cells must be an array")?;
        let mut ids = HashSet::new();
        let mut paths: Vec<String> = Vec::new();
        let mut cells = Vec::new();
        let mut files = Vec::new();
        for value in raw_cells {
            object(value, "cell")?;
            let id = string(&value["id"], "cell id")?;
            ensure!(
                !id.is_empty()
                    && id.len() <= 64
                    && id
                        .bytes()
                        .all(|c| c.is_ascii_alphanumeric() || b"-_".contains(&c)),
                "invalid notebook cell id {id:?}"
            );
            ensure!(
                ids.insert(id.to_owned()),
                "duplicate notebook cell id {id:?}"
            );
            object(&value["metadata"], "cell metadata")?;
            let kind = match value["cell_type"].as_str() {
                Some("markdown") => CellKind::Markdown,
                Some("code") => {
                    ensure!(
                        value
                            .get("execution_count")
                            .is_some_and(|count| count.is_null() || count.as_u64().is_some()),
                        "cell {id}: invalid or missing execution_count"
                    );
                    ensure!(
                        value["outputs"].is_array(),
                        "cell {id}: outputs must be an array"
                    );
                    CellKind::Code
                }
                Some("raw") => CellKind::Raw,
                _ => anyhow::bail!("cell {id}: unsupported cell_type"),
            };
            let source = match &value["source"] {
                Value::String(text) => text.clone(),
                Value::Array(lines) => lines
                    .iter()
                    .map(|line| string(line, "source line"))
                    .collect::<Result<Vec<_>>>()?
                    .concat(),
                _ => anyhow::bail!("cell {id}: source must be a string or string array"),
            };
            let morphir = value["metadata"]["morphir"].clone();
            if !morphir.is_null() {
                object(&morphir, "Morphir cell metadata")?;
            }
            if let Some(file) = morphir.get("file") {
                ensure!(
                    kind != CellKind::Markdown,
                    "cell {id}: Markdown cannot be a workspace file"
                );
                let file: FileMetadata = serde_json::from_value(file.clone())
                    .with_context(|| format!("cell {id}: invalid workspace file metadata"))?;
                relative_path(&file.path)?;
                ensure!(
                    !file.language.trim().is_empty(),
                    "cell {id}: file language is empty"
                );
                let portable: String = file.path.nfkc().case_fold().nfc().collect();
                ensure!(
                    !paths.iter().any(|path| path == &portable
                        || path.starts_with(&format!("{portable}/"))
                        || portable.starts_with(&format!("{path}/"))),
                    "duplicate or conflicting workspace path {:?}",
                    file.path
                );
                paths.push(portable);
                files.push(WorkspaceFile {
                    path: file.path,
                    source: source.clone(),
                });
            }
            cells.push(Cell {
                id: id.to_owned(),
                kind,
                source,
                morphir,
            });
        }
        Ok(Self {
            document,
            cells,
            files,
        })
    }

    /// Original document, including metadata unknown to Morphir.
    pub fn document(&self) -> &Value {
        &self.document
    }
    pub fn cells(&self) -> &[Cell] {
        &self.cells
    }

    /// Populate a fresh workspace; never replace existing files or follow symlinks.
    pub fn materialize(&self, root: &Path) -> Result<()> {
        ensure!(
            fs::symlink_metadata(root)?.is_dir(),
            "workspace root must be a real directory"
        );
        for file in &self.files {
            let mut path = root.to_path_buf();
            let parts: Vec<_> = file.path.split('/').collect();
            for part in &parts[..parts.len() - 1] {
                path.push(part);
                match fs::create_dir(&path) {
                    Ok(()) => {}
                    Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => ensure!(
                        fs::symlink_metadata(&path)?.is_dir(),
                        "workspace ancestor is not a real directory: {}",
                        path.display()
                    ),
                    Err(error) => return Err(error.into()),
                }
            }
            path.push(parts.last().unwrap());
            fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&path)
                .with_context(|| format!("materialize {}", file.path))?
                .write_all(file.source.as_bytes())?;
        }
        Ok(())
    }
}

/// The shared profile uses normalized, portable, confined paths.
pub fn relative_path(value: &str) -> Result<()> {
    ensure!(
        !value.is_empty() && !value.contains(['\\', ':']),
        "expected a portable relative path: {value:?}"
    );
    ensure!(
        value
            .split('/')
            .all(|part| !part.is_empty() && part != "." && part != ".."),
        "path escapes the workspace or is not normalized: {value:?}"
    );
    for part in value.split('/') {
        ensure!(
            !part.ends_with(['.', ' '])
                && !part
                    .chars()
                    .any(|ch| ch.is_control() || "<>\"|?*".contains(ch)),
            "nonportable path component: {part:?}"
        );
        let stem = part
            .split('.')
            .next()
            .unwrap_or_default()
            .to_ascii_uppercase();
        let device = matches!(
            stem.as_str(),
            "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
        ) || ["COM", "LPT"].iter().any(|prefix| {
            stem.strip_prefix(prefix).is_some_and(|suffix| {
                matches!(
                    suffix,
                    "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
                )
            })
        });
        ensure!(!device, "reserved device name in workspace path: {part:?}");
    }
    Ok(())
}

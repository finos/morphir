//! Copy project inputs before running commands; never execute in the author's tree.
#[cfg(test)]
use super::Scenario;
use super::model::{Workspace, relative_path};
use anyhow::{Context, Result, ensure};
use std::{
    collections::HashMap,
    fs,
    io::Write,
    path::{Path, PathBuf},
};
use unicode_casefold::UnicodeCaseFold as _;
use unicode_normalization::UnicodeNormalization as _;

fn excluded(path: &Path, exclusions: &[String]) -> bool {
    path.components().any(|component| {
        matches!(
            component.as_os_str().to_str(),
            Some(".git" | "node_modules" | "target" | "elm-stuff" | "dist" | "out")
        )
    }) || path
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(super::is_scenario_document)
        || path.starts_with(".morphir/cache")
        || exclusions.iter().any(|excluded| path.starts_with(excluded))
}

fn source_directory(directory: &Path, relative: &str) -> Result<PathBuf> {
    let mut source = directory.to_owned();
    if relative != "." {
        relative_path(relative)?;
        for component in Path::new(relative).components() {
            source.push(component);
            real_directory(&source)?;
        }
    }
    real_directory(&source)?;
    Ok(source)
}

fn real_directory(source: &Path) -> Result<()> {
    let message = || {
        format!(
            "workspace source must be a real directory: {}",
            source.display()
        )
    };
    ensure!(
        fs::symlink_metadata(source).with_context(message)?.is_dir(),
        message()
    );
    Ok(())
}

/// Disk inputs of a directory workspace: `(path, source)` files and directories, relative to
/// `destination`.
type Inputs = (Vec<(String, PathBuf)>, Vec<String>);

fn collect_inputs(directory: &Path, path: &str, exclude: &[String]) -> Result<Inputs> {
    let source = source_directory(directory, path)?;
    let mut files = Vec::new();
    let mut directories = Vec::new();
    for entry in walkdir::WalkDir::new(&source)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| !excluded(entry.path().strip_prefix(&source).unwrap(), exclude))
    {
        let entry = entry?;
        let relative = entry.path().strip_prefix(&source)?;
        if relative.as_os_str().is_empty() {
            continue;
        }
        ensure!(
            !entry.file_type().is_symlink(),
            "workspace input cannot be a symlink: {}",
            entry.path().display()
        );
        let path = relative
            .components()
            .map(|component| {
                component
                    .as_os_str()
                    .to_str()
                    .context("workspace input path must be UTF-8")
            })
            .collect::<Result<Vec<_>>>()?
            .join("/");
        relative_path(&path)?;
        if entry.file_type().is_dir() {
            directories.push(path);
        } else {
            ensure!(
                entry.file_type().is_file(),
                "workspace input must be a regular file: {}",
                entry.path().display()
            );
            files.push((path, entry.path().to_owned()));
        }
    }
    Ok((files, directories))
}

fn copy_inputs((files, directories): Inputs, destination: &Path) -> Result<()> {
    for directory in directories {
        fs::create_dir_all(destination.join(directory))?;
    }
    for (path, source) in files {
        fs::copy(&source, destination.join(&path))
            .with_context(|| format!("copy workspace input {path}"))?;
    }
    Ok(())
}

/// Materializes a scenario of the legacy loader the unit tests use, the same way
/// [`materialize_example`] does, with the section's `morphir:file` blocks as the overlay files.
#[cfg(test)]
pub(super) fn materialize(scenario: &Scenario, destination: &Path) -> Result<()> {
    let overlay: Vec<(&str, &str)> = scenario
        .section
        .cells
        .iter()
        .filter(|cell| cell.role == super::markdown::CellRole::File)
        .map(|cell| {
            let path = cell.metadata["path"].as_str().unwrap_or_default();
            (path, cell.source.as_str())
        })
        .collect();
    materialize_example(
        &scenario.directory,
        &scenario.metadata.workspace,
        overlay,
        destination,
    )
}

/// Materialize an example into `destination` from its directory `directory`, its `workspace`
/// and its `(path, source)` overlay files, which `scenarios.md` writes as `morphir:file`
/// fences. An inline workspace holds only the overlay files.
pub(super) fn materialize_example<'a>(
    directory: &Path,
    workspace: &Workspace,
    overlay: impl IntoIterator<Item = (&'a str, &'a str)> + Clone,
    destination: &Path,
) -> Result<()> {
    let inputs = match workspace {
        Workspace::Directory { path, exclude } => collect_inputs(directory, path, exclude)?,
        Workspace::Inline {} => Default::default(),
    };
    validate_workspace_paths(
        overlay
            .clone()
            .into_iter()
            .map(|(path, _)| path)
            .chain(inputs.0.iter().map(|(path, _)| path.as_str())),
        inputs.1.iter().map(String::as_str),
    )?;
    copy_inputs(inputs, destination)?;
    write_workspace_files(destination, overlay)
}

/// Write `(path, source)` files into a fresh workspace at `root`; never replace existing files
/// or follow symlinks. Validate the paths with [`validate_workspace_paths`] first.
fn write_workspace_files<'a>(
    root: &Path,
    files: impl IntoIterator<Item = (&'a str, &'a str)>,
) -> Result<()> {
    ensure!(
        fs::symlink_metadata(root)?.is_dir(),
        "workspace root must be a real directory"
    );
    for (file, source) in files {
        let mut path = root.to_path_buf();
        let parts: Vec<_> = file.split('/').collect();
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
            .with_context(|| format!("materialize {file}"))?
            .write_all(source.as_bytes())?;
    }
    Ok(())
}

/// Checks every workspace path of an example as one set, before any is copied or written: each
/// is a portable relative path, and no two files, or a file and a directory, are the same path
/// after Unicode normalization and case folding.
pub(super) fn validate_workspace_paths<'a>(
    files: impl IntoIterator<Item = &'a str>,
    directories: impl IntoIterator<Item = &'a str>,
) -> Result<()> {
    let mut entries = HashMap::new();
    for (path, kind) in directories
        .into_iter()
        .map(|path| (path, WorkspacePathKind::Directory))
        .chain(
            files
                .into_iter()
                .map(|path| (path, WorkspacePathKind::File)),
        )
    {
        relative_path(path)?;
        for (separator, _) in path.match_indices('/') {
            insert_workspace_path(
                &mut entries,
                &path[..separator],
                WorkspacePathKind::Directory,
            )?;
        }
        insert_workspace_path(&mut entries, path, kind)?;
    }
    Ok(())
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum WorkspacePathKind {
    File,
    Directory,
}

fn insert_workspace_path<'a>(
    entries: &mut HashMap<String, (&'a str, WorkspacePathKind)>,
    path: &'a str,
    kind: WorkspacePathKind,
) -> Result<()> {
    let key: String = path.nfkc().case_fold().nfc().collect();
    if let Some((previous, previous_kind)) = entries.get(&key) {
        ensure!(
            kind == WorkspacePathKind::Directory && *previous_kind == kind && *previous == path,
            "duplicate or conflicting workspace path {path:?} with {previous:?}"
        );
        return Ok(());
    }
    // Keep normalized prefix conflicts conservative even when compatibility
    // normalization introduces a slash from a single authored component.
    ensure!(
        !entries
            .iter()
            .any(
                |(existing, (_, existing_kind))| (*existing_kind == WorkspacePathKind::File
                    && key.starts_with(&format!("{existing}/")))
                    || (kind == WorkspacePathKind::File
                        && existing.starts_with(&format!("{key}/")))
            ),
        "duplicate or conflicting workspace path {path:?}"
    );
    entries.insert(key, (path, kind));
    Ok(())
}

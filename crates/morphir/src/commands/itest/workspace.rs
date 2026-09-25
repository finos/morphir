//! Copy project inputs before running commands; never execute in the author's tree.
use super::{Scenario, model::Workspace};
use crate::notebook::{relative_path, validate_workspace_paths, write_workspace_files};
use anyhow::{Context, Result, ensure};
use std::{
    fs,
    path::{Path, PathBuf},
};

fn excluded(path: &Path, exclusions: &[String]) -> bool {
    path.components().any(|component| {
        matches!(
            component.as_os_str().to_str(),
            Some(".git" | "node_modules" | "target" | "elm-stuff" | "dist" | "out")
        )
    }) || path
        .file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| {
            name == "scenario.ipynb"
                || name == "scenarios.md"
                || name.ends_with(".feature")
                || name.ends_with(".feature.md")
        })
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

pub(super) fn materialize(scenario: &Scenario, destination: &Path) -> Result<()> {
    let Workspace::Directory { path, exclude } = &scenario.metadata.workspace else {
        return scenario.notebook.materialize(destination);
    };
    let inputs = collect_inputs(&scenario.directory, path, exclude)?;
    scenario.notebook.validate_additional_paths(
        inputs.0.iter().map(|(path, _)| path.as_str()),
        inputs.1.iter().map(String::as_str),
    )?;
    copy_inputs(inputs, destination)?;
    scenario.notebook.materialize(destination)
}

/// Materialize an example into `destination` from its directory `directory`, its `workspace`
/// and its `(path, source)` overlay files, which today's Markdown writes as `morphir:file`
/// fences. An inline workspace holds only the overlay files.
pub(super) fn materialize_example<'a>(
    directory: &Path,
    workspace: &Workspace,
    overlay: impl IntoIterator<Item = (&'a str, &'a str)> + Clone,
    destination: &Path,
) -> Result<()> {
    let inputs = match workspace {
        Workspace::Directory { path, exclude } => collect_inputs(directory, path, exclude)?,
        Workspace::Notebook {} => Default::default(),
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

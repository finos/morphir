//! Copy project inputs before running commands; never execute in the author's tree.
use super::{Scenario, model::Workspace};
use crate::notebook::relative_path;
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
        .is_some_and(|name| name == "scenario.ipynb" || name == "scenarios.md")
        || path.starts_with(".morphir/cache")
        || exclusions.iter().any(|excluded| path.starts_with(excluded))
}

fn source_directory(scenario: &Scenario, relative: &str) -> Result<PathBuf> {
    let mut source = scenario.directory.clone();
    if relative != "." {
        relative_path(relative)?;
        for component in Path::new(relative).components() {
            source.push(component);
            ensure!(
                fs::symlink_metadata(&source)?.is_dir(),
                "workspace source must be a real directory: {}",
                source.display()
            );
        }
    }
    ensure!(
        fs::symlink_metadata(&source)?.is_dir(),
        "workspace source must be a real directory: {}",
        source.display()
    );
    Ok(source)
}

pub(super) fn materialize(scenario: &Scenario, destination: &Path) -> Result<()> {
    let Workspace::Directory { path, exclude } = &scenario.metadata.workspace else {
        return scenario.notebook.materialize(destination);
    };
    let source = source_directory(scenario, path)?;
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
    scenario.notebook.validate_additional_paths(
        files.iter().map(|(path, _)| path.as_str()),
        directories.iter().map(String::as_str),
    )?;
    for directory in directories {
        fs::create_dir_all(destination.join(directory))?;
    }
    for (path, source) in files {
        fs::copy(&source, destination.join(&path))
            .with_context(|| format!("copy workspace input {path}"))?;
    }
    scenario.notebook.materialize(destination)
}

// Copyright 2026 FINOS
// SPDX-License-Identifier: Apache-2.0
use super::{Files, Result, generate::INPUT_DIGESTS};
use std::{
    collections::BTreeSet,
    fs,
    io::Write,
    path::{Component, Path, PathBuf},
};
fn absolute(path: &Path) -> Result<PathBuf> {
    let path = std::path::absolute(path)?;
    let mut result = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                result.pop();
            }
            _ => result.push(part.as_os_str()),
        }
    }
    Ok(result)
}
fn reject_symlinks(path: &Path) -> Result<()> {
    let mut current = PathBuf::new();
    for part in absolute(path)?.components() {
        current.push(part.as_os_str());
        match fs::symlink_metadata(&current) {
            Ok(meta) if meta.is_symlink() => {
                return Err(format!("Symlink is not allowed: {}", current.display()).into());
            }
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}
fn validate_paths(files: &Files) -> Result<()> {
    for path in files.keys() {
        if Path::new(path).is_absolute()
            || path.contains(['\\', '\0'])
            || path.split('/').any(|p| matches!(p, "" | "." | ".."))
        {
            return Err(format!("Invalid fixture path: {path}").into());
        }
    }
    Ok(())
}
pub fn read_inputs(source: &Path) -> Result<Files> {
    INPUT_DIGESTS
        .iter()
        .map(|(path, _)| {
            let input = absolute(&source.join(path))?;
            reject_symlinks(&input)?;
            if !fs::symlink_metadata(&input)
                .map_err(|e| format!("Missing fixture input file: {path}: {e}"))?
                .is_file()
            {
                return Err(format!("Expected fixture input file: {path}").into());
            }
            Ok(((*path).to_owned(), fs::read(input)?))
        })
        .collect()
}
pub fn write_files(output: &Path, files: &Files, source: &Path) -> Result<()> {
    let output_path = absolute(output)?;
    let output = output_path.as_path();
    validate_paths(files)?;
    reject_symlinks(output)?;
    reject_symlinks(source)?;
    if absolute(output)? == absolute(source)? {
        return Err("Fixture output must not alias its source".into());
    }
    fs::create_dir_all(output)?;
    if fs::read_dir(output)?.next().is_some() {
        return Err("Fixture output must be empty".into());
    }
    for (path, bytes) in files {
        let target = output.join(path);
        reject_symlinks(&target)?;
        fs::create_dir_all(target.parent().ok_or("fixture parent")?)?;
        fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(target)?
            .write_all(bytes)?;
    }
    Ok(())
}
fn visit(
    root: &Path,
    relative: &str,
    files: &mut Files,
    dirs: &mut BTreeSet<String>,
) -> Result<()> {
    for entry in fs::read_dir(root.join(relative))? {
        let entry = entry?;
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| "Non-UTF8 fixture path")?;
        let path = if relative.is_empty() {
            name
        } else {
            format!("{relative}/{name}")
        };
        let kind = entry.file_type()?;
        if kind.is_symlink() {
            return Err(format!("Symlink is not allowed: {path}").into());
        }
        if kind.is_dir() {
            dirs.insert(path.clone());
            visit(root, &path, files, dirs)?;
        } else if kind.is_file() {
            files.insert(path, fs::read(entry.path())?);
        } else {
            return Err(format!("Unexpected fixture entry: {path}").into());
        }
    }
    Ok(())
}
pub fn read_files(root: &Path) -> Result<Files> {
    let root_path = absolute(root)?;
    let root = root_path.as_path();
    reject_symlinks(root)?;
    let mut files = Files::new();
    visit(root, "", &mut files, &mut BTreeSet::new())?;
    Ok(files)
}
pub fn check_files(root: &Path, expected: &Files) -> Result<()> {
    let root_path = absolute(root)?;
    let root = root_path.as_path();
    validate_paths(expected)?;
    reject_symlinks(root)?;
    let mut actual = Files::new();
    let mut dirs = BTreeSet::new();
    visit(root, "", &mut actual, &mut dirs)?;
    for dir in dirs {
        if !expected.keys().any(|p| p.starts_with(&format!("{dir}/"))) {
            return Err(format!("Unexpected fixture directory: {dir}").into());
        }
    }
    for path in actual.keys() {
        if path != "README.md" && !expected.contains_key(path) {
            return Err(format!("Unexpected fixture file: {path}").into());
        }
    }
    for (path, bytes) in expected {
        match actual.get(path) {
            None => return Err(format!("Missing fixture file: {path}").into()),
            Some(actual) if actual != bytes => {
                return Err(format!("Fixture bytes differ: {path}").into());
            }
            Some(_) => {}
        }
    }
    Ok(())
}

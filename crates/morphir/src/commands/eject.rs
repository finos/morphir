//! Copy a task's declared value to a user path after the run.

use crate::error::CliError;
use morphir_devkit::{TaskPaths, TaskResult};
use std::path::{Component, Path, PathBuf};

/// What one eject did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EjectReport {
    /// Absolute target directory.
    pub target: PathBuf,
    /// `value` entries copied.
    pub copied: Vec<String>,
    /// Entries from the previous eject that were removed as stale.
    pub removed: Vec<String>,
}

/// Eject the task's `value` entries into `target`, removing entries this
/// function ejected there before that are no longer in `value`.
///
/// Every entry — from the current `value` and from the previous eject's
/// bookkeeping — is checked before anything is touched: an absolute path or a
/// path containing `..` is rejected outright, since joining it onto `target`
/// could name a location outside `target` and this function deletes what it
/// names. See `validate_entry`.
pub fn eject(paths: &TaskPaths, target: &Path) -> Result<EjectReport, CliError> {
    let mut record = TaskResult::read(&paths.result)
        .map_err(|error| CliError::Config { error })?
        .ok_or_else(|| CliError::Validation {
            message: format!(
                "no result record at {}; the task did not complete",
                paths.result.display()
            ),
        })?;

    for entry in &record.value {
        validate_entry(entry)?;
    }
    let key = target.to_string_lossy().into_owned();
    let previous = record.ejected.get(&key).cloned().unwrap_or_default();
    for entry in &previous {
        validate_entry(entry)?;
    }

    std::fs::create_dir_all(target).map_err(|error| CliError::FileSystem { error })?;

    let mut removed = Vec::new();
    for stale in previous
        .iter()
        .filter(|entry| !record.value.contains(entry))
    {
        let path = target.join(stale);
        remove_entry(&path)?;
        prune_empty_parents(&path, target)?;
        removed.push(stale.clone());
    }

    let mut copied = Vec::new();
    for entry in &record.value {
        let source = paths.dest.join(entry);
        let destination = target.join(entry);
        if source.is_dir() {
            remove_entry(&destination)?;
            copy_dir(&source, &destination)?;
        } else {
            if let Some(parent) = destination.parent() {
                std::fs::create_dir_all(parent).map_err(|error| CliError::FileSystem { error })?;
            }
            std::fs::copy(&source, &destination).map_err(|error| CliError::FileSystem { error })?;
        }
        copied.push(entry.clone());
    }

    record.ejected.insert(key, record.value.clone());
    record
        .write(&paths.result)
        .map_err(|error| CliError::Config { error })?;
    Ok(EjectReport {
        target: target.to_path_buf(),
        copied,
        removed,
    })
}

/// Eject when `-o` was given. Relative targets resolve against `cwd`.
pub fn maybe_eject(
    paths: &TaskPaths,
    output: Option<&str>,
    cwd: &Path,
) -> Result<Option<String>, CliError> {
    let Some(output) = output else {
        return Ok(None);
    };
    let target = Path::new(output);
    let target = if target.is_absolute() {
        target.to_path_buf()
    } else {
        cwd.join(target)
    };
    let report = eject(paths, &target)?;
    Ok(Some(report.target.to_string_lossy().into_owned()))
}

/// Reject a `value`/`ejected` entry that could name a location outside
/// `target` once joined onto it: an absolute path (`PathBuf::join` discards
/// the base entirely when the joined path is absolute) or any path
/// containing a `..` component. Also rejects an entry with no real path
/// component at all (empty string or bare `.`), which would otherwise name
/// `target` itself.
fn validate_entry(entry: &str) -> Result<(), CliError> {
    let path = Path::new(entry);
    let mut has_normal_component = false;
    for component in path.components() {
        match component {
            Component::Normal(_) => has_normal_component = true,
            Component::CurDir => {}
            Component::ParentDir => {
                return Err(CliError::Validation {
                    message: format!(
                        "task result entry '{entry}' contains '..'; refusing to eject it"
                    ),
                });
            }
            Component::RootDir | Component::Prefix(_) => {
                return Err(CliError::Validation {
                    message: format!(
                        "task result entry '{entry}' is an absolute path; refusing to eject it"
                    ),
                });
            }
        }
    }
    if !has_normal_component {
        return Err(CliError::Validation {
            message: format!(
                "task result entry '{entry}' does not name a path under the eject target; refusing to eject it"
            ),
        });
    }
    Ok(())
}

fn remove_entry(path: &Path) -> Result<(), CliError> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_dir() => {
            std::fs::remove_dir_all(path).map_err(|error| CliError::FileSystem { error })
        }
        Ok(_) => std::fs::remove_file(path).map_err(|error| CliError::FileSystem { error }),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(CliError::FileSystem { error }),
    }
}

fn prune_empty_parents(path: &Path, stop: &Path) -> Result<(), CliError> {
    let mut current = path.parent();
    while let Some(dir) = current {
        if dir == stop || !dir.starts_with(stop) {
            break;
        }
        match std::fs::remove_dir(dir) {
            Ok(()) => current = dir.parent(),
            Err(_) => break,
        }
    }
    Ok(())
}

fn copy_dir(source: &Path, destination: &Path) -> Result<(), CliError> {
    std::fs::create_dir_all(destination).map_err(|error| CliError::FileSystem { error })?;
    for entry in std::fs::read_dir(source).map_err(|error| CliError::FileSystem { error })? {
        let entry = entry.map_err(|error| CliError::FileSystem { error })?;
        let target = destination.join(entry.file_name());
        let file_type = entry
            .file_type()
            .map_err(|error| CliError::FileSystem { error })?;
        if file_type.is_dir() {
            copy_dir(&entry.path(), &target)?;
        } else {
            std::fs::copy(entry.path(), &target).map_err(|error| CliError::FileSystem { error })?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_devkit::{TaskId, TaskPaths, TaskResult};
    use std::path::Path;

    fn task_with_value(root: &Path, value: &[&str]) -> TaskPaths {
        let paths = TaskPaths::new(root, Path::new(""), &TaskId::compile());
        std::fs::create_dir_all(paths.dest.join("parse")).unwrap();
        std::fs::write(paths.dest.join("morphir-ir.json"), "{}").unwrap();
        std::fs::write(paths.dest.join("parse/main.json"), "{}").unwrap();
        std::fs::create_dir_all(paths.dest.join("morphir-ir/pkg")).unwrap();
        std::fs::write(paths.dest.join("morphir-ir/manifest.yaml"), "a: 1").unwrap();
        std::fs::write(paths.dest.join("morphir-ir/pkg/x.yaml"), "b: 2").unwrap();
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = value.iter().map(|entry| (*entry).to_owned()).collect();
        record.write(&paths.result).unwrap();
        paths
    }

    #[test]
    fn copies_only_value_entries() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        let report = eject(&paths, &target).unwrap();
        assert!(target.join("morphir-ir.json").is_file());
        assert!(!target.join("parse").exists());
        assert_eq!(report.copied, vec!["morphir-ir.json".to_owned()]);
        let record = TaskResult::read(&paths.result).unwrap().unwrap();
        assert_eq!(
            record.ejected[&target.to_string_lossy().into_owned()],
            vec!["morphir-ir.json".to_owned()]
        );
    }

    #[test]
    fn directory_entries_copy_recursively() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        eject(&paths, &target).unwrap();
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());
    }

    #[test]
    fn re_eject_removes_stale_entries_and_keeps_foreign_files() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = task_with_value(&root, &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        eject(&paths, &target).unwrap();
        std::fs::write(target.join("README.md"), "mine").unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = vec!["morphir-ir".to_owned()];
        record.write(&paths.result).unwrap();
        let report = eject(&paths, &target).unwrap();

        assert!(!target.join("morphir-ir.json").exists());
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("README.md").is_file());
        assert_eq!(report.removed, vec!["morphir-ir.json".to_owned()]);
    }

    #[test]
    fn re_eject_removes_a_stale_directory_entry_and_keeps_a_foreign_directory_beside_it() {
        // Same property as `re_eject_removes_stale_entries_and_keeps_foreign_files`,
        // but for a directory entry: a foreign directory placed inside the
        // stale entry's parent must block pruning of that parent, and a
        // foreign top-level directory must be untouched.
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = TaskPaths::new(&root, Path::new(""), &TaskId::compile());
        std::fs::create_dir_all(paths.dest.join("sub/report/pkg")).unwrap();
        std::fs::write(paths.dest.join("sub/report/pkg/x.yaml"), "b: 2").unwrap();
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = vec!["sub/report".to_owned()];
        record.write(&paths.result).unwrap();

        let target = temp.path().join("dist");
        eject(&paths, &target).unwrap();
        assert!(target.join("sub/report/pkg/x.yaml").is_file());

        // A foreign file inside the entry's parent directory, and a foreign
        // top-level directory unrelated to any entry.
        std::fs::write(target.join("sub/keepme.txt"), "mine").unwrap();
        std::fs::create_dir_all(target.join("mine/nested")).unwrap();
        std::fs::write(target.join("mine/nested/file.txt"), "mine too").unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = Vec::new();
        record.write(&paths.result).unwrap();
        let report = eject(&paths, &target).unwrap();

        assert!(!target.join("sub/report").exists());
        assert_eq!(report.removed, vec!["sub/report".to_owned()]);
        // The foreign file blocked pruning of `sub`, so `sub` and its foreign
        // content survive even though the entry that used to live there is gone.
        assert!(target.join("sub").is_dir());
        assert!(target.join("sub/keepme.txt").is_file());
        // The unrelated foreign directory tree is completely untouched.
        assert!(target.join("mine/nested/file.txt").is_file());
    }

    #[test]
    fn value_entries_that_could_escape_the_target_are_rejected_without_touching_disk() {
        let temp = tempfile::tempdir().unwrap();
        let target = temp.path().join("dist");
        let foreign = temp.path().join("foreign_target");
        std::fs::create_dir_all(&foreign).unwrap();
        std::fs::write(foreign.join("secret.txt"), "do not touch").unwrap();

        for bad_entry in [
            "../foreign_target/secret.txt",
            "sub/../../foreign_target/secret.txt",
        ] {
            let paths = task_with_value(&temp.path().join("out"), &[bad_entry]);
            let error = eject(&paths, &target).unwrap_err();
            assert!(error.to_string().contains(".."), "{error}");
            assert!(!target.exists(), "target must not be created on rejection");
        }

        // An absolute-path entry is rejected the same way.
        let absolute_entry_text = foreign.join("secret.txt");
        let absolute_entry_text = absolute_entry_text.to_string_lossy().into_owned();
        let paths = task_with_value(&temp.path().join("out2"), &[&absolute_entry_text]);
        let error = eject(&paths, &target).unwrap_err();
        assert!(error.to_string().contains("absolute"), "{error}");
        assert!(!target.exists());

        // The foreign file was never touched.
        assert_eq!(
            std::fs::read_to_string(foreign.join("secret.txt")).unwrap(),
            "do not touch"
        );
    }

    #[test]
    fn missing_record_is_an_error() {
        let temp = tempfile::tempdir().unwrap();
        let paths = TaskPaths::new(temp.path(), Path::new(""), &TaskId::compile());
        let error = eject(&paths, &temp.path().join("dist")).unwrap_err();
        assert!(error.to_string().contains("no result record"), "{error}");
    }

    #[test]
    fn maybe_eject_resolves_relative_targets_against_cwd() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        assert_eq!(maybe_eject(&paths, None, temp.path()).unwrap(), None);
        let ejected = maybe_eject(&paths, Some("dist/ir"), temp.path())
            .unwrap()
            .unwrap();
        assert_eq!(ejected, temp.path().join("dist/ir").to_string_lossy());
        assert!(temp.path().join("dist/ir/morphir-ir.json").is_file());
    }
}

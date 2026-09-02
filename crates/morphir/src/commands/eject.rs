//! Copy a task's declared value to a user path after the run.

use crate::error::CliError;
use morphir_devkit::{TaskPaths, TaskResult};
use std::path::{Component, Path, PathBuf};

/// What one eject did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EjectReport {
    /// Absolute target directory.
    pub target: PathBuf,
    /// `value` entries copied (entry names, e.g. `morphir-ir` for a
    /// directory-valued entry — not the individual files beneath it).
    pub copied: Vec<String>,
    /// Files this function wrote under `target` on a previous eject, paths
    /// relative to `target`, that were actually deleted because the
    /// current `value` no longer produces them. A path only appears here if
    /// something was really removed; a stale bookkeeping entry whose file
    /// was already gone (deleted by the user, or by an earlier failed run)
    /// is not reported as a removal.
    pub removed: Vec<String>,
}

/// Eject the task's `value` entries into `target`.
///
/// What `ejected[target]` remembers, and why it is files and not entries:
/// a directory-valued entry (a document-tree IR, for example) is merged
/// into `target` rather than replacing whatever is already there, because
/// `target` may hold a directory the user created before this function ever
/// ran. If bookkeeping recorded the *entry name* as owned, a later eject
/// would see that name in its own history and feel entitled to delete the
/// whole directory — including content this function never wrote. So
/// instead this function flattens `value` into the individual files it
/// actually writes under `target` (`flatten_value_files`) and remembers
/// exactly that list. A later eject only ever deletes files that are in the
/// old flattened list and not in the new one, and only ever deletes files —
/// never a directory wholesale — so foreign content survives no matter how
/// many times eject runs.
///
/// Every entry in `value`, and every file path from a previous eject's
/// bookkeeping, is checked before anything is touched: an absolute path or a
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
    let previous_files = record.ejected.get(&key).cloned().unwrap_or_default();
    for file in &previous_files {
        validate_entry(file)?;
    }

    std::fs::create_dir_all(target).map_err(|error| CliError::FileSystem { error })?;
    let canonical_target =
        std::fs::canonicalize(target).map_err(|error| CliError::FileSystem { error })?;

    let new_files = flatten_value_files(paths, &record.value)?;

    // Remove exactly the files this function wrote here before that the
    // current `value` no longer produces. A directory entry is never
    // deleted wholesale — only the individual files this function is
    // recorded as owning — so a directory the user already had before the
    // first eject, or a file the user added beside/inside an owned
    // directory afterward, is never at risk.
    let mut removed = Vec::new();
    for stale in previous_files
        .iter()
        .filter(|file| !new_files.contains(file))
    {
        let path = target.join(stale);
        if remove_confined(&path, target, &canonical_target)? {
            prune_empty_parents(&path, target)?;
            removed.push(stale.clone());
        }
    }

    let mut copied = Vec::new();
    for entry in &record.value {
        let source = paths.dest.join(entry);
        let destination = target.join(entry);
        if source.is_dir() {
            // Always merge: a directory-valued entry never had the
            // destination wiped first, whether this is the first time it
            // has been ejected here or the tenth, so any foreign content in
            // it survives regardless.
            copy_dir(&source, &destination)?;
        } else {
            if let Some(parent) = destination.parent() {
                std::fs::create_dir_all(parent).map_err(|error| CliError::FileSystem { error })?;
            }
            std::fs::copy(&source, &destination).map_err(|error| CliError::FileSystem { error })?;
        }
        copied.push(entry.clone());
    }

    record.ejected.insert(key, new_files);
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

/// Reject a `value` entry or an `ejected` file path that could name a
/// location outside `target` once joined onto it: an absolute path
/// (`PathBuf::join` discards the base entirely when the joined path is
/// absolute) or any path containing a `..` component. Also rejects an entry
/// with no real path component at all (empty string or bare `.`), which
/// would otherwise name `target` itself.
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

/// Remove `path` if it exists, first confirming its containing directory
/// still resolves under `canonical_target` (the canonicalized `target`).
/// Returns whether anything was actually removed, so callers never report a
/// removal that did not happen.
///
/// `symlink_metadata` on `path` only protects against `path` itself being a
/// symlink; it does not stop a symlinked *intermediate* directory (e.g.
/// `target/sub -> /elsewhere`) from redirecting `remove_dir_all`/`remove_file`
/// onto a location outside `target`. Canonicalizing `path`'s parent and
/// checking it against the canonicalized target catches that: a legitimate
/// removal's parent always resolves inside the target, while a symlinked
/// intermediate resolves elsewhere. `target` itself may legitimately be a
/// symlink (the user's `-o` can point at one), so both sides are
/// canonicalized before comparing — comparing `path` directly against the
/// non-canonical `target` would reject that legitimate case.
///
/// This check is advisory, not a security boundary: it catches accidental or
/// stale symlinks sitting in the target, not a hostile actor. It is
/// inherently TOCTOU-racy — nothing stops a symlink from being swapped in
/// between the `canonicalize` call here and the removal syscall below.
/// Closing that fully would need descriptor-relative removal (an `openat`/
/// `unlinkat` chain anchored at a handle opened on `target`), which this
/// function does not attempt.
fn remove_confined(path: &Path, target: &Path, canonical_target: &Path) -> Result<bool, CliError> {
    let parent = path.parent().unwrap_or(target);
    let canonical_parent = match std::fs::canonicalize(parent) {
        Ok(canonical_parent) => canonical_parent,
        // The parent does not exist, so there is nothing under it to remove.
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(CliError::FileSystem { error }),
    };
    if !canonical_parent.starts_with(canonical_target) {
        return Err(CliError::Validation {
            message: format!(
                "refusing to remove '{}': its containing directory resolves to '{}', \
                 which is outside the eject target '{}' (resolved to '{}')",
                path.display(),
                canonical_parent.display(),
                target.display(),
                canonical_target.display()
            ),
        });
    }
    remove_entry(path)
}

/// Remove `path` (file or directory) if it exists. Returns whether anything
/// was actually removed.
fn remove_entry(path: &Path) -> Result<bool, CliError> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_dir() => std::fs::remove_dir_all(path)
            .map(|()| true)
            .map_err(|error| CliError::FileSystem { error }),
        Ok(_) => std::fs::remove_file(path)
            .map(|()| true)
            .map_err(|error| CliError::FileSystem { error }),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(CliError::FileSystem { error }),
    }
}

/// Every file `record.value` produces, as paths relative to `target`. A
/// file entry contributes itself; a directory entry contributes every file
/// beneath it, walked recursively. This is exactly the set of files `eject`
/// writes under `target` this run, so it is also exactly what
/// `ejected[target]` should remember owning — see the `eject` doc comment.
fn flatten_value_files(paths: &TaskPaths, value: &[String]) -> Result<Vec<String>, CliError> {
    let mut files = Vec::new();
    for entry in value {
        let source = paths.dest.join(entry);
        if source.is_dir() {
            collect_files(&source, Path::new(entry), &mut files)?;
        } else {
            files.push(entry.clone());
        }
    }
    Ok(files)
}

/// Recursively collect the files under `source` into `files`, naming each
/// one with `relative` (the entry's own relative path) joined onto its path
/// within `source`.
fn collect_files(source: &Path, relative: &Path, files: &mut Vec<String>) -> Result<(), CliError> {
    let mut children = std::fs::read_dir(source)
        .map_err(|error| CliError::FileSystem { error })?
        .collect::<Result<Vec<_>, std::io::Error>>()
        .map_err(|error| CliError::FileSystem { error })?;
    children.sort_by_key(std::fs::DirEntry::file_name);
    for child in children {
        let file_type = child
            .file_type()
            .map_err(|error| CliError::FileSystem { error })?;
        let child_relative = relative.join(child.file_name());
        if file_type.is_dir() {
            collect_files(&child.path(), &child_relative, files)?;
        } else {
            files.push(child_relative.to_string_lossy().into_owned());
        }
    }
    Ok(())
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
        // `removed` is now file-level bookkeeping: the one file this
        // function actually wrote and deleted, not the entry name.
        assert_eq!(report.removed, vec!["sub/report/pkg/x.yaml".to_owned()]);
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
    fn previous_ejected_entries_that_could_escape_the_target_are_also_rejected() {
        // `validate_entry` runs over both `record.value` (covered above) and
        // the bookkeeping list from a prior eject to this target
        // (`record.ejected`). Exercise the second loop specifically: a
        // clean `value` with a malicious entry sitting only in `ejected`.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &[]);
        let target = temp.path().join("dist");

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.ejected.insert(
            target.to_string_lossy().into_owned(),
            vec!["../escape.txt".to_owned()],
        );
        record.write(&paths.result).unwrap();

        let error = eject(&paths, &target).unwrap_err();
        assert!(error.to_string().contains(".."), "{error}");
    }

    #[test]
    fn degenerate_value_entries_are_rejected() {
        // An empty entry, or one made only of `.` components, has no real
        // path segment and would otherwise resolve to `target` itself.
        for degenerate in ["", "."] {
            let temp = tempfile::tempdir().unwrap();
            let paths = task_with_value(&temp.path().join("out"), &[degenerate]);
            let target = temp.path().join("dist");
            let error = eject(&paths, &target).unwrap_err();
            assert!(
                error.to_string().contains("does not name a path"),
                "{error}"
            );
        }
    }

    #[test]
    fn first_eject_merges_into_a_foreign_directory_without_deleting_it() {
        // A directory-valued entry is always merged into, never wiped
        // first, whether or not anything has been ejected here before. If
        // the user already has their own directory at that path, it must be
        // merged into — not deleted — since this function never put it
        // there.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("morphir-ir")).unwrap();
        std::fs::write(target.join("morphir-ir/mine.txt"), "not yours").unwrap();

        eject(&paths, &target).unwrap();

        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/mine.txt")).unwrap(),
            "not yours",
            "a foreign file inside a first-time directory entry must survive"
        );
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());
    }

    #[test]
    fn second_eject_after_merging_into_a_foreign_directory_still_keeps_the_foreign_file() {
        // Regression for the bug in the round-1 fix: merging into a user's
        // pre-existing directory on the FIRST eject kept `mine.txt`, but
        // bookkeeping then recorded the whole entry name as owned, so the
        // SECOND eject saw the entry in its own history and wiped the
        // directory anyway. Bookkeeping now tracks individual files, so the
        // foreign file must survive any number of ejects, not just the
        // first.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("morphir-ir")).unwrap();
        std::fs::write(target.join("morphir-ir/mine.txt"), "not yours").unwrap();

        eject(&paths, &target).unwrap();
        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/mine.txt")).unwrap(),
            "not yours"
        );

        eject(&paths, &target).unwrap();

        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/mine.txt")).unwrap(),
            "not yours",
            "a foreign file must survive a SECOND eject, not just the first"
        );
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());
    }

    #[test]
    fn second_eject_of_a_directory_entry_removes_a_file_no_longer_produced() {
        // Once a directory entry has been ejected here before, a re-eject
        // of it must still drop a file the task produced last time but not
        // this time — but only that file: a sibling file the task still
        // produces, and a foreign file the user has placed inside the same
        // directory, must both survive.
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = task_with_value(&root, &["morphir-ir"]);
        let target = temp.path().join("dist");
        eject(&paths, &target).unwrap();
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());

        std::fs::write(target.join("morphir-ir/foreign.txt"), "mine").unwrap();
        std::fs::remove_file(paths.dest.join("morphir-ir/pkg/x.yaml")).unwrap();
        eject(&paths, &target).unwrap();

        assert!(
            !target.join("morphir-ir/pkg/x.yaml").exists(),
            "a file dropped from a directory this function owns must not survive a re-eject"
        );
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/foreign.txt")).unwrap(),
            "mine",
            "a foreign file inside an owned directory must survive a re-eject"
        );
    }

    #[test]
    fn removed_only_lists_files_actually_deleted() {
        // If a previously-ejected file is already gone by the time a stale
        // eject runs (the user deleted it, or an earlier run failed
        // partway), that is not a removal this call performed and must not
        // be claimed in the report.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        eject(&paths, &target).unwrap();
        std::fs::remove_file(target.join("morphir-ir.json")).unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = Vec::new();
        record.write(&paths.result).unwrap();
        let report = eject(&paths, &target).unwrap();

        assert!(
            report.removed.is_empty(),
            "nothing was actually removed by this call: {:?}",
            report.removed
        );
    }

    #[cfg(unix)]
    #[test]
    fn stale_removal_refuses_to_delete_through_a_symlinked_intermediate_directory() {
        use std::os::unix::fs::symlink;

        // `dist/sub` is a symlink to a directory the eject target does not
        // own. A stale entry `sub/report` would make `remove_dir_all` land
        // on `outside/report` through that symlink even though
        // `symlink_metadata` on the final component (`report`) sees an
        // ordinary directory. `remove_confined` must refuse instead.
        let temp = tempfile::tempdir().unwrap();
        let outside = temp.path().join("outside");
        std::fs::create_dir_all(outside.join("report")).unwrap();
        std::fs::write(outside.join("report/marker.txt"), "safe").unwrap();

        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        symlink(&outside, target.join("sub")).unwrap();

        let paths = TaskPaths::new(&temp.path().join("out"), Path::new(""), &TaskId::compile());
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = Vec::new();
        record.ejected.insert(
            target.to_string_lossy().into_owned(),
            vec!["sub/report".to_owned()],
        );
        record.write(&paths.result).unwrap();

        let error = eject(&paths, &target).unwrap_err();
        assert!(
            error.to_string().contains("outside the eject target"),
            "{error}"
        );
        assert_eq!(
            std::fs::read_to_string(outside.join("report/marker.txt")).unwrap(),
            "safe",
            "the symlink escape must not let removal reach outside the target"
        );
    }

    #[cfg(unix)]
    #[test]
    fn ejecting_into_a_symlinked_target_still_works() {
        // The target itself may legitimately be a symlink (`-o` pointed at
        // one); that must keep working since it is not an escape.
        use std::os::unix::fs::symlink;

        let temp = tempfile::tempdir().unwrap();
        let real_target = temp.path().join("real_dist");
        std::fs::create_dir_all(&real_target).unwrap();
        let target = temp.path().join("dist_link");
        symlink(&real_target, &target).unwrap();

        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        eject(&paths, &target).unwrap();

        assert!(real_target.join("morphir-ir.json").is_file());
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

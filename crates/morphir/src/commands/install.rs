//! Copy a task's declared value to a user path after the run.

use crate::commands::out_context::TaskLock;
use crate::error::CliError;
use morphir_devkit::{TaskPaths, TaskResult};
use same_file::Handle;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Component, Path, PathBuf};

/// What one install did.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallReport {
    /// Absolute target directory.
    pub target: PathBuf,
    /// `value` entries copied (entry names, e.g. `morphir-ir` for a
    /// directory-valued entry — not the individual files beneath it).
    pub copied: Vec<String>,
    /// Files this function wrote under `target` on a previous install, paths
    /// relative to `target`, that were actually deleted because the
    /// current `value` no longer produces them. A path only appears here if
    /// something was really removed; a stale bookkeeping entry whose file
    /// was already gone (deleted by the user, or by an earlier failed run)
    /// is not reported as a removal.
    pub removed: Vec<String>,
}

/// Install the task's `value` entries into `target`.
///
/// What `installed[target]` remembers, and why it is files and not entries:
/// a directory-valued entry (a document-tree IR, for example) is merged
/// into `target` rather than replacing whatever is already there, because
/// `target` may hold a directory the user created before this function ever
/// ran. If bookkeeping recorded the *entry name* as owned, a later install
/// would see that name in its own history and feel entitled to delete the
/// whole directory — including content this function never wrote. So
/// instead this function flattens `value` into the individual files it
/// actually writes under `target` (`flatten_value_files`) and remembers
/// exactly that list. A later install only ever deletes files that are in the
/// old flattened list and not in the new one, and only ever deletes files —
/// never a directory wholesale — so foreign content survives no matter how
/// many times install runs.
///
/// Every entry in `value`, and every file path from a previous install's
/// bookkeeping, is checked before anything is touched: an absolute path or a
/// path containing `..` is rejected outright, since joining it onto `target`
/// could name a location outside `target` and this function deletes what it
/// names. See `validate_entry`.
///
/// Text alone does not settle where a path leads, though, so every destination
/// is also resolved against the filesystem before the first byte is written:
/// see `confined_destination`. Both checks run in the pre-flight scan, so an
/// install that is going to be refused writes nothing at all.
///
/// All of that runs under an exclusive lock on the install target, taken as
/// soon as the target is canonicalized and held until the ledger is written.
/// `out_root` is where that lock file lives; see `install_lock_path` for why
/// it is keyed on the target rather than on the task, and why it is not
/// written into the target itself.
pub fn install(
    paths: &TaskPaths,
    target: &Path,
    out_root: &Path,
) -> Result<InstallReport, CliError> {
    let mut record = TaskResult::read(&paths.result)
        .map_err(|error| CliError::Config { error })?
        .ok_or_else(|| CliError::Validation {
            message: format!(
                "no result record at {}; the task did not complete",
                paths.result.display()
            ),
        })?;

    // A tombstone (see `out_context::prepare_dest`) is what a run that
    // started but did not finish leaves behind: no product, but the ledger of
    // what earlier runs installed. Installing from one would delete every
    // file in that ledger and write the ledger back empty. Every caller today
    // runs `install` right after writing a successful record, so a tombstone
    // cannot actually reach this function, but the guard keeps that true if a
    // future caller changes.
    //
    // An empty `value` on a record that is NOT a tombstone is a different
    // thing entirely: a run that succeeded and produced nothing. That
    // installs normally, which means it retires everything the previous run
    // put at this target and records an empty ledger.
    if record.tombstone {
        return Err(CliError::Validation {
            message: format!(
                "task result at {} is a tombstone: the task has no completed product; \
                 run it first",
                paths.result.display()
            ),
        });
    }

    for entry in &record.value {
        validate_entry(entry)?;
    }

    reject_non_directory_target(target)?;
    std::fs::create_dir_all(target).map_err(|error| CliError::FileSystem { error })?;
    let canonical_target =
        std::fs::canonicalize(target).map_err(|error| CliError::FileSystem { error })?;
    reject_target_inside_dest(&canonical_target, &paths.dest)?;

    // Everything from here on — the conflict scan, the stale removals, the
    // copies, and the ledger write — runs with this held. Dropped when the
    // function returns, whichever way it returns.
    let _target_lock = TaskLock::acquire(
        &install_lock_path(out_root, &canonical_target),
        "installing to this target",
    )?;

    // Keyed on the canonical target, not the raw `-o` string, so `dist` and
    // `./dist` (or any other two spellings of the same directory) share one
    // bookkeeping entry instead of shadowing each other.
    let key = canonical_target.to_string_lossy().into_owned();
    let previous_files = record.installed.get(&key).cloned().unwrap_or_default();
    for file in &previous_files {
        validate_entry(file)?;
    }

    let new_files = flatten_value_files(paths, &record.value)?;
    let new_files_lookup: HashSet<&str> = new_files.iter().map(String::as_str).collect();

    // Before touching anything: every location this run would create or write
    // has to resolve inside the target. A symlink already sitting in the
    // target redirects `create_dir_all` and `fs::copy` without any of the
    // textual checks above noticing. The entries themselves are checked as
    // well as the flattened files, because a directory entry with nothing
    // under it flattens to no files at all and would still have
    // `copy_dir` create it.
    for destination in new_files.iter().chain(record.value.iter()) {
        confined_destination(destination, target, &canonical_target)?;
    }

    // Before touching anything: a file this run would write that already
    // exists at the destination and is NOT one this function wrote last time
    // is foreign content — it belongs to the user, not to a previous install.
    // Copying over it would silently overwrite it, and a later run whose
    // artifact set shrinks would then delete it as if it were ours. Refuse
    // the whole install instead, before any copy or removal, so the target is
    // left exactly as it was.
    let previous_files_lookup: HashSet<&str> = previous_files.iter().map(String::as_str).collect();
    let unmatched: Vec<&String> = new_files
        .iter()
        .filter(|file| !previous_files_lookup.contains(file.as_str()))
        .filter(|file| std::fs::symlink_metadata(target.join(file)).is_ok())
        .collect();
    // A destination the ledger does not name may still be a file the ledger
    // owns, written under a different spelling. See `renamed_previous_files`.
    let renamed = renamed_previous_files(target, &previous_files, &unmatched)?;
    let renamed_to: HashSet<&str> = renamed.values().map(String::as_str).collect();
    let mut conflicts: Vec<String> = unmatched
        .into_iter()
        .filter(|file| !renamed_to.contains(file.as_str()))
        .cloned()
        .collect();
    if !conflicts.is_empty() {
        conflicts.sort();
        return Err(CliError::Validation {
            message: format!(
                "install target '{}' already contains files Morphir did not write: {}; \
                 move them aside or choose a different -o target",
                target.display(),
                conflicts.join(", ")
            ),
        });
    }

    // Before touching anything: every directory between the target and a
    // file this function wrote must still be a real directory. See
    // `reject_symlinked_ancestors`.
    for file in &previous_files {
        reject_symlinked_ancestors(file, target)?;
    }

    // Remove exactly the files this function wrote here before that the
    // current `value` no longer produces. A directory entry is never
    // deleted wholesale — only the individual files this function is
    // recorded as owning — so a directory the user already had before the
    // first install, or a file the user added beside/inside an owned
    // directory afterward, is never at risk. `remove_confined` itself
    // refuses to remove anything that turns out to be a directory (see its
    // doc comment), which also protects against a record written by an
    // older build of this scheme that still names a directory entry rather
    // than a flattened file path.
    let mut removed = Vec::new();
    for stale in previous_files
        .iter()
        .filter(|file| !new_files_lookup.contains(file.as_str()))
        // A ledger entry this run is about to rewrite under a different
        // spelling names the same file, so it is not stale.
        .filter(|file| !renamed.contains_key(file.as_str()))
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
            // has been installed here or the tenth, so any foreign content in
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

    record.installed.insert(key, new_files);
    record
        .write(&paths.result)
        .map_err(|error| CliError::Config { error })?;
    Ok(InstallReport {
        target: target.to_path_buf(),
        copied,
        removed,
    })
}

/// Install when `-o` was given. Relative targets resolve against `cwd`.
/// `out_root` is where the install target's lock file goes; see
/// `install_lock_path`.
pub fn maybe_install(
    paths: &TaskPaths,
    output: Option<&str>,
    cwd: &Path,
    out_root: &Path,
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
    let report = install(paths, &target, out_root)?;
    Ok(Some(report.target.to_string_lossy().into_owned()))
}

/// The lock file guarding one install target:
/// `<out root>/install-locks/<hash of the canonical target>.lock`.
///
/// Keyed on the target rather than on the task, because the thing two runs
/// collide over is the directory they are both writing into. `compile -o
/// dist` and `generate -o dist` hold different task locks, so without this
/// both can find `dist/morphir-ir.json` absent, both write it, and both
/// record themselves as owning it.
///
/// The lock file does not go inside the target. Install's pre-flight scan
/// treats anything under the target that it did not write as foreign content
/// and refuses the run, so a lock file there would make install refuse
/// itself. The out root is Morphir's own directory and already holds the
/// task locks, so it is where this one belongs too.
///
/// The name is a hex `DefaultHasher` digest of the canonical target's bytes.
/// It is not a cryptographic hash — `sha2` is not a dependency of this crate
/// — and it does not need to be: two different targets whose digests
/// collided would merely take turns with each other, which costs a little
/// time and gets no answer wrong. `DefaultHasher` is not guaranteed stable
/// across Rust releases either, which does not matter here, because every
/// process contending for one lock is the same binary.
pub fn install_lock_path(out_root: &Path, canonical_target: &Path) -> PathBuf {
    use std::hash::{Hash, Hasher};

    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    canonical_target
        .as_os_str()
        .as_encoded_bytes()
        .hash(&mut hasher);
    out_root
        .join("install-locks")
        .join(format!("{:016x}.lock", hasher.finish()))
}

/// Reject a `-o` target that already exists as something other than a
/// directory, with a message that names the path and explains what `-o`
/// means: someone reusing an old invocation that named `-o` as an exact
/// output *file* (as this path did before it grew a canonical `.dest`) would
/// otherwise hit `create_dir_all` failing on that file with a bare "File
/// exists" `CliError::FileSystem`, naming neither the path nor the reason.
/// `std::fs::metadata` follows symlinks, so a symlink to a directory passes
/// (see `remove_confined`'s doc comment: `target` may legitimately be a
/// symlink); a missing path also passes, since `create_dir_all` creates it.
fn reject_non_directory_target(target: &Path) -> Result<(), CliError> {
    match std::fs::metadata(target) {
        Ok(metadata) if !metadata.is_dir() => Err(CliError::Validation {
            message: format!(
                "-o target '{}' already exists and is not a directory; \
                 -o installs the task's output into a directory, and the canonical \
                 output stays under .morphir/out",
                target.display()
            ),
        }),
        Ok(_) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(CliError::FileSystem { error }),
    }
}

/// Reject a `-o` target that is the task's own scratch directory, or a path
/// inside it. `install` copies from `paths.dest` to `target`; if the two are
/// the same location (or `target` is nested under `dest`), a copy's source
/// and destination alias each other, and `fs::copy` truncates the
/// destination — and therefore the source — before reading it. Both sides
/// are canonicalized before comparing, the same way `remove_confined` does,
/// so a symlinked `dest` or `target` cannot slip past a textual comparison.
fn reject_target_inside_dest(canonical_target: &Path, dest: &Path) -> Result<(), CliError> {
    let canonical_dest = match std::fs::canonicalize(dest) {
        Ok(canonical_dest) => canonical_dest,
        // `dest` does not exist, so `target` cannot be inside it.
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(CliError::FileSystem { error }),
    };
    if canonical_target.starts_with(&canonical_dest) {
        return Err(CliError::Validation {
            message: format!(
                "-o target '{}' is the task's own scratch directory ('{}') or lies inside it; \
                 the install target must be outside the task's scratch directory",
                canonical_target.display(),
                canonical_dest.display()
            ),
        });
    }
    Ok(())
}

/// Reject a `value` entry or an `installed` file path that could name a
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
                        "task result entry '{entry}' contains '..'; refusing to install it"
                    ),
                });
            }
            Component::RootDir | Component::Prefix(_) => {
                return Err(CliError::Validation {
                    message: format!(
                        "task result entry '{entry}' is an absolute path; refusing to install it"
                    ),
                });
            }
        }
    }
    if !has_normal_component {
        return Err(CliError::Validation {
            message: format!(
                "task result entry '{entry}' does not name a path under the install target; refusing to install it"
            ),
        });
    }
    Ok(())
}

/// Confirm that `relative`, joined onto `target`, still names a location
/// inside `target` once the symlinks along the way are followed.
///
/// `validate_entry` catches the textual escapes (`..` and absolute paths) but
/// not a symlink already sitting in the target: with `dist/morphir-ir`
/// pointing at `/outside`, `create_dir_all` and `fs::copy` follow it without
/// complaint and the install writes outside `dist` altogether. Worse, a user
/// who replaces an owned directory with such a symlink slips past the
/// foreign-content conflict check too, because the paths beneath it are ones
/// this function already owns.
///
/// The destination usually does not exist yet, so the nearest ancestor that
/// does is canonicalized instead, and has to resolve under the canonical
/// target — the same rule `remove_confined` applies on the removal side. A
/// path that exists but does not resolve is a dangling symlink, which
/// `fs::copy` would follow to wherever it points, so it is refused rather
/// than walked past.
///
/// Like `remove_confined`, this is advisory rather than a security boundary:
/// it catches an accidental or stale symlink in the target, and it is
/// inherently racy, since nothing stops one from appearing between this check
/// and the write.
fn confined_destination(
    relative: &str,
    target: &Path,
    canonical_target: &Path,
) -> Result<(), CliError> {
    let destination = target.join(relative);
    let mut candidate = Some(destination.as_path());
    while let Some(path) = candidate {
        match std::fs::canonicalize(path) {
            Ok(resolved) if resolved.starts_with(canonical_target) => return Ok(()),
            Ok(resolved) => {
                return Err(CliError::Validation {
                    message: format!(
                        "refusing to install '{}': it resolves to '{}', which is outside the \
                         install target '{}' (resolved to '{}')",
                        destination.display(),
                        resolved.display(),
                        target.display(),
                        canonical_target.display()
                    ),
                });
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                if std::fs::symlink_metadata(path).is_ok() {
                    return Err(CliError::Validation {
                        message: format!(
                            "refusing to install '{}': '{}' is a symbolic link with no target, \
                             so writing through it could land outside the install target '{}'",
                            destination.display(),
                            path.display(),
                            target.display()
                        ),
                    });
                }
                candidate = path.parent();
            }
            Err(error) => return Err(CliError::FileSystem { error }),
        }
    }
    Ok(())
}

/// Previous ledger entries this run rewrites under a different spelling, as
/// `old spelling -> new spelling`.
///
/// The ledger records each path exactly as install spelled it. On a
/// case-insensitive filesystem a generated name that changes only in case
/// between runs — `Foo.gleam` becoming `foo.gleam` — is a different string
/// but the very same file: a string-only lookup finds no previous entry,
/// `symlink_metadata` finds the file sitting there, and the reinstall is
/// refused as though the user had put it there. Comparing the strings
/// case-insensitively instead would only move the guesswork around, since
/// whether case matters is a property of the filesystem and not of the path.
///
/// So each new destination that exists and has no entry by name is compared
/// by identity against the previous entries still on disk.
/// `same_file::Handle` asks the filesystem, which is the only thing that
/// knows. A match means install owns the file, under a name it now spells
/// differently: it is not foreign content, and the entry under the old
/// spelling is not stale. The ledger is rewritten from this run's paths, so
/// the new spelling replaces the old one there without any extra work.
///
/// `candidates` is only the destinations that both exist and failed to match
/// by name, which is normally none at all, so no handle is opened in the
/// ordinary case.
fn renamed_previous_files(
    target: &Path,
    previous_files: &[String],
    candidates: &[&String],
) -> Result<BTreeMap<String, String>, CliError> {
    if candidates.is_empty() {
        return Ok(BTreeMap::new());
    }
    let mut owned: HashMap<Handle, &String> = HashMap::new();
    for file in previous_files {
        if let Some(handle) = handle_for(&target.join(file))? {
            owned.insert(handle, file);
        }
    }
    let mut renamed = BTreeMap::new();
    for candidate in candidates {
        let Some(handle) = handle_for(&target.join(candidate))? else {
            continue;
        };
        if let Some(previous) = owned.get(&handle) {
            renamed.insert((*previous).clone(), (*candidate).clone());
        }
    }
    Ok(renamed)
}

/// A handle identifying the file at `path`, or `None` when nothing is there.
fn handle_for(path: &Path) -> Result<Option<Handle>, CliError> {
    match Handle::from_path(path) {
        Ok(handle) => Ok(Some(handle)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(CliError::FileSystem { error }),
    }
}

/// Refuse an owned destination whose path now runs through a symbolic link.
///
/// `install` only ever creates real directories under the target, so every
/// directory between the target and a file it wrote was a real directory at
/// the time it was written. If one of them is a symbolic link now, someone
/// swapped it in afterwards, and the ledger's paths no longer name what the
/// ledger thinks they name: `remove_entry` unlinks a file through the link,
/// and the copy step writes over one. Either way the file that is destroyed
/// is the user's, not Morphir's.
///
/// `confined_destination` does not catch this. A link pointing at a sibling
/// directory *inside* the same target resolves inside the target, so every
/// containment check is satisfied and the paths beneath the link are ones
/// this function already owns.
///
/// Only the components strictly between the target and the file are checked.
/// The file itself may be a link for all this cares — `remove_entry` unlinks
/// the link rather than what it points at, and a copy replaces it — and
/// `target` itself may legitimately be one, since `-o` can name a symlinked
/// directory. A component that does not exist ends the walk: there is
/// nothing below it to reach.
///
/// Like the other symlink checks here this is advisory rather than a security
/// boundary, and inherently racy: nothing stops a link from being swapped in
/// between this check and the removal.
fn reject_symlinked_ancestors(relative: &str, target: &Path) -> Result<(), CliError> {
    let components: Vec<Component<'_>> = Path::new(relative).components().collect();
    let ancestors = components.len().saturating_sub(1);
    let mut path = target.to_path_buf();
    for component in components.into_iter().take(ancestors) {
        path.push(component);
        match std::fs::symlink_metadata(&path) {
            Ok(metadata) if metadata.is_symlink() => {
                return Err(CliError::Validation {
                    message: format!(
                        "refusing to install '{}': '{}' is a symbolic link, but Morphir \
                         installed it as a real directory; the files under it are not the \
                         ones Morphir wrote. Remove the link or choose a different -o target",
                        target.join(relative).display(),
                        path.display()
                    ),
                });
            }
            Ok(_) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(error) => return Err(CliError::FileSystem { error }),
        }
    }
    Ok(())
}

/// Remove `path` if it is a file that exists, first confirming its
/// containing directory still resolves under `canonical_target` (the
/// canonicalized `target`). Returns whether anything was actually removed,
/// so callers never report a removal that did not happen.
///
/// `symlink_metadata` on `path` only protects against `path` itself being a
/// symlink; it does not stop a symlinked *intermediate* directory (e.g.
/// `target/sub -> /elsewhere`) from redirecting `remove_file` onto a
/// location outside `target`. Canonicalizing `path`'s parent and checking it
/// against the canonicalized target catches that: a legitimate removal's
/// parent always resolves inside the target, while a symlinked intermediate
/// resolves elsewhere. `target` itself may legitimately be a symlink (the
/// user's `-o` can point at one), so both sides are canonicalized before
/// comparing — comparing `path` directly against the non-canonical `target`
/// would reject that legitimate case.
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
                 which is outside the install target '{}' (resolved to '{}')",
                path.display(),
                canonical_parent.display(),
                target.display(),
                canonical_target.display()
            ),
        });
    }
    remove_entry(path)
}

/// Remove `path` if it is a file that exists. Returns whether anything was
/// actually removed.
///
/// A directory at `path` is never removed here, even recursively — this
/// function only ever deletes files this module wrote, and a directory is
/// not one of those, whether it is foreign content the user created, or a
/// directory that a record written by an older build of this scheme still
/// lists by entry name rather than by the file paths beneath it (the
/// bookkeeping this module writes today is always flattened to files, but a
/// stale record on disk from before that change is not). `prune_empty_parents`
/// is the only place a directory is ever removed, and only once emptying it
/// out file by file has left it with nothing inside.
fn remove_entry(path: &Path) -> Result<bool, CliError> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_dir() => Ok(false),
        Ok(_) => std::fs::remove_file(path)
            .map(|()| true)
            .map_err(|error| CliError::FileSystem { error }),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(CliError::FileSystem { error }),
    }
}

/// Every file `record.value` produces, as paths relative to `target`. A
/// file entry contributes itself; a directory entry contributes every file
/// beneath it, walked recursively. This is exactly the set of files `install`
/// writes under `target` this run, so it is also exactly what
/// `installed[target]` should remember owning — see the `install` doc comment.
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

    /// The out root a task's `TaskPaths` were built under. Every test here
    /// uses the root module, so the record sits directly in the out root.
    fn out_root_of(paths: &TaskPaths) -> PathBuf {
        paths.result.parent().unwrap().to_path_buf()
    }

    /// `install` with the out root the task was built under, which is where
    /// the install target's lock file goes.
    fn install_here(paths: &TaskPaths, target: &Path) -> Result<InstallReport, CliError> {
        install(paths, target, &out_root_of(paths))
    }

    /// The key `install` uses for `record.installed`: the canonicalized path,
    /// not whatever string the test wrote. `path` must already exist.
    fn canonical_key(path: &Path) -> String {
        std::fs::canonicalize(path)
            .unwrap()
            .to_string_lossy()
            .into_owned()
    }

    fn task_with_value(root: &Path, value: &[&str]) -> TaskPaths {
        let paths = TaskPaths::new(root, Path::new(""), &TaskId::compile()).unwrap();
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
        let report = install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir.json").is_file());
        assert!(!target.join("parse").exists());
        assert_eq!(report.copied, vec!["morphir-ir.json".to_owned()]);
        let record = TaskResult::read(&paths.result).unwrap().unwrap();
        assert_eq!(
            record.installed[&canonical_key(&target)],
            vec!["morphir-ir.json".to_owned()]
        );
    }

    #[test]
    fn rejects_a_target_that_is_already_a_plain_file() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("out.json");
        std::fs::write(&target, "not a directory").unwrap();

        let error = install_here(&paths, &target).unwrap_err();
        let CliError::Validation { message } = error else {
            panic!("expected a validation error, got {error:?}");
        };
        assert!(
            message.contains(&target.to_string_lossy().into_owned()),
            "{message}"
        );
        assert!(message.contains("directory"), "{message}");
    }

    #[test]
    fn directory_entries_copy_recursively() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());
    }

    #[test]
    fn re_install_removes_stale_entries_and_keeps_foreign_files() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = task_with_value(&root, &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        std::fs::write(target.join("README.md"), "mine").unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = vec!["morphir-ir".to_owned()];
        record.write(&paths.result).unwrap();
        let report = install_here(&paths, &target).unwrap();

        assert!(!target.join("morphir-ir.json").exists());
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("README.md").is_file());
        assert_eq!(report.removed, vec!["morphir-ir.json".to_owned()]);
    }

    #[test]
    fn re_install_removes_a_stale_directory_entry_and_keeps_a_foreign_directory_beside_it() {
        // Same property as `re_install_removes_stale_entries_and_keeps_foreign_files`,
        // but for a directory entry: a foreign directory placed inside the
        // stale entry's parent must block pruning of that parent, and a
        // foreign top-level directory must be untouched.
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = TaskPaths::new(&root, Path::new(""), &TaskId::compile()).unwrap();
        std::fs::create_dir_all(paths.dest.join("sub/report/pkg")).unwrap();
        std::fs::write(paths.dest.join("sub/report/pkg/x.yaml"), "b: 2").unwrap();
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = vec!["sub/report".to_owned()];
        record.write(&paths.result).unwrap();

        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("sub/report/pkg/x.yaml").is_file());

        // A foreign file inside the entry's parent directory, and a foreign
        // top-level directory unrelated to any entry.
        std::fs::write(target.join("sub/keepme.txt"), "mine").unwrap();
        std::fs::create_dir_all(target.join("mine/nested")).unwrap();
        std::fs::write(target.join("mine/nested/file.txt"), "mine too").unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = Vec::new();
        record.write(&paths.result).unwrap();
        let report = install_here(&paths, &target).unwrap();

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
            let error = install_here(&paths, &target).unwrap_err();
            assert!(error.to_string().contains(".."), "{error}");
            assert!(!target.exists(), "target must not be created on rejection");
        }

        // An absolute-path entry is rejected the same way.
        let absolute_entry_text = foreign.join("secret.txt");
        let absolute_entry_text = absolute_entry_text.to_string_lossy().into_owned();
        let paths = task_with_value(&temp.path().join("out2"), &[&absolute_entry_text]);
        let error = install_here(&paths, &target).unwrap_err();
        assert!(error.to_string().contains("absolute"), "{error}");
        assert!(!target.exists());

        // The foreign file was never touched.
        assert_eq!(
            std::fs::read_to_string(foreign.join("secret.txt")).unwrap(),
            "do not touch"
        );
    }

    #[test]
    fn previous_installed_entries_that_could_escape_the_target_are_also_rejected() {
        // `validate_entry` runs over both `record.value` (covered above) and
        // the bookkeeping list from a prior install to this target
        // (`record.installed`). Exercise the second loop specifically: a
        // clean `value` with a malicious entry sitting only in `installed`.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &[]);
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record
            .installed
            .insert(canonical_key(&target), vec!["../escape.txt".to_owned()]);
        record.write(&paths.result).unwrap();

        let error = install_here(&paths, &target).unwrap_err();
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
            let error = install_here(&paths, &target).unwrap_err();
            assert!(
                error.to_string().contains("does not name a path"),
                "{error}"
            );
        }
    }

    #[test]
    fn first_install_merges_into_a_foreign_directory_without_deleting_it() {
        // A directory-valued entry is always merged into, never wiped
        // first, whether or not anything has been installed here before. If
        // the user already has their own directory at that path, it must be
        // merged into — not deleted — since this function never put it
        // there.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("morphir-ir")).unwrap();
        std::fs::write(target.join("morphir-ir/mine.txt"), "not yours").unwrap();

        install_here(&paths, &target).unwrap();

        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/mine.txt")).unwrap(),
            "not yours",
            "a foreign file inside a first-time directory entry must survive"
        );
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());
    }

    #[test]
    fn second_install_after_merging_into_a_foreign_directory_still_keeps_the_foreign_file() {
        // Regression for the bug in the round-1 fix: merging into a user's
        // pre-existing directory on the FIRST install kept `mine.txt`, but
        // bookkeeping then recorded the whole entry name as owned, so the
        // SECOND install saw the entry in its own history and wiped the
        // directory anyway. Bookkeeping now tracks individual files, so the
        // foreign file must survive any number of installs, not just the
        // first.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("morphir-ir")).unwrap();
        std::fs::write(target.join("morphir-ir/mine.txt"), "not yours").unwrap();

        install_here(&paths, &target).unwrap();
        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/mine.txt")).unwrap(),
            "not yours"
        );

        install_here(&paths, &target).unwrap();

        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/mine.txt")).unwrap(),
            "not yours",
            "a foreign file must survive a SECOND install, not just the first"
        );
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());
    }

    #[test]
    fn second_install_of_a_directory_entry_removes_a_file_no_longer_produced() {
        // Once a directory entry has been installed here before, a re-install
        // of it must still drop a file the task produced last time but not
        // this time — but only that file: a sibling file the task still
        // produces, and a foreign file the user has placed inside the same
        // directory, must both survive.
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = task_with_value(&root, &["morphir-ir"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());

        std::fs::write(target.join("morphir-ir/foreign.txt"), "mine").unwrap();
        std::fs::remove_file(paths.dest.join("morphir-ir/pkg/x.yaml")).unwrap();
        install_here(&paths, &target).unwrap();

        assert!(
            !target.join("morphir-ir/pkg/x.yaml").exists(),
            "a file dropped from a directory this function owns must not survive a re-install"
        );
        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/foreign.txt")).unwrap(),
            "mine",
            "a foreign file inside an owned directory must survive a re-install"
        );
    }

    #[test]
    fn removed_only_lists_files_actually_deleted() {
        // If a previously-installed file is already gone by the time a stale
        // install runs (the user deleted it, or an earlier run failed
        // partway), that is not a removal this call performed and must not
        // be claimed in the report.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        std::fs::remove_file(target.join("morphir-ir.json")).unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = Vec::new();
        record.write(&paths.result).unwrap();
        let report = install_here(&paths, &target).unwrap();

        assert!(
            report.removed.is_empty(),
            "nothing was actually removed by this call: {:?}",
            report.removed
        );
    }

    #[test]
    fn a_legacy_entry_shaped_stale_path_that_is_a_directory_is_never_deleted() {
        // Round 2 rewrote `installed[target]` from entry names to flattened
        // file paths. A record written by an EARLIER build of this branch
        // still has an entry name like `morphir-ir` in that list. If the
        // current run's `value` no longer includes it, it looks stale by
        // that old bookkeeping — but it names a real directory the merge
        // logic wrote into, not a file this function is allowed to delete,
        // so it must survive untouched and must not be reported as removed.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &[]);
        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("morphir-ir/pkg")).unwrap();
        std::fs::write(target.join("morphir-ir/manifest.yaml"), "a: 1").unwrap();
        std::fs::write(target.join("morphir-ir/pkg/x.yaml"), "b: 2").unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record
            .installed
            .insert(canonical_key(&target), vec!["morphir-ir".to_owned()]);
        record.write(&paths.result).unwrap();

        let report = install_here(&paths, &target).unwrap();

        assert!(target.join("morphir-ir/manifest.yaml").is_file());
        assert!(target.join("morphir-ir/pkg/x.yaml").is_file());
        assert!(
            report.removed.is_empty(),
            "a directory must never be reported as removed: {:?}",
            report.removed
        );
    }

    #[test]
    fn a_stale_file_path_the_user_replaced_with_a_directory_is_never_deleted() {
        // Install wrote `morphir-ir.json` as a file. The user later removes it
        // and creates their own directory of the same name. When the task
        // stops producing that entry, the path looks stale by file-path
        // bookkeeping — but it no longer names a file this function wrote,
        // so it must not be deleted.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir.json").is_file());

        std::fs::remove_file(target.join("morphir-ir.json")).unwrap();
        std::fs::create_dir_all(target.join("morphir-ir.json/mine")).unwrap();
        std::fs::write(target.join("morphir-ir.json/mine/keep.txt"), "mine").unwrap();

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = Vec::new();
        record.write(&paths.result).unwrap();
        let report = install_here(&paths, &target).unwrap();

        assert!(target.join("morphir-ir.json").is_dir());
        assert!(target.join("morphir-ir.json/mine/keep.txt").is_file());
        assert!(
            report.removed.is_empty(),
            "a directory must never be reported as removed: {:?}",
            report.removed
        );
    }

    #[cfg(unix)]
    #[test]
    fn stale_removal_refuses_to_delete_through_a_symlinked_intermediate_directory() {
        use std::os::unix::fs::symlink;

        // `dist/sub` is a symlink to a directory the install target does not
        // own. A stale entry `sub/report` would make `remove_dir_all` land
        // on `outside/report` through that symlink even though
        // `symlink_metadata` on the final component (`report`) sees an
        // ordinary directory. The pre-flight scan refuses first, naming the
        // link (`reject_symlinked_ancestors`); `remove_confined` would refuse
        // on its own if the scan ever let this through.
        let temp = tempfile::tempdir().unwrap();
        let outside = temp.path().join("outside");
        std::fs::create_dir_all(outside.join("report")).unwrap();
        std::fs::write(outside.join("report/marker.txt"), "safe").unwrap();

        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        symlink(&outside, target.join("sub")).unwrap();

        let paths =
            TaskPaths::new(&temp.path().join("out"), Path::new(""), &TaskId::compile()).unwrap();
        std::fs::create_dir_all(&paths.dest).unwrap();
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = Vec::new();
        record
            .installed
            .insert(canonical_key(&target), vec!["sub/report".to_owned()]);
        record.write(&paths.result).unwrap();

        let error = install_here(&paths, &target).unwrap_err();
        assert!(error.to_string().contains("symbolic link"), "{error}");
        assert!(error.to_string().contains("sub"), "{error}");
        assert_eq!(
            std::fs::read_to_string(outside.join("report/marker.txt")).unwrap(),
            "safe",
            "the symlink escape must not let removal reach outside the target"
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_symlinked_intermediate_directory_stops_the_copy_before_it_starts() {
        use std::os::unix::fs::symlink;

        // `dist/morphir-ir` is a symlink to a directory the target does not
        // own. `create_dir_all` and `fs::copy` would follow it happily and
        // write the whole entry outside `dist`.
        let temp = tempfile::tempdir().unwrap();
        let outside = temp.path().join("outside");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("manifest.yaml"), "safe").unwrap();

        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        symlink(&outside, target.join("morphir-ir")).unwrap();

        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let error = install_here(&paths, &target).unwrap_err();
        let CliError::Validation { message } = error else {
            panic!("expected a validation error, got {error:?}");
        };
        assert!(message.contains("outside the install target"), "{message}");
        assert!(message.contains("morphir-ir"), "{message}");

        assert_eq!(
            std::fs::read_to_string(outside.join("manifest.yaml")).unwrap(),
            "safe",
            "the file outside the target must not be overwritten"
        );
        assert!(
            !outside.join("pkg").exists(),
            "nothing may be created outside the target"
        );
        let record = TaskResult::read(&paths.result).unwrap().unwrap();
        assert!(
            record.installed.is_empty(),
            "a refused install records no bookkeeping"
        );
    }

    #[cfg(unix)]
    #[test]
    fn replacing_an_owned_directory_with_a_symlink_is_refused_on_the_next_install() {
        use std::os::unix::fs::symlink;

        // The conflict check alone cannot catch this: every path under
        // `morphir-ir` is one this function wrote last time, so it is not
        // foreign content, and the copy would follow the new symlink out of
        // the target.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir/manifest.yaml").is_file());

        let outside = temp.path().join("outside");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("manifest.yaml"), "not ours").unwrap();
        std::fs::remove_dir_all(target.join("morphir-ir")).unwrap();
        symlink(&outside, target.join("morphir-ir")).unwrap();

        let error = install_here(&paths, &target).unwrap_err();
        assert!(
            error.to_string().contains("outside the install target"),
            "{error}"
        );
        assert_eq!(
            std::fs::read_to_string(outside.join("manifest.yaml")).unwrap(),
            "not ours"
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_symlink_that_stays_inside_the_target_is_followed_as_usual() {
        use std::os::unix::fs::symlink;

        // A symlink is only a problem when it leads out of the target. One
        // that lands back inside it is an ordinary part of the user's layout
        // and must keep working.
        let temp = tempfile::tempdir().unwrap();
        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("real")).unwrap();
        symlink(target.join("real"), target.join("morphir-ir")).unwrap();

        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        install_here(&paths, &target).unwrap();

        assert!(target.join("real/manifest.yaml").is_file());
        assert!(target.join("real/pkg/x.yaml").is_file());
    }

    #[cfg(unix)]
    #[test]
    fn a_dangling_symlink_at_a_destination_is_refused_rather_than_written_through() {
        use std::os::unix::fs::symlink;

        // The link resolves to nothing, so canonicalizing it says "not
        // found" — but `fs::copy` would still create the file at the far end
        // of it, which is outside the target.
        let temp = tempfile::tempdir().unwrap();
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        symlink(
            temp.path().join("outside/gone"),
            target.join("morphir-ir.json"),
        )
        .unwrap();

        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let error = install_here(&paths, &target).unwrap_err();
        assert!(
            error.to_string().contains("symbolic link with no target"),
            "{error}"
        );
    }

    #[cfg(unix)]
    #[test]
    fn installing_into_a_symlinked_target_still_works() {
        // The target itself may legitimately be a symlink (`-o` pointed at
        // one); that must keep working since it is not an escape.
        use std::os::unix::fs::symlink;

        let temp = tempfile::tempdir().unwrap();
        let real_target = temp.path().join("real_dist");
        std::fs::create_dir_all(&real_target).unwrap();
        let target = temp.path().join("dist_link");
        symlink(&real_target, &target).unwrap();

        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        install_here(&paths, &target).unwrap();

        assert!(real_target.join("morphir-ir.json").is_file());
    }

    #[test]
    fn missing_record_is_an_error() {
        let temp = tempfile::tempdir().unwrap();
        let paths = TaskPaths::new(temp.path(), Path::new(""), &TaskId::compile()).unwrap();
        let error = install_here(&paths, &temp.path().join("dist")).unwrap_err();
        assert!(error.to_string().contains("no result record"), "{error}");
    }

    /// A target holding one file a previous install is recorded as owning,
    /// with a record that produces nothing this time. Returns the task paths
    /// and the target.
    fn a_target_with_one_previously_installed_file(temp: &Path) -> (TaskPaths, PathBuf) {
        let paths = TaskPaths::new(&temp.join("out"), Path::new(""), &TaskId::compile()).unwrap();
        std::fs::create_dir_all(&paths.dest).unwrap();
        let target = temp.join("dist");
        std::fs::create_dir_all(&target).unwrap();
        std::fs::write(target.join("morphir-ir.json"), "previously installed").unwrap();

        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = Vec::new();
        record
            .installed
            .insert(canonical_key(&target), vec!["morphir-ir.json".to_owned()]);
        record.write(&paths.result).unwrap();
        (paths, target)
    }

    #[test]
    fn a_tombstone_is_rejected_rather_than_wiping_the_ledger() {
        // `out_context::prepare_dest` leaves a tombstone behind when a run
        // starts, and it is still there if that run failed. Installing from
        // one would mean "produce nothing and remove everything previously
        // installed". Every caller in the CLI runs `install` right after a
        // successful `record.write`, so this is not reachable today, but the
        // guard protects against a future caller (or a hand-edited record)
        // silently emptying a whole install target.
        let temp = tempfile::tempdir().unwrap();
        let (paths, target) = a_target_with_one_previously_installed_file(temp.path());
        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.tombstone = true;
        record.write(&paths.result).unwrap();

        let error = install_here(&paths, &target).unwrap_err();
        let CliError::Validation { message } = error else {
            panic!("expected a validation error, got {error:?}");
        };
        assert!(message.contains("no completed product"), "{message}");
        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir.json")).unwrap(),
            "previously installed",
            "a tombstone must not delete previously installed files"
        );
        let record_after = TaskResult::read(&paths.result).unwrap().unwrap();
        assert!(
            !record_after.installed.is_empty(),
            "a rejected install must not overwrite the ledger with an empty one"
        );
    }

    #[test]
    fn a_successful_run_that_produced_nothing_still_retires_what_it_installed_before() {
        // Same record shape as the tombstone above — empty `value`, a ledger
        // naming one file — but this one is not a tombstone: the task ran,
        // succeeded, and had nothing to emit this time. That is a real
        // result, so it installs, and installing it means the file the last
        // run left at the target goes away.
        let temp = tempfile::tempdir().unwrap();
        let (paths, target) = a_target_with_one_previously_installed_file(temp.path());

        let report = install_here(&paths, &target).unwrap();

        assert!(report.copied.is_empty());
        assert_eq!(report.removed, vec!["morphir-ir.json".to_owned()]);
        assert!(
            !target.join("morphir-ir.json").exists(),
            "a run that produces nothing retires what it installed last time"
        );
        let record_after = TaskResult::read(&paths.result).unwrap().unwrap();
        assert_eq!(
            record_after.installed[&canonical_key(&target)],
            Vec::<String>::new(),
            "the ledger for this target is now empty, not stale"
        );
    }

    #[test]
    fn a_foreign_file_at_a_path_install_would_write_blocks_the_whole_install() {
        // A file install did not write, sitting exactly where the current
        // `value` would write one, must not be silently overwritten (and
        // therefore must not later be deleted as if it were ours). The
        // whole install is refused instead, and nothing on disk changes.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        std::fs::write(target.join("morphir-ir.json"), "not ours").unwrap();

        let error = install_here(&paths, &target).unwrap_err();
        let CliError::Validation { message } = error else {
            panic!("expected a validation error, got {error:?}");
        };
        assert!(message.contains("morphir-ir.json"), "{message}");
        assert!(message.contains("did not write"), "{message}");

        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir.json")).unwrap(),
            "not ours",
            "the foreign file must be untouched"
        );
        assert!(
            std::fs::read_dir(&target).unwrap().count() == 1,
            "nothing else must be created in the target"
        );
        let record = TaskResult::read(&paths.result).unwrap().unwrap();
        assert!(
            record.installed.is_empty(),
            "no bookkeeping must be recorded when the install is refused"
        );
    }

    #[test]
    fn a_foreign_file_inside_a_directory_entry_also_blocks_the_install() {
        // Same property, but the conflicting path is one of the individual
        // files flattened out of a directory-valued entry, not a top-level
        // file entry.
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("morphir-ir")).unwrap();
        std::fs::write(target.join("morphir-ir/manifest.yaml"), "not ours").unwrap();

        let error = install_here(&paths, &target).unwrap_err();
        assert!(
            error.to_string().contains("morphir-ir/manifest.yaml"),
            "{error}"
        );
        assert_eq!(
            std::fs::read_to_string(target.join("morphir-ir/manifest.yaml")).unwrap(),
            "not ours"
        );
        assert!(!target.join("morphir-ir/pkg").exists());
    }

    #[test]
    fn re_installing_over_a_file_we_wrote_last_time_still_succeeds() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();

        // Installing again over the exact same, still-owned file must not be
        // treated as a conflict.
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir.json").is_file());
    }

    #[test]
    fn re_installing_with_a_different_spelling_of_the_same_target_still_finds_prior_bookkeeping() {
        // `installed` is keyed on the canonicalized target, so `dist` and
        // `./dist` share bookkeeping instead of shadowing each other: a
        // stale file from the first install must still be recognized and
        // removed on the second, even though the two calls spell `target`
        // differently.
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = task_with_value(&root, &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir.json").is_file());

        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = Vec::new();
        record.write(&paths.result).unwrap();

        let dotted_target = temp.path().join(".").join("dist");
        let report = install_here(&paths, &dotted_target).unwrap();

        assert!(!target.join("morphir-ir.json").exists());
        assert_eq!(report.removed, vec!["morphir-ir.json".to_owned()]);
    }

    #[test]
    fn install_refuses_a_target_that_is_the_tasks_own_dest() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);

        let error = install_here(&paths, &paths.dest).unwrap_err();
        let CliError::Validation { message } = error else {
            panic!("expected a validation error, got {error:?}");
        };
        assert!(message.contains("scratch directory"), "{message}");
    }

    #[test]
    fn install_refuses_a_target_nested_inside_the_tasks_own_dest() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = paths.dest.join("nested");

        let error = install_here(&paths, &target).unwrap_err();
        assert!(error.to_string().contains("scratch directory"), "{error}");
    }

    /// The user replaces an installed directory with a link to a sibling
    /// directory under the same target. Every containment check is satisfied
    /// — the link resolves inside the target — but the paths beneath it are
    /// ones the ledger says Morphir owns, while the files they now name are
    /// the user's.
    #[cfg(unix)]
    #[test]
    fn an_owned_directory_swapped_for_a_symlink_inside_the_target_is_refused() {
        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir/manifest.yaml").is_file());

        let foreign = target.join("other");
        std::fs::create_dir_all(&foreign).unwrap();
        std::fs::write(foreign.join("manifest.yaml"), "the user's file").unwrap();
        std::fs::remove_dir_all(target.join("morphir-ir")).unwrap();
        std::os::unix::fs::symlink(&foreign, target.join("morphir-ir")).unwrap();

        // This run produces nothing, so every owned file is due for removal,
        // and each one now resolves through the link onto the user's file.
        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = Vec::new();
        record.write(&paths.result).unwrap();

        let message = install_here(&paths, &target).unwrap_err().to_string();
        assert!(message.contains("symbolic link"), "{message}");
        assert!(message.contains("morphir-ir"), "{message}");
        assert_eq!(
            std::fs::read_to_string(foreign.join("manifest.yaml")).unwrap(),
            "the user's file",
            "the file behind the link is the user's and must survive"
        );
    }

    /// The lock is the target's, not the task's: two tasks installing to one
    /// directory have to take turns, and two spellings of one directory are
    /// one directory.
    #[test]
    fn the_install_lock_is_keyed_on_the_target_and_lives_under_the_out_root() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        let canonical_target = std::fs::canonicalize(&target).unwrap();
        let dotted = std::fs::canonicalize(temp.path().join("./dist")).unwrap();

        let lock_path = install_lock_path(&root, &canonical_target);
        assert_eq!(lock_path, install_lock_path(&root, &dotted));
        assert_ne!(
            lock_path,
            install_lock_path(&root, &std::fs::canonicalize(temp.path()).unwrap())
        );
        assert!(lock_path.starts_with(&root), "{}", lock_path.display());
        assert!(
            !lock_path.starts_with(&canonical_target),
            "the lock file must stay out of the target, or the conflict scan \
             would read it as foreign content: {}",
            lock_path.display()
        );

        // An install really does create it, and it survives the run.
        let paths = task_with_value(&root, &["morphir-ir.json"]);
        install(&paths, &target, &root).unwrap();
        assert!(lock_path.is_file());
    }

    /// Two runs installing to one target used to both see a destination as
    /// absent, both write it, and both claim it in their own ledger. Distinct
    /// task locks do not help, because the tasks are different.
    #[test]
    fn an_install_waits_for_another_run_installing_to_the_same_target() {
        use std::sync::mpsc::{RecvTimeoutError, channel};
        use std::time::Duration;

        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        let canonical_target = std::fs::canonicalize(&target).unwrap();

        // Stand in for another Morphir run part-way through its own install
        // to this target, under some other task entirely.
        let lock_path = install_lock_path(&root, &canonical_target);
        std::fs::create_dir_all(lock_path.parent().unwrap()).unwrap();
        let held = std::fs::OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(&lock_path)
            .unwrap();
        fs2::FileExt::try_lock_exclusive(&held).expect("nothing holds it yet");

        let paths = task_with_value(&root, &["morphir-ir.json"]);
        let (running_root, running_target) = (root.clone(), target.clone());
        let (finished, waiting) = channel();
        let installing = std::thread::spawn(move || {
            let report = install(&paths, &running_target, &running_root).unwrap();
            finished.send(()).unwrap();
            report
        });

        assert_eq!(
            waiting.recv_timeout(Duration::from_millis(250)),
            Err(RecvTimeoutError::Timeout),
            "an install must wait while another run holds the target's lock"
        );

        fs2::FileExt::unlock(&held).unwrap();
        waiting
            .recv_timeout(Duration::from_secs(30))
            .expect("the install proceeds once the other run releases the lock");
        installing.join().unwrap();
        assert!(target.join("morphir-ir.json").is_file());
    }

    /// A task whose `.dest` holds exactly one generated file.
    fn task_with_one_file(root: &Path, name: &str) -> TaskPaths {
        let paths = TaskPaths::new(root, Path::new(""), &TaskId::compile()).unwrap();
        std::fs::create_dir_all(&paths.dest).unwrap();
        std::fs::write(paths.dest.join(name), "generated").unwrap();
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = vec![name.to_owned()];
        record.write(&paths.result).unwrap();
        paths
    }

    /// Does this directory's filesystem tell two spellings of one name apart?
    /// The answer is a property of the filesystem the tests are running on,
    /// so it is measured rather than assumed.
    fn is_case_insensitive(directory: &Path) -> bool {
        let probe = directory.join("MorphirCaseProbe");
        std::fs::write(&probe, "probe").unwrap();
        let insensitive = directory.join("morphircaseprobe").exists();
        std::fs::remove_file(&probe).unwrap();
        insensitive
    }

    /// A generated name that changes only in case between runs used to be
    /// refused: the ledger did not hold the new spelling, but the file was
    /// sitting there, so install called its own output foreign content.
    #[test]
    fn a_ledger_entry_that_differs_only_in_case_is_recognised_as_ours() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        let insensitive = is_case_insensitive(&target);

        let paths = task_with_one_file(&root, "Foo.gleam");
        install_here(&paths, &target).unwrap();
        let key = canonical_key(&target);
        assert_eq!(
            TaskResult::read(&paths.result).unwrap().unwrap().installed[&key],
            vec!["Foo.gleam".to_owned()]
        );

        // The next run generates the same thing under a different case.
        std::fs::remove_file(paths.dest.join("Foo.gleam")).unwrap();
        std::fs::write(paths.dest.join("foo.gleam"), "generated again").unwrap();
        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.value = vec!["foo.gleam".to_owned()];
        record.write(&paths.result).unwrap();

        let report = install_here(&paths, &target).expect("install must not refuse its own file");
        assert_eq!(report.copied, vec!["foo.gleam".to_owned()]);
        assert_eq!(
            TaskResult::read(&paths.result).unwrap().unwrap().installed[&key],
            vec!["foo.gleam".to_owned()],
            "the ledger holds the spelling this run wrote"
        );
        assert_eq!(
            std::fs::read_to_string(target.join("foo.gleam")).unwrap(),
            "generated again"
        );

        if insensitive {
            // One file under two spellings. The old entry names it too, so it
            // is not stale and nothing is removed.
            assert!(
                report.removed.is_empty(),
                "the old spelling names the same file: {:?}",
                report.removed
            );
        } else {
            // Two names, two files. The old one is retired as usual.
            assert_eq!(report.removed, vec!["Foo.gleam".to_owned()]);
            assert!(!target.join("Foo.gleam").exists());
        }
    }

    #[test]
    fn maybe_install_resolves_relative_targets_against_cwd() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = task_with_value(&root, &["morphir-ir.json"]);
        assert_eq!(
            maybe_install(&paths, None, temp.path(), &root).unwrap(),
            None
        );
        let installed = maybe_install(&paths, Some("dist/ir"), temp.path(), &root)
            .unwrap()
            .unwrap();
        assert_eq!(installed, temp.path().join("dist/ir").to_string_lossy());
        assert!(temp.path().join("dist/ir/morphir-ir.json").is_file());
    }
}

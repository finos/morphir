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
/// Text alone does not settle where a path leads, though, so every component
/// of every one of those paths is also checked against the filesystem before
/// the first byte is written: nothing below the target may be a symbolic
/// link. See `reject_symlinks_below_target`. With that rule in place a file
/// has exactly one spelling under the target, so the ledger records each path
/// as plain text and ownership is a string comparison. Both checks run in the
/// pre-flight scan, so an install that is going to be refused writes nothing
/// at all.
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

    // Before touching anything: nothing below the target may be a symbolic
    // link. See `reject_symlinks_below_target`. The entries themselves are
    // checked as well as the flattened files, because a directory entry with
    // nothing under it flattens to no files at all and would still have
    // `copy_dir` create it, and the ledger's own paths are checked because
    // this run may delete what they name.
    for path in new_files
        .iter()
        .chain(record.value.iter())
        .chain(previous_files.iter())
    {
        reject_symlinks_below_target(path, target)?;
    }

    let new_files_lookup: HashSet<&str> = new_files.iter().map(String::as_str).collect();

    // Before touching anything: two output paths can name one file. On a
    // filesystem that does not distinguish letter case, `a/Config` and
    // `a/config` are the same file, so the second copy would silently
    // overwrite the first with whichever entry happened to run last. Refuse
    // the whole install rather than let one clobber the other.
    reject_colliding_destinations(&new_files, target, &canonical_target, out_root)?;

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

    // A copy failing partway through must not leave the target in a state
    // the *next* install cannot make sense of: everything up to the failing
    // entry is already on disk, but the ledger below is only written once
    // every entry has copied, so without a rollback the next run would read
    // the OLD ledger, find files this run wrote that it does not know about,
    // and refuse the whole install as foreign content — wedging `-o` until
    // someone clears the target by hand. `copied_files` tracks every file
    // actually written this run, incrementally, so that if a copy does fail,
    // exactly the files it introduced (not ones merely overwritten, which
    // were already ours) can be deleted, and the ledger can be written to
    // match what is left on disk before the error is returned.
    //
    // The *failing* copy's own destination is part of that too: `fs::copy`
    // creates the destination file before it starts moving bytes into it, so
    // a failure partway through a single file's copy (disk full, say) can
    // leave a truncated file sitting there even though `fs::copy` itself
    // never returned `Ok`. Left untracked, that file would be neither rolled
    // back nor recorded in the ledger — foreign content the very next install
    // would refuse to run past, which is the wedge this whole scheme exists
    // to prevent. So the failing destination is folded into `copied_files`
    // too, whenever pre-flight's guarantee (see above: anything that already
    // existed at a destination before the copy loop ran was either owned or
    // this install never started) means anything found there now can only be
    // this run's own partial write.
    let mut copied = Vec::new();
    let mut copied_files: Vec<String> = Vec::new();
    let mut copy_failure: Option<CliError> = None;
    'copy: for entry in &record.value {
        let source = paths.dest.join(entry);
        let destination = target.join(entry);
        if source.is_dir() {
            // Always merge: a directory-valued entry never had the
            // destination wiped first, whether this is the first time it
            // has been installed here or the tenth, so any foreign content in
            // it survives regardless.
            if let Err(error) = copy_dir(&source, &destination, Path::new(entry), &mut copied_files)
            {
                copy_failure = Some(error);
                break 'copy;
            }
        } else {
            if let Some(parent) = destination.parent()
                && let Err(error) = std::fs::create_dir_all(parent)
            {
                copy_failure = Some(CliError::FileSystem { error });
                break 'copy;
            }
            match std::fs::copy(&source, &destination) {
                Ok(_) => copied_files.push(entry.clone()),
                Err(error) => {
                    if copy_failure_left_a_file(&destination) {
                        copied_files.push(entry.clone());
                    }
                    copy_failure = Some(CliError::FileSystem { error });
                    break 'copy;
                }
            }
        }
        copied.push(entry.clone());
    }

    if let Some(error) = copy_failure {
        let (ledger, error) = handle_copy_failure(
            error,
            CopyFailureContext {
                copied_files: &copied_files,
                previous_files: &previous_files,
                previous_files_lookup: &previous_files_lookup,
                removed: &removed,
                target,
            },
        );
        record.installed.insert(key, ledger);
        record
            .write(&paths.result)
            .map_err(|write_error| CliError::Config { error: write_error })?;
        return Err(error);
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
/// `<Morphir home>/locks/install/<hash of the canonical target>.lock`.
///
/// Keyed on the target rather than on the task, because the thing two runs
/// collide over is the directory they are both writing into. `compile -o
/// dist` and `generate -o dist` hold different task locks, so without this
/// both can find `dist/morphir-ir.json` absent, both write it, and both
/// record themselves as owning it.
///
/// The lock lives under the user-global Morphir home directory, not under
/// `out_root`, because the target is what two runs actually collide over,
/// and two different workspaces (two different out roots) can both name the
/// same `-o` target. A lock keyed on `out_root` as well as the target would
/// let one workspace's run and another's both believe they hold the lock for
/// the same directory. `out_root` is kept as a parameter only for the
/// fallback below.
///
/// The lock file does not go inside the target either way. Install's
/// pre-flight scan treats anything under the target that it did not write as
/// foreign content and refuses the run, so a lock file there would make
/// install refuse itself.
///
/// If the Morphir home directory cannot be resolved (see
/// [`crate::home::MorphirHome::resolve`]), the lock falls back to
/// `<out_root>/install-locks/<hash>.lock`, the out root already being
/// Morphir's own directory and already holding the task locks. That fallback
/// reintroduces the per-out-root problem this function otherwise avoids, so
/// it prints one line to stderr saying so.
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
    let file_name = format!("{:016x}.lock", hasher.finish());

    match crate::home::MorphirHome::resolve() {
        Ok(home) => home.locks_dir().join("install").join(file_name),
        Err(error) => {
            eprintln!(
                "warning: could not resolve the Morphir home directory ({error}); the \
                 install lock for '{}' will live under the out root instead of the \
                 user-global lock directory, so a different workspace's out root would \
                 not share it",
                canonical_target.display()
            );
            out_root.join("install-locks").join(file_name)
        }
    }
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

/// Refuse the install when any path component below `target` is a symbolic
/// link.
///
/// `target` itself may be a link: `-o` pointing at one is an ordinary thing to
/// do, and it is canonicalized before anything else happens. Below that,
/// everything install writes to, and everything its ledger claims to own, has
/// to be a real file or a real directory.
///
/// One rule replaces a whole family of hazards. A link that leads out of the
/// target — `dist/morphir-ir` pointing at `/outside` — makes `create_dir_all`
/// and `fs::copy` write outside the target. A link with nothing at the far end
/// makes them create the file wherever it points. A directory install created
/// and the user later swapped for a link means the ledger's paths no longer
/// name the files install wrote. A link that stays inside the target makes two
/// different output paths one file. Every one of those is a symbolic link
/// under the target, so refusing all of them, by name and before anything is
/// touched, settles all of them at once — and leaves the ledger free to record
/// each file exactly as install spells it.
///
/// A component that is not on disk ends the walk: nothing exists below a path
/// that does not exist, so there is nothing further to check.
///
/// Like `remove_confined`, this is advisory rather than a security boundary.
/// It catches an accidental or stale link in the target, and it is inherently
/// racy, since nothing stops one from appearing between this check and the
/// write.
fn reject_symlinks_below_target(relative: &str, target: &Path) -> Result<(), CliError> {
    let mut path = target.to_path_buf();
    // `validate_entry` has already refused everything but ordinary names, so
    // every component here is one directory step below the last.
    for component in Path::new(relative).components() {
        let Component::Normal(name) = component else {
            continue;
        };
        path.push(name);
        match std::fs::symlink_metadata(&path) {
            Ok(metadata) if metadata.is_symlink() => {
                let points_at = std::fs::read_link(&path)
                    .map(|link| format!(" to '{}'", link.display()))
                    .unwrap_or_default();
                return Err(CliError::Validation {
                    message: format!(
                        "refusing to install into '{}': '{}' is a symbolic link{points_at}, and \
                         an -o target may not contain symbolic links; point -o at the real \
                         directory instead, or remove the link",
                        target.display(),
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

/// Refuse the install when two of `destinations` name the same file under
/// `target`.
///
/// Nothing below the target is a symbolic link by the time this runs (see
/// `reject_symlinks_below_target`), so two output paths can only be one file
/// by being the same text — or by differing in nothing but letter case on a
/// filesystem that does not distinguish it, which is the default on macOS and
/// Windows. On a case-sensitive filesystem `a/Config` and `a/config` really
/// are two files; on a case-insensitive one they are one file, and the second
/// copy would silently overwrite the first. So the grouping key case-folds
/// every path when the target's filesystem turns out not to tell case apart;
/// see `target_filesystem_is_case_insensitive`.
///
/// The error lists every colliding group so the user can see which paths are
/// fighting over one file.
fn reject_colliding_destinations(
    destinations: &[String],
    target: &Path,
    canonical_target: &Path,
    out_root: &Path,
) -> Result<(), CliError> {
    let case_insensitive = target_filesystem_is_case_insensitive(canonical_target, out_root);

    // `to_lowercase` is a Unicode simple case fold, which is adequate here:
    // it only decides which entries get compared against each other, never
    // anything written to disk.
    let fold = |value: &str| -> String {
        if case_insensitive {
            value.to_lowercase()
        } else {
            value.to_owned()
        }
    };

    let mut by_destination: BTreeMap<String, Vec<&String>> = BTreeMap::new();
    for destination in destinations {
        by_destination
            .entry(fold(destination))
            .or_default()
            .push(destination);
    }

    let mut collisions: Vec<Vec<&String>> = by_destination
        .into_values()
        .filter(|group| group.len() > 1)
        .collect();
    if collisions.is_empty() {
        return Ok(());
    }
    for group in &mut collisions {
        group.sort();
    }

    let groups = collisions
        .iter()
        .map(|group| {
            group
                .iter()
                .map(|destination| destination.as_str())
                .collect::<Vec<_>>()
                .join(", ")
        })
        .collect::<Vec<_>>()
        .join("; ");

    let reason = if case_insensitive {
        "letter case this filesystem does not distinguish makes two output paths one file"
    } else {
        "two output paths are the same file"
    };

    Err(CliError::Validation {
        message: format!(
            "install target '{}' would write more than one output path to the same file: \
             {groups}; {reason}, so the install cannot proceed",
            target.display()
        ),
    })
}

/// Best-effort probe: does the filesystem holding `canonical_target` treat
/// two names that differ only in letter case as the same file?
///
/// The answer is what tells `reject_colliding_destinations` whether it also
/// has to fold case before comparing destinations — see that function's doc
/// comment for why a case-only difference matters at all.
///
/// The probe avoids writing into the user's own directory wherever it can:
/// it first looks for something already on disk under `canonical_target` —
/// an existing entry, or failing that the target directory itself — and asks
/// whether a case-swapped spelling of its final path component resolves to
/// the very same file, by filesystem identity (`same_file::Handle`), the
/// same trick `renamed_previous_files` uses. That settles the question
/// without creating anything.
///
/// Nothing under the target can always settle it, though — an empty target
/// whose own name happens to have no letter to swap case on, say — so as a
/// last resort a small marker file is created, probed, and removed under the
/// install lock's own directory: inside the user-global Morphir home, never
/// inside the target. That directory is not guaranteed to share a filesystem
/// with the target, which is the tradeoff for not touching the user's tree.
///
/// If even that is inconclusive, the answer is `true`. Assuming
/// case-insensitive is the safe direction: at worst it makes
/// `reject_colliding_destinations` refuse an install over a collision that
/// was never real, which the user can work around, while assuming
/// case-sensitive when the filesystem is not would let two outputs silently
/// clobber each other — the exact failure this whole check exists to
/// prevent.
fn target_filesystem_is_case_insensitive(canonical_target: &Path, out_root: &Path) -> bool {
    let mut candidates: Vec<PathBuf> = std::fs::read_dir(canonical_target)
        .map(|entries| entries.flatten().map(|entry| entry.path()).collect())
        .unwrap_or_default();
    candidates.push(canonical_target.to_path_buf());

    for candidate in &candidates {
        if let Some(result) = probe_case_sensitivity_at(candidate) {
            return result;
        }
    }

    let lock_dir = install_lock_path(out_root, canonical_target)
        .parent()
        .map(Path::to_path_buf);
    if let Some(lock_dir) = lock_dir
        && let Some(result) = probe_case_sensitivity_with_marker(&lock_dir)
    {
        return result;
    }

    true
}

/// Does a case-swapped spelling of `path`'s final component name the same
/// file as `path`, by filesystem identity? `None` when the question could
/// not even be asked — nothing at `path`, or its final component has no
/// letter whose case can be swapped.
///
/// A swapped spelling that is simply NOT THERE is an answer, not a failure to
/// ask: the filesystem distinguishes the two names, so it is case-sensitive.
/// Treating that as "could not tell" made every probe on a case-sensitive
/// filesystem inconclusive — the swapped name never exists there — and the
/// caller then fell back to assuming case-insensitive, which refuses installs
/// of two outputs that really are two different files.
fn probe_case_sensitivity_at(path: &Path) -> Option<bool> {
    let original = handle_for(path)?;
    let swapped_path = case_swapped_sibling(path)?;
    match Handle::from_path(&swapped_path) {
        Ok(swapped) => Some(original == swapped),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Some(false),
        // Something is there but will not open — no permission to read it,
        // say. That settles nothing.
        Err(_) => None,
    }
}

/// `path` with its final path component's letters case-swapped (upper to
/// lower and back), or `None` when that component has no letter to swap —
/// digits, punctuation, or an empty name, none of which can answer whether
/// case matters.
fn case_swapped_sibling(path: &Path) -> Option<PathBuf> {
    let name = path.file_name()?.to_str()?;
    let swapped: String = name
        .chars()
        .map(|character| {
            if character.is_uppercase() {
                character.to_lowercase().next().unwrap_or(character)
            } else if character.is_lowercase() {
                character.to_uppercase().next().unwrap_or(character)
            } else {
                character
            }
        })
        .collect();
    if swapped == name {
        None
    } else {
        Some(path.with_file_name(swapped))
    }
}

/// Creates a small marker file under `lock_dir`, probes whether a
/// case-swapped spelling of it names the same file, and removes it again.
/// `None` if the marker could not even be created — `lock_dir` is not
/// writable, say.
fn probe_case_sensitivity_with_marker(lock_dir: &Path) -> Option<bool> {
    std::fs::create_dir_all(lock_dir).ok()?;
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos())
        .unwrap_or_default();
    let marker = lock_dir.join(format!(".case-probe-{}-{nanos}", std::process::id()));
    std::fs::write(&marker, []).ok()?;
    let result = probe_case_sensitivity_at(&marker);
    let _ = std::fs::remove_file(&marker);
    result
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
    // One handle can stand for several ledger entries: two entries that are
    // hard links to each other are one file, and a map keeping only the last
    // of them would leave the other unprotected from stale removal.
    let mut owned: HashMap<Handle, Vec<&String>> = HashMap::new();
    for file in previous_files {
        if let Some(handle) = handle_for(&target.join(file)) {
            owned.entry(handle).or_default().push(file);
        }
    }
    let mut renamed = BTreeMap::new();
    for candidate in candidates {
        let Some(handle) = handle_for(&target.join(candidate)) else {
            continue;
        };
        for previous in owned.get(&handle).into_iter().flatten() {
            renamed.insert((*previous).clone(), (*candidate).clone());
        }
    }
    Ok(renamed)
}

/// A handle identifying the file at `path`, or `None` when there is nothing
/// there or it cannot be opened.
///
/// A destination that exists but will not open — no permission to read it,
/// say — is one install cannot show to be its own, so it is left out of the
/// comparison. That lands the caller on the "already contains files Morphir
/// did not write" refusal, which names the path and says what to do about it,
/// rather than on a bare I/O error from a check the user never asked for.
fn handle_for(path: &Path) -> Option<Handle> {
    Handle::from_path(path).ok()
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

/// Recursively copy `source` to `destination`, appending the path of every
/// file actually copied — relative to `target` (`relative` is the entry's own
/// relative path, the same root `flatten_value_files`/`collect_files` walk
/// from) — to `copied_files` as it goes.
///
/// `copied_files` grows incrementally, file by file, rather than only being
/// filled in once the whole copy has succeeded, so a caller whose call fails
/// partway through still has an accurate record of exactly what this call
/// wrote before the failure — the list `roll_back_partial_copy` needs to
/// clean up after it.
fn copy_dir(
    source: &Path,
    destination: &Path,
    relative: &Path,
    copied_files: &mut Vec<String>,
) -> Result<(), CliError> {
    std::fs::create_dir_all(destination).map_err(|error| CliError::FileSystem { error })?;
    for entry in std::fs::read_dir(source).map_err(|error| CliError::FileSystem { error })? {
        let entry = entry.map_err(|error| CliError::FileSystem { error })?;
        let target = destination.join(entry.file_name());
        let child_relative = relative.join(entry.file_name());
        let file_type = entry
            .file_type()
            .map_err(|error| CliError::FileSystem { error })?;
        if file_type.is_dir() {
            copy_dir(&entry.path(), &target, &child_relative, copied_files)?;
        } else {
            match std::fs::copy(entry.path(), &target) {
                Ok(_) => copied_files.push(child_relative.to_string_lossy().into_owned()),
                Err(error) => {
                    // Same reasoning as the file-entry branch in `install`:
                    // a failure partway through this one file's copy can
                    // still have created it, and pre-flight already
                    // guarantees anything found here now is this run's own.
                    if copy_failure_left_a_file(&target) {
                        copied_files.push(child_relative.to_string_lossy().into_owned());
                    }
                    return Err(CliError::FileSystem { error });
                }
            }
        }
    }
    Ok(())
}

/// Whether a copy attempt that just failed to write `destination` still
/// left something sitting there, and so must be folded into this run's own
/// output for rollback purposes.
///
/// A copy can fail two different ways: it can fail before writing anything
/// at all — no permission to create the destination in its parent
/// directory, say — in which case there is nothing at `destination` to
/// clean up. Or it can fail partway through, after `fs::copy` has already
/// created (and started writing) the destination file — disk full
/// mid-stream, for instance — in which case a truncated file is left
/// behind. The two are told apart the only reliable way: by asking whether
/// anything is at `destination` now. Pre-flight (see `install`'s conflict
/// scan) already guarantees that anything found there once the copy loop is
/// running was either already owned by a previous install or did not exist
/// when this run started, so anything this check finds can only be this
/// run's own failed write.
fn copy_failure_left_a_file(destination: &Path) -> bool {
    std::fs::symlink_metadata(destination).is_ok()
}

/// Undo everything a copy phase wrote before it failed partway through: every
/// path in `copied_files` that is not in `previously_owned` is deleted, and
/// its now-empty parent directories under `target` are pruned.
///
/// A path already in `previously_owned` was written by an earlier, completed
/// install — this run merely overwrote it — so it is ours either way and is
/// left alone; only content this run introduced for the first time is rolled
/// back. Deleting it, rather than leaving it on disk, is what keeps the next
/// install from later finding it and refusing the whole run as foreign
/// content it never wrote.
///
/// Both lists hold paths spelled exactly as install writes them, so the
/// comparison is a plain string match. Nothing below the target is a symbolic
/// link (see `reject_symlinks_below_target`), so one file has one spelling.
///
/// This never stops early: every file in `copied_files` is attempted, even
/// after an earlier one failed to delete, so one stubborn file (a read-only
/// parent directory, say) does not leave the rest of this run's output
/// stranded on disk and unrecorded as well. Every deletion failure is
/// collected and returned instead of raised, so the caller can decide what
/// to do about a rollback that could not fully finish — in particular, it
/// still has to write a ledger that matches whatever is actually left on
/// disk. An empty `Vec` means every file this run introduced was cleaned up.
fn roll_back_partial_copy(
    copied_files: &[String],
    previously_owned: &HashSet<&str>,
    target: &Path,
) -> Vec<CliError> {
    let mut errors = Vec::new();
    for file in copied_files {
        if previously_owned.contains(file.as_str()) {
            continue;
        }
        let path = target.join(file);
        match std::fs::remove_file(&path) {
            Ok(()) => {
                // `prune_empty_parents` never actually returns an error (a
                // failed prune is silently left in place), but it is typed
                // to return a `Result` for callers that might want to know
                // otherwise, so any future error is folded in here rather
                // than silently ignored.
                if let Err(error) = prune_empty_parents(&path, target) {
                    errors.push(error);
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            // `std::io::Error`'s own message never names the path it
            // happened to (`"Operation not permitted (os error 1)"` alone
            // says nothing about which file), so the path is folded in here,
            // where it is still in scope, rather than left for a caller to
            // reconstruct later.
            Err(error) => errors.push(CliError::Validation {
                message: format!("could not remove '{}': {error}", path.display()),
            }),
        }
    }
    errors
}

/// A short, human-readable description of `error`'s cause, for folding one
/// `CliError` into the message of another. `CliError`'s own `Display` is
/// deliberately terse for most variants (`"File system error"`, with the
/// real detail only reachable through `source()`), which is fine when it is
/// the only error being reported but not enough when several are being
/// combined into one message.
fn describe(error: &CliError) -> String {
    match error {
        CliError::FileSystem { error } => error.to_string(),
        other => other.to_string(),
    }
}

/// Bundles `handle_copy_failure`'s inputs so they can be passed as one
/// argument instead of seven: every field is a borrow from state `install`
/// already built before the copy loop ran.
struct CopyFailureContext<'a> {
    /// Every file this run wrote, including a failing copy's own partial
    /// destination — see `copy_failure_left_a_file`.
    copied_files: &'a [String],
    /// The ledger as it was before this run touched anything.
    previous_files: &'a [String],
    /// `previous_files`, as a lookup set.
    previous_files_lookup: &'a HashSet<&'a str>,
    /// Files the stale-removal pass, earlier in `install`, actually deleted.
    removed: &'a [String],
    /// The install target.
    target: &'a Path,
}

/// Everything that has to happen once a copy has failed partway through: roll
/// back (best-effort) what this run introduced, compute the ledger that
/// matches whatever is actually left on disk afterward, and settle on the
/// error to report.
///
/// The ledger written here is the previous ledger minus whatever the stale
/// removal pass already deleted, plus — this is the part a plain "roll back,
/// then reuse the pre-copy ledger" approach misses — any file `copied_files`
/// names that rollback could not remove. That second part is what keeps the
/// ledger honest when rollback itself hits an error: a file rollback failed
/// to delete is still really on disk, so the ledger has to keep owning it,
/// spelled the way the successful-install path would have recorded it, or
/// the next install would find it and refuse to run past it as foreign
/// content.
///
/// Rollback failing does not make the original copy failure any less true,
/// so it is always the error reported — but silently dropping a rollback
/// failure would hide that some of this run's files are still sitting on
/// disk unrecorded, so when rollback did hit errors they are folded into the
/// message alongside it.
fn handle_copy_failure(
    copy_error: CliError,
    context: CopyFailureContext<'_>,
) -> (Vec<String>, CliError) {
    let CopyFailureContext {
        copied_files,
        previous_files,
        previous_files_lookup,
        removed,
        target,
    } = context;
    let rollback_errors = roll_back_partial_copy(copied_files, previous_files_lookup, target);

    let removed_lookup: HashSet<&str> = removed.iter().map(String::as_str).collect();
    let mut ledger: Vec<String> = previous_files
        .iter()
        .filter(|file| !removed_lookup.contains(file.as_str()))
        .cloned()
        .collect();
    for file in copied_files {
        if previous_files_lookup.contains(file.as_str()) {
            // Already owned before this run started; already in `ledger`
            // via `previous_files` above.
            continue;
        }
        if std::fs::symlink_metadata(target.join(file)).is_ok() {
            ledger.push(file.clone());
        }
    }

    if rollback_errors.is_empty() {
        return (ledger, copy_error);
    }

    let mut message = format!("install failed while copying: {}", describe(&copy_error));
    for rollback_error in &rollback_errors {
        message.push_str(&format!(
            "; rolling back a file this run wrote also failed: {}",
            describe(rollback_error)
        ));
    }
    (ledger, CliError::Validation { message })
}

#[cfg(test)]
mod tests {
    use super::*;
    use morphir_devkit::{TaskId, TaskPaths, TaskResult};
    use std::path::Path;

    /// Points `MORPHIR_HOME` at a sandbox directory under the OS temp
    /// directory, once for the whole test binary process, so `install`'s
    /// calls to `MorphirHome::resolve()` (by way of `install_lock_path`)
    /// never touch the developer's real Morphir home while these tests run.
    /// Every entry point below that reaches `install_lock_path` — directly
    /// or through `install_here` — calls this first.
    ///
    /// A `std::sync::Once` makes this safe under parallel test execution: it
    /// runs exactly once, before any test in this binary can have read
    /// `MORPHIR_HOME`, and the value is never changed again afterward, so
    /// there is nothing for two threads to race over.
    fn redirect_morphir_home_for_tests() {
        static INIT: std::sync::Once = std::sync::Once::new();
        INIT.call_once(|| {
            let home = std::env::temp_dir()
                .join(format!("morphir-install-tests-home-{}", std::process::id()));
            std::fs::create_dir_all(&home).expect("create a sandbox Morphir home for tests");
            // SAFETY: set exactly once, from `Once::call_once`, before any
            // test reads `MORPHIR_HOME`, and never changed again.
            unsafe {
                std::env::set_var(crate::home::MORPHIR_HOME_ENV, &home);
            }
        });
    }

    /// The out root a task's `TaskPaths` were built under. Every test here
    /// uses the root module, so the record sits directly in the out root.
    fn out_root_of(paths: &TaskPaths) -> PathBuf {
        paths.result.parent().unwrap().to_path_buf()
    }

    /// `install` with the out root the task was built under. The install
    /// target's lock file itself now lives under the sandboxed
    /// `MORPHIR_HOME` (see `redirect_morphir_home_for_tests`), not under this
    /// out root.
    fn install_here(paths: &TaskPaths, target: &Path) -> Result<InstallReport, CliError> {
        redirect_morphir_home_for_tests();
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
        // own. A stale entry `sub/report` would make the removal land on
        // `outside/report` through that symlink even though
        // `symlink_metadata` on the final component (`report`) sees an
        // ordinary directory. The pre-flight scan walks every component of
        // every ledger path and refuses first, naming `sub`;
        // `remove_confined` would refuse on its own if it ever got that far.
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
        let message = error.to_string();
        assert!(message.contains("is a symbolic link"), "{message}");
        assert!(message.contains("sub"), "{message}");
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
        assert!(message.contains("is a symbolic link"), "{message}");
        assert!(message.contains("morphir-ir"), "{message}");
        assert!(
            message.contains("may not contain symbolic links"),
            "{message}"
        );

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
        let message = error.to_string();
        assert!(message.contains("is a symbolic link"), "{message}");
        assert!(message.contains("morphir-ir"), "{message}");
        assert_eq!(
            std::fs::read_to_string(outside.join("manifest.yaml")).unwrap(),
            "not ours"
        );
    }

    /// A ledger entry naming a FILE, not a directory, swapped for a symlink
    /// to another file that is itself inside the target. The link leads
    /// nowhere unusual, and the name it sits at is still one the ledger owns,
    /// so the foreign-content conflict check never runs on it — but the file
    /// there is no longer the one Morphir wrote, and `fs::copy` would follow
    /// the link and overwrite `other` in its place. The no-symlinks rule
    /// catches it whatever the link points at.
    #[cfg(unix)]
    #[test]
    fn an_owned_file_swapped_for_a_symlink_to_another_file_in_the_target_is_refused() {
        use std::os::unix::fs::symlink;

        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir.json").is_file());

        // A foreign file elsewhere in the target.
        std::fs::write(target.join("other.json"), "not ours").unwrap();

        // The user removes the file Morphir wrote and puts a symlink to that
        // foreign file in its place.
        std::fs::remove_file(target.join("morphir-ir.json")).unwrap();
        symlink(target.join("other.json"), target.join("morphir-ir.json")).unwrap();

        let error = install_here(&paths, &target).unwrap_err();
        let message = error.to_string();
        assert!(message.contains("symbolic link"), "{message}");
        assert!(message.contains("morphir-ir.json"), "{message}");
        assert!(message.contains("other.json"), "{message}");
        assert_eq!(
            std::fs::read_to_string(target.join("other.json")).unwrap(),
            "not ours",
            "the file behind the symlink must survive untouched"
        );
    }

    /// A symbolic link that stays inside the target used to be followed as
    /// an ordinary part of the user's layout, with the ledger recording where
    /// each file really landed. That support is what most of this module's
    /// complexity paid for, and it is gone: anything below the target has to
    /// be a real directory now, wherever the link leads. Install says so by
    /// name and suggests pointing `-o` at the real directory instead.
    #[cfg(unix)]
    #[test]
    fn a_symlinked_directory_inside_the_target_is_refused_even_though_it_stays_inside() {
        use std::os::unix::fs::symlink;

        let temp = tempfile::tempdir().unwrap();
        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("real")).unwrap();
        symlink(target.join("real"), target.join("morphir-ir")).unwrap();

        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir"]);
        let error = install_here(&paths, &target).unwrap_err();
        let CliError::Validation { message } = error else {
            panic!("expected a validation error, got {error:?}");
        };
        assert!(message.contains("is a symbolic link"), "{message}");
        assert!(message.contains("morphir-ir"), "{message}");
        assert!(
            message.contains("point -o at the real directory"),
            "{message}"
        );

        assert!(
            std::fs::read_dir(target.join("real")).unwrap().count() == 0,
            "nothing may be written through the link"
        );
        let record = TaskResult::read(&paths.result).unwrap().unwrap();
        assert!(
            record.installed.is_empty(),
            "a refused install records no bookkeeping"
        );
    }

    /// The same rule for a FILE the user put in the way, rather than a
    /// directory: a symlink sitting exactly where install would write, at a
    /// path no previous install owns. The foreign-content check would name it
    /// too, but the symlink rule runs first and says the more useful thing.
    #[cfg(unix)]
    #[test]
    fn a_symlinked_file_the_user_placed_at_a_destination_is_refused() {
        use std::os::unix::fs::symlink;

        let temp = tempfile::tempdir().unwrap();
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        std::fs::write(target.join("mine.json"), "the user's file").unwrap();
        symlink(target.join("mine.json"), target.join("morphir-ir.json")).unwrap();

        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let error = install_here(&paths, &target).unwrap_err();
        let message = error.to_string();
        assert!(message.contains("is a symbolic link"), "{message}");
        assert!(message.contains("morphir-ir.json"), "{message}");

        assert_eq!(
            std::fs::read_to_string(target.join("mine.json")).unwrap(),
            "the user's file",
            "the file behind the link is the user's and must survive"
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_dangling_symlink_at_a_destination_is_refused_rather_than_written_through() {
        use std::os::unix::fs::symlink;

        // The link has nothing at the far end, so `symlink_metadata` is the
        // only thing that sees it at all — and `fs::copy` would happily
        // create the file where it points, which is outside the target.
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
        let message = error.to_string();
        assert!(message.contains("is a symbolic link"), "{message}");
        assert!(message.contains("morphir-ir.json"), "{message}");
    }

    /// The second of a two-file install fails partway through — its
    /// destination directory is read-only — after the first file has already
    /// been copied. Without a rollback, the first file would sit on disk
    /// unrecorded, and the next install would see it as foreign content it
    /// never wrote and refuse to run at all.
    #[cfg(unix)]
    #[test]
    fn a_failed_copy_rolls_back_what_this_run_wrote_and_leaves_the_ledger_matching_disk() {
        use std::os::unix::fs::PermissionsExt;

        redirect_morphir_home_for_tests();
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let paths = TaskPaths::new(&root, Path::new(""), &TaskId::compile()).unwrap();
        std::fs::create_dir_all(&paths.dest).unwrap();
        std::fs::write(paths.dest.join("a.json"), "first").unwrap();
        std::fs::create_dir_all(paths.dest.join("sub")).unwrap();
        std::fs::write(paths.dest.join("sub/b.json"), "second").unwrap();
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = vec!["a.json".to_owned(), "sub/b.json".to_owned()];
        record.write(&paths.result).unwrap();

        let target = temp.path().join("dist");
        std::fs::create_dir_all(target.join("sub")).unwrap();
        // The second entry's destination directory cannot be written into,
        // so its copy fails after the first entry has already landed.
        std::fs::set_permissions(target.join("sub"), std::fs::Permissions::from_mode(0o500))
            .unwrap();

        let result = install_here(&paths, &target);
        // Restore write permission regardless of the outcome, so the temp
        // directory can be cleaned up and the follow-up install below can run.
        std::fs::set_permissions(target.join("sub"), std::fs::Permissions::from_mode(0o700))
            .unwrap();

        let error = result.unwrap_err();
        assert!(matches!(error, CliError::FileSystem { .. }), "{error}");
        assert!(
            !target.join("a.json").exists(),
            "the file this run copied before the failure must be rolled back"
        );
        assert!(
            !target.join("sub/b.json").exists(),
            "the copy that failed must not leave a partial file behind"
        );

        let record_after = TaskResult::read(&paths.result).unwrap().unwrap();
        assert_eq!(
            record_after.installed.get(&canonical_key(&target)),
            Some(&Vec::<String>::new()),
            "the ledger must be rewritten to match what is actually left on disk"
        );

        // Fixing the permissions and installing again must not be wedged by
        // whatever the failed attempt left behind.
        let report = install_here(&paths, &target).expect("a later install must not be wedged");
        assert!(target.join("a.json").is_file());
        assert!(target.join("sub/b.json").is_file());
        assert_eq!(
            report.copied,
            vec!["a.json".to_owned(), "sub/b.json".to_owned()]
        );
    }

    /// `copy_failure_left_a_file` is what decides whether a failing copy's
    /// own destination gets folded into `copied_files` for rollback (see the
    /// comment above the copy loop in `install`). Real end-to-end coverage
    /// of the case it exists for — `fs::copy` creating a destination file
    /// and then failing partway through writing it, disk-full mid-stream —
    /// is not practical to trigger deterministically in a test: the only two
    /// portable ways a real `fs::copy` call can fail either fail before ever
    /// touching the destination (no permission to create it) or fail while
    /// opening the source (which also never touches the destination), and
    /// pre-flight already refuses the whole install before the copy loop
    /// runs if a destination exists without being previously owned, so the
    /// "something else already there" case can never legitimately reach this
    /// check either. So the condition itself is exercised directly instead.
    #[test]
    fn copy_failure_left_a_file_reports_whether_the_destination_exists() {
        let temp = tempfile::tempdir().unwrap();
        let destination = temp.path().join("partial.json");
        assert!(
            !copy_failure_left_a_file(&destination),
            "nothing is there yet"
        );

        std::fs::write(&destination, "truncated").unwrap();
        assert!(
            copy_failure_left_a_file(&destination),
            "a copy that failed mid-write still left a file behind"
        );
    }

    /// `handle_copy_failure` is what `install` calls once a copy has failed;
    /// it rolls back this run's own files (best-effort — see
    /// `roll_back_partial_copy`), computes the ledger to write, and settles
    /// on the error to report. Exercising a rollback *deletion* failure
    /// end-to-end through `install` runs into the same difficulty as above:
    /// a file only becomes eligible for rollback by having been newly
    /// created during this same run, which means its parent directory was
    /// writable a moment ago — there is no portable, non-racy way to make
    /// that same directory refuse a deletion moments later without also
    /// having refused the creation. So this calls `handle_copy_failure`
    /// directly, with a `copied_files` entry that names a real directory on
    /// disk rather than a file: `std::fs::remove_file` refuses to remove a
    /// directory on every platform, which forces the same kind of failure a
    /// stubborn permission problem would, deterministically.
    #[test]
    fn handle_copy_failure_is_best_effort_and_keeps_the_ledger_matching_disk() {
        let temp = tempfile::tempdir().unwrap();
        let target = temp.path().join("dist");
        // Stands in for a file this run introduced that rollback then fails
        // to remove: a directory, so `remove_file` errors deterministically.
        std::fs::create_dir_all(target.join("stuck")).unwrap();
        // A second file this run introduced that rollback *can* remove, to
        // confirm a failure on one entry does not stop the others.
        std::fs::write(target.join("removable.json"), "new").unwrap();
        assert!(target.join("removable.json").exists());

        let copied_files = vec!["stuck".to_owned(), "removable.json".to_owned()];
        let previous_files = vec!["kept.json".to_owned()];
        let previous_files_lookup: HashSet<&str> =
            previous_files.iter().map(String::as_str).collect();
        let removed: Vec<String> = Vec::new();

        let copy_error = CliError::FileSystem {
            error: std::io::Error::other("could not copy never-reached.json"),
        };
        let (ledger, error) = handle_copy_failure(
            copy_error,
            CopyFailureContext {
                copied_files: &copied_files,
                previous_files: &previous_files,
                previous_files_lookup: &previous_files_lookup,
                removed: &removed,
                target: &target,
            },
        );

        assert!(
            !target.join("removable.json").exists(),
            "rollback still removes what it can, even though another entry failed"
        );
        assert!(
            target.join("stuck").is_dir(),
            "the entry rollback could not remove is left in place, not lost"
        );

        assert_eq!(
            ledger,
            vec!["kept.json".to_owned(), "stuck".to_owned()],
            "the ledger keeps the previously owned file and adds back the one \
             rollback could not remove, so it matches what is really on disk"
        );

        let CliError::Validation { message } = error else {
            panic!("expected a validation error combining both failures, got {error:?}");
        };
        assert!(
            message.contains("could not copy never-reached.json"),
            "{message}"
        );
        assert!(
            message.contains("rolling back") && message.to_lowercase().contains("stuck"),
            "{message}"
        );
    }

    /// A ledger entry naming a FILE, not a directory, swapped for a symlink
    /// to a file OUTSIDE the target altogether. Only the inside-target case
    /// (`an_owned_file_swapped_for_a_symlink_to_another_file_in_the_target_is_refused`)
    /// was covered before.
    ///
    /// This actually lands on a different check than that sibling test:
    /// The same rule refuses this whether the link leads out of the target or
    /// back into it; the sibling test covers the inside-pointing case. Either
    /// way the property this test is after — refused before any write, and
    /// the file behind the link never touched — holds.
    #[cfg(unix)]
    #[test]
    fn an_owned_file_swapped_for_a_symlink_pointing_outside_the_target_is_refused() {
        use std::os::unix::fs::symlink;

        let temp = tempfile::tempdir().unwrap();
        let paths = task_with_value(&temp.path().join("out"), &["morphir-ir.json"]);
        let target = temp.path().join("dist");
        install_here(&paths, &target).unwrap();
        assert!(target.join("morphir-ir.json").is_file());

        // A file entirely outside the install target.
        let outside = temp.path().join("outside");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("secret.txt"), "not ours").unwrap();

        // The user removes the file Morphir wrote and puts a symlink to the
        // outside file in its place.
        std::fs::remove_file(target.join("morphir-ir.json")).unwrap();
        symlink(outside.join("secret.txt"), target.join("morphir-ir.json")).unwrap();

        let error = install_here(&paths, &target).unwrap_err();
        let message = error.to_string();
        assert!(message.contains("is a symbolic link"), "{message}");
        assert!(message.contains("morphir-ir.json"), "{message}");

        assert_eq!(
            std::fs::read_to_string(outside.join("secret.txt")).unwrap(),
            "not ours",
            "the file outside the target must be refused before any write, untouched"
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

    /// `dist/a` and `dist/b` both link to `dist/real`, so the entries
    /// `a/config` and `b/config` name one file on disk. Every earlier check
    /// passes each of them individually — both resolve inside the target —
    /// so without a dedicated check the second copy would silently overwrite
    /// the first. The whole install must be refused instead, and nothing may
    /// be written.
    /// `a/Config` and `a/config` are two different strings. On a
    /// case-sensitive filesystem they really are two different files. On a
    /// case-insensitive one they are the same file, and the second copy would
    /// silently overwrite the first — the exact clobber this collision check
    /// exists to prevent. Which branch runs is decided by probing the host
    /// filesystem, the same way
    /// `a_ledger_entry_that_differs_only_in_case_is_recognised_as_ours` does.
    #[test]
    fn case_only_output_collisions_are_refused_on_case_insensitive_filesystems() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        let insensitive = is_case_insensitive(&target);

        let paths = TaskPaths::new(&root, Path::new(""), &TaskId::compile()).unwrap();
        std::fs::create_dir_all(paths.dest.join("a")).unwrap();
        std::fs::write(paths.dest.join("a/Config"), "upper").unwrap();
        std::fs::write(paths.dest.join("a/config"), "lower").unwrap();
        let mut record = TaskResult::new(&TaskId::compile(), Path::new(""));
        record.value = vec!["a/Config".to_owned(), "a/config".to_owned()];
        record.write(&paths.result).unwrap();

        let result = install_here(&paths, &target);

        if insensitive {
            let error = result.unwrap_err();
            let CliError::Validation { message } = error else {
                panic!("expected a validation error, got {error:?}");
            };
            assert!(message.contains("a/Config"), "{message}");
            assert!(message.contains("a/config"), "{message}");
            let record_after = TaskResult::read(&paths.result).unwrap().unwrap();
            assert!(
                record_after.installed.is_empty(),
                "no bookkeeping must be recorded when the install is refused"
            );
        } else {
            let report =
                result.expect("differently cased names are different files on this filesystem");
            assert_eq!(
                report.copied,
                vec!["a/Config".to_owned(), "a/config".to_owned()]
            );
            assert!(target.join("a/Config").is_file());
            assert!(target.join("a/config").is_file());
            assert_eq!(
                std::fs::read_to_string(target.join("a/Config")).unwrap(),
                "upper"
            );
            assert_eq!(
                std::fs::read_to_string(target.join("a/config")).unwrap(),
                "lower"
            );
            let record_after = TaskResult::read(&paths.result).unwrap().unwrap();
            assert_eq!(
                record_after.installed[&canonical_key(&target)],
                vec!["a/Config".to_owned(), "a/config".to_owned()],
                "two different files get two ledger entries"
            );
        }
    }

    /// The probe has to give an answer on either kind of filesystem, and the
    /// same answer the filesystem itself gives. It used to shrug on a
    /// case-sensitive one — the case-swapped spelling is never there, which it
    /// read as "cannot tell" rather than as "these are two names" — and the
    /// caller then assumed case-insensitive and refused installs of two
    /// outputs that really were two different files.
    #[test]
    fn the_case_sensitivity_probe_answers_on_either_kind_of_filesystem() {
        let temp = tempfile::tempdir().unwrap();
        let marker = temp.path().join("Probe");
        std::fs::write(&marker, "x").unwrap();

        assert_eq!(
            probe_case_sensitivity_at(&marker),
            Some(is_case_insensitive(temp.path())),
            "the probe must answer, and agree with the filesystem"
        );
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
    fn the_install_lock_is_keyed_on_the_target_and_lives_under_the_morphir_home() {
        redirect_morphir_home_for_tests();
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
        let home = crate::home::MorphirHome::resolve().unwrap();
        assert!(
            lock_path.starts_with(home.locks_dir().join("install")),
            "the lock lives in the user-global Morphir home, not the out root: {}",
            lock_path.display()
        );
        assert!(
            !lock_path.starts_with(&root),
            "the lock no longer lives under the out root: {}",
            lock_path.display()
        );
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

    /// Two different `OutContext`s — standing in for two different
    /// workspaces — installing to the same `-o` target must share one lock,
    /// not one each, or two workspaces racing to install into the same
    /// directory would both believe they hold it.
    #[test]
    fn two_out_contexts_with_different_roots_derive_the_same_install_lock_path_for_one_target() {
        use crate::commands::out_context::{OutContext, OutOverrides};

        redirect_morphir_home_for_tests();
        let temp = tempfile::tempdir().unwrap();
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();
        let canonical_target = std::fs::canonicalize(&target).unwrap();

        let workspace_a = OutContext::resolve(
            None,
            &OutOverrides::default(),
            &temp.path().join("workspace-a"),
        );
        let workspace_b = OutContext::resolve(
            None,
            &OutOverrides::default(),
            &temp.path().join("workspace-b"),
        );
        assert_ne!(
            workspace_a.root, workspace_b.root,
            "the two out roots must genuinely differ for this test to mean anything"
        );

        assert_eq!(
            install_lock_path(&workspace_a.root, &canonical_target),
            install_lock_path(&workspace_b.root, &canonical_target),
            "two out roots installing to the same target must derive the same lock path"
        );
    }

    /// Two runs installing to one target used to both see a destination as
    /// absent, both write it, and both claim it in their own ledger. Distinct
    /// task locks do not help, because the tasks are different.
    #[test]
    fn an_install_waits_for_another_run_installing_to_the_same_target() {
        use std::sync::mpsc::{RecvTimeoutError, channel};
        use std::time::Duration;

        redirect_morphir_home_for_tests();
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

    /// Two ledger entries that are hard links to each other are one file, so
    /// a map keyed by that file has to remember both names. Keeping only one
    /// of them left the other looking stale, and it was deleted.
    #[test]
    fn hard_linked_ledger_entries_are_all_kept_when_one_of_them_matches() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("out");
        let target = temp.path().join("dist");
        std::fs::create_dir_all(&target).unwrap();

        // Three names, one file: two of them are in the ledger, and the third
        // is the one this run writes.
        std::fs::write(target.join("one.txt"), "generated").unwrap();
        std::fs::hard_link(target.join("one.txt"), target.join("two.txt")).unwrap();
        std::fs::hard_link(target.join("one.txt"), target.join("three.txt")).unwrap();

        let paths = task_with_one_file(&root, "three.txt");
        let mut record = TaskResult::read(&paths.result).unwrap().unwrap();
        record.installed.insert(
            canonical_key(&target),
            vec!["one.txt".to_owned(), "two.txt".to_owned()],
        );
        record.write(&paths.result).unwrap();

        let report = install_here(&paths, &target).unwrap();
        assert!(
            report.removed.is_empty(),
            "every name for a file this run rewrites is ours: {:?}",
            report.removed
        );
        assert!(target.join("one.txt").exists());
        assert!(target.join("two.txt").exists());
    }

    #[test]
    fn maybe_install_resolves_relative_targets_against_cwd() {
        redirect_morphir_home_for_tests();
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

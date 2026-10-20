//! Post-exit physical census, separate from dynamic publication/cleanup events.
use cap_fs_ext::{DirExt as _, FollowSymlinks, OpenOptionsFollowExt as _, OpenOptionsSyncExt as _};
use cap_std::fs::{Dir, OpenOptions};
use morphir_mck::workbench::model_originals::installed::{
    InstalledAdapterError, InstalledClientRun, InstalledSnapshot,
};
use std::{
    io::Read,
    path::{Component, Path, PathBuf},
    sync::atomic::AtomicBool,
};
use tokio::time::Instant;

pub(super) fn census(
    run: &mut InstalledClientRun<'_>,
    target: InstalledSnapshot,
    root: &Path,
    held: &Dir,
    end: Instant,
    interrupted: &AtomicBool,
) -> Result<(), InstalledAdapterError> {
    super::check(end, interrupted)?;
    let label = root
        .to_str()
        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
    run.begin_snapshot(target, 8, label)?;
    // Keep the genuine fixture-issued destination/scratch directory, rather
    // than acquiring a replacement root from a post-exit path claim.
    let metadata = std::fs::symlink_metadata(root).map_err(super::incomplete)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    let identity = morphir_common::file_identity::FileIdentity::from_file(
        held.try_clone().map_err(super::incomplete)?.into_std_file(),
    )
    .map_err(super::incomplete)?;
    if identity
        != morphir_common::file_identity::FileIdentity::from_path(root)
            .map_err(super::incomplete)?
    {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    let mut buffer = Vec::new();
    walk(
        run,
        target,
        held,
        Path::new(""),
        &mut buffer,
        end,
        interrupted,
    )?;
    run.complete_snapshot(target)
}
fn walk(
    run: &mut InstalledClientRun<'_>,
    target: InstalledSnapshot,
    directory: &Dir,
    relative: &Path,
    buffer: &mut Vec<u8>,
    end: Instant,
    interrupted: &AtomicBool,
) -> Result<(), InstalledAdapterError> {
    for entry in directory.entries().map_err(super::incomplete)? {
        super::check(end, interrupted)?;
        let entry = entry.map_err(super::incomplete)?;
        let name = entry.file_name();
        let name_text = name
            .to_str()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        let path: PathBuf = run.command_path(relative, name_text)?;
        let path_text = portable_relative(run, &path)?;
        let kind = entry.file_type().map_err(super::incomplete)?;
        if kind.is_dir() {
            run.record_snapshot_directory(target, &path_text)?;
            let child = directory
                .open_dir_nofollow(&name)
                .map_err(super::incomplete)?;
            walk(run, target, &child, &path, buffer, end, interrupted)?;
        } else if kind.is_file() {
            let mut options = OpenOptions::new();
            options.read(true).follow(FollowSymlinks::No).nonblock(true);
            let mut file = directory
                .open_with(&name, &options)
                .map_err(super::incomplete)?;
            let metadata = file.metadata().map_err(super::incomplete)?;
            if !metadata.is_file() {
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
            let length = usize::try_from(metadata.len()).map_err(super::incomplete)?;
            let requested = length
                .checked_add(1)
                .ok_or(InstalledAdapterError::ObservationIncomplete)?;
            if buffer.len() < requested {
                *buffer = run.observation_read_buffer(requested)?;
            }
            let mut filled = 0;
            loop {
                super::check(end, interrupted)?;
                if filled == requested {
                    return Err(InstalledAdapterError::ObservationIncomplete);
                }
                let count = (requested - filled).min(65_536);
                let permission = run
                    .prepare_snapshot_read(count)
                    .map_err(super::incomplete)?;
                let actual = file
                    .read(&mut buffer[filled..filled + count])
                    .map_err(super::incomplete)?;
                permission.finish(actual).map_err(super::incomplete)?;
                if actual == 0 {
                    break;
                }
                filled += actual;
            }
            if filled != length {
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
            run.record_snapshot_file(target, &path_text, &buffer[..filled])?;
        } else {
            // Destination policy is regular files/directories only. This does
            // not change the distinct source-association symlink-literal rule.
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
    }
    Ok(())
}

/// Encode validated actual native components with the portable '/' separator.
/// A literal Unix backslash remains literal and is refused by SourcePath;
/// it is never silently turned into another filesystem path.
pub(super) fn portable_relative(
    run: &mut InstalledClientRun<'_>,
    path: &Path,
) -> Result<String, InstalledAdapterError> {
    let native_length = path.as_os_str().len();
    run.visit_observation_bytes(native_length)?;
    let mut required = 0usize;
    for component in path.components() {
        let Component::Normal(name) = component else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        let text = name
            .to_str()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        if required != 0 {
            required = required
                .checked_add(1)
                .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        }
        required = required
            .checked_add(text.len())
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
    }
    if required == 0 {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    // SAME funded actual allocation, retained across clear/push. Native
    // component spellings plus one separator cannot exceed its native path
    // copy; check actual capacity before rewriting, with no reserve/growth.
    let mut portable = run.copy_command_operand(path.as_os_str())?;
    if required > portable.capacity() {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    run.visit_observation_bytes(required)?;
    portable.clear();
    for component in path.components() {
        let Component::Normal(name) = component else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        if !portable.is_empty() {
            portable.push("/");
        }
        portable.push(name);
    }
    // Safe owned conversion preserves exact bytes; validation work is paid
    // before the conversion and no guessed Arc/allocator layout is involved.
    run.visit_observation_bytes(required)?;
    portable.into_string().map_err(super::incomplete)
}

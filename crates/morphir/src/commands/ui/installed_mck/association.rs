//! Bounded observations of the actual supplied runtime, package and checkout.
use super::*;
use crate::commands::mck::workbench::installed_launch::{InstalledCommandPaths, InstalledLaunch};
use cap_fs_ext::{DirExt as _, FollowSymlinks, OpenOptionsFollowExt as _, OpenOptionsSyncExt as _};
use cap_std::fs::OpenOptions;
use morphir_mck::workbench::model_originals::installed::{
    InstalledMetadataQuery, InstalledProcessPurpose,
};
use sha2::{Digest, Sha256};
use std::{
    ffi::OsStr,
    io::Read,
    path::{Path, PathBuf},
};

const REVISION: &[&str] = &[
    "rev-parse",
    "--path-format=absolute",
    "--show-toplevel",
    "--show-object-format",
    "HEAD",
];
const INVENTORY: &[&str] = &["ls-files", "--stage", "-z"];
const STATUS: &[&str] = &[
    "--no-optional-locks",
    "-c",
    "core.fsmonitor=false",
    "status",
    "--porcelain=v1",
    "-z",
    "--untracked-files=no",
];

fn git_program(run: &mut InstalledClientRun<'_>) -> Result<PathBuf, InstalledAdapterError> {
    // This is an observed host metadata tool, distinct from the selected SUT.
    // Resolve once and retain its absolute actual program in every outcome.
    let path = std::env::var_os("PATH").ok_or(InstalledAdapterError::ObservationIncomplete)?;
    for directory in std::env::split_paths(&path) {
        if !directory.is_absolute() {
            continue;
        }
        let program =
            run.command_path(&directory, if cfg!(windows) { "git.exe" } else { "git" })?;
        if program.is_file() {
            return Ok(program);
        }
    }
    Err(InstalledAdapterError::ObservationIncomplete)
}

pub(super) async fn observe(
    launch: &InstalledLaunch,
    paths: &InstalledCommandPaths,
    run: &mut InstalledClientRun<'_>,
    events: &mut InstalledHostObservation,
    limits: Limits,
    end: Instant,
    interrupted: Arc<AtomicBool>,
) -> Result<data::ImplementationObservation, InstalledAdapterError> {
    let git = git_program(run)?;
    for (query, arguments) in [
        (InstalledMetadataQuery::Revision, REVISION),
        (InstalledMetadataQuery::TrackedInventory, INVENTORY),
        (InstalledMetadataQuery::TrackedStatus, STATUS),
    ] {
        super::check(end, &interrupted)?;
        let command_end = end.min(
            Instant::now()
                .checked_add(limits.request_timeout)
                .ok_or(InstalledAdapterError::ObservationIncomplete)?,
        );
        let mut pending = Some(run.spawn_process(
            InstalledProcessPurpose::Metadata(query),
            &git,
            arguments.iter().map(OsStr::new),
            launch.source_checkout(),
            &[],
            limits,
        )?);
        match super::processes::execute(run, events, &mut pending, command_end, &interrupted).await
        {
            Ok(finished) => run.record_finished_process(finished)?,
            Err(error) => {
                // Keep SAME real owner through the explicit cleanup attempt.
                let cleanup_end = super::end(limits)?;
                let _ = super::processes::terminate(&mut pending, cleanup_end).await;
                return Err(error);
            }
        }
    }
    let tools = run.take_metadata_tools()?;
    if tools.len() != 3 {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    let mut buffer = run.observation_read_buffer(65_536)?;
    let package_dir = Dir::open_ambient_dir(launch.package(), cap_std::ambient_authority())
        .map_err(incomplete)?;
    let mut package_entries = Vec::new();
    package(
        run,
        &package_dir,
        Path::new(""),
        &mut package_entries,
        &mut buffer,
        end,
        &interrupted,
    )?;
    run.sort_package_entries(&mut package_entries)?;
    let package_digest = run.package_census_digest(&package_entries)?;
    let package = data::PackageCensus {
        root: run.observation_operand(launch.package().as_os_str())?,
        entries: data::Items::new(package_entries).map_err(incomplete)?,
        sha256: package_digest,
    };
    let root = Dir::open_ambient_dir(launch.source_checkout(), cap_std::ambient_authority())
        .map_err(incomplete)?;
    let revision = tools[0].stdout.as_bytes();
    run.visit_observation_bytes(revision.len())?;
    let revision = std::str::from_utf8(revision).map_err(incomplete)?;
    run.visit_observation_bytes(revision.len())?;
    let mut lines = revision.split_terminator('\n');
    let actual_root = lines
        .next()
        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
    let format = match lines.next() {
        Some("sha1") => data::ObjectFormat::Sha1,
        Some("sha256") => data::ObjectFormat::Sha256,
        _ => return Err(InstalledAdapterError::ObservationIncomplete),
    };
    let head = run.observation_text(
        lines
            .next()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?,
    )?;
    if lines.next().is_some() || !revision.ends_with('\n') {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    // Retain the observed physical root, then the checker relates it to the
    // actual CommandSpec cwd. This is association, not build equivalence.
    let actual_root = run.copy_command_operand(OsStr::new(actual_root))?;
    if Path::new(&actual_root) != launch.source_checkout() {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    let inventory = tools[1].stdout.as_bytes();
    run.visit_observation_bytes(inventory.len())?;
    let inventory = std::str::from_utf8(inventory).map_err(incomplete)?;
    run.visit_observation_bytes(inventory.len())?;
    let mut source_entries = Vec::new();
    if !inventory.is_empty() && !inventory.ends_with('\0') {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    for row in inventory.split_terminator('\0') {
        super::check(end, &interrupted)?;
        run.visit_observation_bytes(row.len())?;
        let (metadata, path) = row
            .split_once('\t')
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        run.visit_observation_bytes(metadata.len())?;
        let mut fields = metadata.split(' ');
        let mode = fields.next();
        let _blob = fields
            .next()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        if fields.next() != Some("0") || fields.next().is_some() {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        // Validate the exact portable relative path before any content access.
        let relative = run.observation_path(path)?;
        if mode == Some("120000") {
            #[cfg(unix)]
            {
                use std::os::unix::ffi::OsStrExt as _;
                let (parent, leaf) = parent_nofollow(&root, relative.as_str())?;
                let name = leaf.as_bytes();
                let mut terminated = run.observation_read_buffer(
                    name.len()
                        .checked_add(1)
                        .ok_or(InstalledAdapterError::ObservationIncomplete)?,
                )?;
                run.visit_observation_bytes(name.len())?;
                terminated[..name.len()].copy_from_slice(name);
                let name = std::ffi::CStr::from_bytes_with_nul(&terminated).map_err(incomplete)?;
                let permission = run
                    .prepare_snapshot_read(buffer.len())
                    .map_err(incomplete)?;
                let length = rustix::fs::readlinkat_raw(&parent, name, &mut buffer[..])
                    .map_err(incomplete)?;
                permission.finish(length).map_err(incomplete)?;
                if length == buffer.len() {
                    return Err(InstalledAdapterError::ObservationIncomplete);
                }
                run.observation_source_link(&mut source_entries, path, &buffer[..length])?;
            }
            #[cfg(not(unix))]
            {
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
        } else {
            let mode = match mode {
                Some("100644") => data::FileMode::Regular,
                Some("100755") => data::FileMode::Executable,
                _ => return Err(InstalledAdapterError::ObservationIncomplete),
            };
            let (length, digest) = hash_relative(
                run,
                &root,
                relative.as_str(),
                &mut buffer,
                end,
                &interrupted,
            )?;
            run.observation_source_file(&mut source_entries, path, mode, length, digest)?;
        }
    }
    let source_digest = run.source_census_digest(&source_entries)?;
    let source = data::SourceAssociation {
        root: run.observation_operand(&actual_root)?,
        head,
        object_format: format,
        tracked_status: if tools[2].stdout.as_bytes().is_empty() {
            data::TrackedStatus::Unchanged
        } else {
            data::TrackedStatus::Changed
        },
        entries: data::Items::new(source_entries).map_err(incomplete)?,
        sha256: source_digest,
    };
    let (length, digest) = hash_program(run, launch.node(), &mut buffer, end, &interrupted)?;
    let runtime = data::RuntimeObservation {
        program: run.observation_operand(launch.node().as_os_str())?,
        byte_length: data::Natural::new(length).map_err(incomplete)?,
        sha256: data::ContentSha256::new(digest),
        version: data::VersionObservation::Unobserved {},
    };
    let observed_launch = match launch {
        InstalledLaunch::NodePackage { .. } => {
            let entry = run.command_path(launch.package(), "bin/morphir.js")?;
            data::LaunchObservation::NodePackage {
                entry: run.observation_operand(entry.as_os_str())?,
            }
        }
        InstalledLaunch::NativeExecutable { program, .. } => {
            let (length, digest) =
                hash_program(run, program.as_path(), &mut buffer, end, &interrupted)?;
            data::LaunchObservation::NativeExecutable {
                program: run.observation_operand(program.as_path().as_os_str())?,
                byte_length: data::Natural::new(length).map_err(incomplete)?,
                sha256: data::ContentSha256::new(digest),
            }
        }
    };
    let command_paths = data::CommandPaths {
        launch_file: run.observation_operand(paths.launch_file().as_os_str())?,
        connection_file: run.observation_operand(paths.connection_file().as_os_str())?,
        source_selection_file: run.observation_operand(paths.source_file().as_os_str())?,
        project_selection_file: run.observation_operand(paths.project_file().as_os_str())?,
        destination: run.observation_operand(paths.destination_argument())?,
    };
    Ok(data::ImplementationObservation::Observed {
        before_action: data::Natural::new(2).map_err(incomplete)?,
        launch: observed_launch,
        runtime,
        command_paths,
        package,
        source,
        metadata_tools: data::Items::new(tools).map_err(incomplete)?,
    })
}
fn hash_program(
    run: &mut InstalledClientRun<'_>,
    path: &Path,
    buffer: &mut [u8],
    end: Instant,
    interrupted: &AtomicBool,
) -> Result<(u64, [u8; 32]), InstalledAdapterError> {
    let parent = path
        .parent()
        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
    let file = path
        .file_name()
        .and_then(OsStr::to_str)
        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
    let root = Dir::open_ambient_dir(parent, cap_std::ambient_authority()).map_err(incomplete)?;
    hash_relative(run, &root, file, buffer, end, interrupted)
}
fn hash_relative(
    run: &mut InstalledClientRun<'_>,
    root: &Dir,
    path: &str,
    buffer: &mut [u8],
    end: Instant,
    interrupted: &AtomicBool,
) -> Result<(u64, [u8; 32]), InstalledAdapterError> {
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No).nonblock(true);
    let (parent, leaf) = parent_nofollow(root, path)?;
    let mut file = parent.open_with(leaf, &options).map_err(incomplete)?;
    if !file.metadata().map_err(incomplete)?.is_file() {
        return Err(InstalledAdapterError::ObservationIncomplete);
    }
    let mut hash = Sha256::new();
    let mut length = 0u64;
    loop {
        super::check(end, interrupted)?;
        let permission = run
            .prepare_snapshot_read(buffer.len())
            .map_err(incomplete)?;
        let actual = file.read(buffer).map_err(incomplete)?;
        permission.finish(actual).map_err(incomplete)?;
        if actual == 0 {
            break;
        }
        run.visit_observation_bytes(actual)?;
        hash.update(&buffer[..actual]);
        length = length
            .checked_add(actual as u64)
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
    }
    Ok((length, hash.finalize().into()))
}
fn parent_nofollow<'a>(
    root: &Dir,
    path: &'a str,
) -> Result<(Dir, &'a OsStr), InstalledAdapterError> {
    let mut components = Path::new(path).components().peekable();
    let mut directory = root.try_clone().map_err(incomplete)?;
    while let Some(component) = components.next() {
        let std::path::Component::Normal(component) = component else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        if components.peek().is_none() {
            return Ok((directory, component));
        }
        directory = directory.open_dir_nofollow(component).map_err(incomplete)?;
    }
    Err(InstalledAdapterError::ObservationIncomplete)
}
fn package(
    run: &mut InstalledClientRun<'_>,
    directory: &Dir,
    relative: &Path,
    entries: &mut Vec<data::PackageFile>,
    buffer: &mut [u8],
    end: Instant,
    interrupted: &AtomicBool,
) -> Result<(), InstalledAdapterError> {
    for entry in directory.entries().map_err(incomplete)? {
        super::check(end, interrupted)?;
        let entry = entry.map_err(incomplete)?;
        let name = entry.file_name();
        let text = name
            .to_str()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        let path = run.command_path(relative, text)?;
        let path_text = path
            .to_str()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        let kind = entry.file_type().map_err(incomplete)?;
        if kind.is_dir() {
            let child = directory.open_dir_nofollow(&name).map_err(incomplete)?;
            package(run, &child, &path, entries, buffer, end, interrupted)?;
        } else if kind.is_file() {
            let (length, digest) = hash_relative(run, directory, text, buffer, end, interrupted)?;
            #[cfg(unix)]
            let executable = {
                use cap_std::fs::MetadataExt as _;
                entry.metadata().map_err(incomplete)?.mode() & 0o111 != 0
            };
            #[cfg(not(unix))]
            let executable = false;
            run.observation_package_file(
                entries,
                path_text,
                if executable {
                    data::FileMode::Executable
                } else {
                    data::FileMode::Regular
                },
                length,
                digest,
            )?;
        } else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
    }
    Ok(())
}

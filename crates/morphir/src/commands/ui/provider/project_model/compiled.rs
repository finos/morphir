//! Read the compile record and its artifact under one confined shared lock.

use super::{MAX_PROJECT_MODEL_BYTES, protocol_error};
use crate::{commands::ir_storage::read_value_from_vfs, error::CliError};
use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt, OpenOptionsSyncExt};
use cap_std::fs::{Dir, File, OpenOptions};
use morphir_common::vfs::{VfsPath, memory_root};
use morphir_devkit::{IrLayout, TaskId, TaskResult};
use std::{
    io::{Read, Write},
    path::{Component, Path},
};

/// None means no compile record exists, so the caller may try the legacy file.
pub(super) fn load(root: &Dir, module: &Path) -> Result<Option<String>, CliError> {
    let directory = match open_directory(root, module) {
        Ok(directory) => directory,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    let mut options = OpenOptions::new();
    options
        .read(true)
        .write(true)
        .create(true)
        .follow(FollowSymlinks::No)
        .nonblock(true);
    let lock = directory.open_with("compile.lock", &options)?.into_std();
    if !lock.metadata()?.is_file() {
        return Err(protocol_error("Compile lock must be a regular file"));
    }
    fs2::FileExt::lock_shared(&lock)?;
    let file = match open_file(&directory, Path::new("compile.json")) {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error.into()),
    };
    let mut budget = MAX_PROJECT_MODEL_BYTES;
    let record: TaskResult = serde_json::from_slice(&read_bounded(file, &mut budget)?)
        .map_err(|error| protocol_error(format!("Invalid compile task record: {error}")))?;
    if record.schema != morphir_devkit::out::result::RESULT_SCHEMA
        || record.task != TaskId::compile().as_str()
        || record.module != module.to_string_lossy().replace('\\', "/")
    {
        return Err(protocol_error(
            "Compile task record does not match the selected project",
        ));
    }
    if record.tombstone {
        return Err(protocol_error(
            "Project has no successful compile; compile it again",
        ));
    }
    let descriptor = record
        .ir
        .ok_or_else(|| protocol_error("Compile record has no IR descriptor"))?;
    let artifact_path = Path::new(&descriptor.path);
    if crate::commands::install::confine_relative_path(&descriptor.path).is_err()
        || artifact_path
            .components()
            .any(|part| !matches!(part, Component::Normal(_)))
    {
        return Err(protocol_error(
            "IR descriptor must name a path confined to compile.dest",
        ));
    }
    let dest = directory.open_dir_nofollow("compile.dest")?;
    let snapshot = memory_root();
    let target = snapshot.join(&descriptor.path).map_err(vfs_error)?;
    target.parent().create_dir_all().map_err(vfs_error)?;
    match descriptor.layout {
        IrLayout::SingleFile => {
            let bytes = read_bounded(open_file(&dest, artifact_path)?, &mut budget)?;
            target.create_file().map_err(vfs_error)?.write_all(&bytes)?;
        }
        IrLayout::DocumentTree => {
            let tree = open_directory(&dest, artifact_path)?;
            let mut entries_left = 100_000;
            snapshot_tree(&tree, &target, &mut budget, &mut entries_left, 0)?;
        }
    }
    let value = read_value_from_vfs(&snapshot, &descriptor)?;
    let content =
        serde_json::to_string(&value).map_err(|error| protocol_error(error.to_string()))?;
    if content.len() as u64 > MAX_PROJECT_MODEL_BYTES {
        return Err(protocol_error("Project model exceeds response size limit"));
    }
    Ok(Some(content))
}

fn vfs_error(error: impl std::fmt::Display) -> CliError {
    protocol_error(error.to_string())
}

pub(super) fn open_directory(root: &Dir, path: &Path) -> std::io::Result<Dir> {
    let mut directory = root.try_clone()?;
    for part in path.components() {
        let Component::Normal(name) = part else {
            return Err(std::io::Error::other("Directory path is not confined"));
        };
        directory = directory.open_dir_nofollow(name)?;
    }
    Ok(directory)
}

fn open_file(root: &Dir, path: &Path) -> std::io::Result<File> {
    let directory = open_directory(root, path.parent().unwrap_or(Path::new("")))?;
    let name = path
        .file_name()
        .ok_or_else(|| std::io::Error::other("Missing file name"))?;
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No).nonblock(true);
    directory.open_with(name, &options)
}

fn read_bounded(file: File, budget: &mut u64) -> Result<Vec<u8>, CliError> {
    let metadata = file.metadata()?;
    if !metadata.is_file() || metadata.len() > *budget {
        return Err(protocol_error(
            "Project artifact is not a regular file within the model size limit",
        ));
    }
    let mut bytes = Vec::new();
    file.take(*budget + 1).read_to_end(&mut bytes)?;
    *budget = budget
        .checked_sub(bytes.len() as u64)
        .ok_or_else(|| protocol_error("Project model exceeds size limit"))?;
    Ok(bytes)
}

fn snapshot_tree(
    directory: &Dir,
    target: &VfsPath,
    budget: &mut u64,
    entries_left: &mut usize,
    depth: usize,
) -> Result<(), CliError> {
    if depth > 128 {
        return Err(protocol_error("Project document tree exceeds depth limit"));
    }
    target.create_dir_all().map_err(vfs_error)?;
    for entry in directory.entries()? {
        *entries_left = entries_left
            .checked_sub(1)
            .ok_or_else(|| protocol_error("Project document tree exceeds entry limit"))?;
        let entry = entry?;
        let name = entry.file_name();
        let name_text = name
            .to_str()
            .ok_or_else(|| protocol_error("Project artifact filename must be UTF-8"))?;
        let child = target.join(name_text).map_err(vfs_error)?;
        if entry.file_type()?.is_dir() {
            snapshot_tree(
                &directory.open_dir_nofollow(&name)?,
                &child,
                budget,
                entries_left,
                depth + 1,
            )?;
        } else {
            let bytes = read_bounded(open_file(directory, Path::new(&name))?, budget)?;
            child.create_file().map_err(vfs_error)?.write_all(&bytes)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::commands::{
        ir_storage::{self, IrStorage},
        out_context::OutContext,
    };
    use morphir_devkit::{TaskId, TaskResult};

    fn load(out: &OutContext) -> Result<Option<String>, CliError> {
        let root = Dir::open_ambient_dir(&out.root, cap_std::ambient_authority()).unwrap();
        super::load(&root, &out.module)
    }

    #[test]
    fn follows_recorded_layout_and_refuses_tombstones() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext {
            root: temp.path().to_path_buf(),
            module: "packages/model".into(),
        };
        let ir = empty_ir();
        for layout in [
            morphir_devkit::IrLayout::SingleFile,
            morphir_devkit::IrLayout::DocumentTree,
        ] {
            for format in ["json", "yaml"] {
                let paths = out.task(&TaskId::compile()).unwrap();
                let descriptor = ir_storage::write_v4(
                    &paths.dest,
                    &IrStorage {
                        layout,
                        format: morphir_common::ir_transport::FormatId::new(format).unwrap(),
                    },
                    &ir,
                )
                .unwrap();
                let mut record = TaskResult::new(&TaskId::compile(), &out.module);
                record.ir = Some(descriptor);
                record.write(&paths.result).unwrap();
                let content = load(&out).unwrap().unwrap();
                assert_eq!(
                    serde_json::from_str::<serde_json::Value>(&content).unwrap(),
                    serde_json::to_value(&ir).unwrap()
                );
                record.tombstone = true;
                record.write(&paths.result).unwrap();
                assert!(
                    load(&out)
                        .unwrap_err()
                        .to_string()
                        .contains("successful compile")
                );
            }
        }
    }

    fn empty_ir() -> morphir_core::ir::v4::IRFile {
        use morphir_core::ir::v4::{
            Distribution, FormatVersion, IRFile, LibraryContent, PackageDefinition,
        };
        IRFile {
            format_version: FormatVersion::Integer(4),
            distribution: Distribution::Library(LibraryContent {
                package_name: morphir_core::naming::PackageName::parse("acme/model"),
                dependencies: Default::default(),
                def: PackageDefinition {
                    modules: Default::default(),
                },
            }),
        }
    }

    #[test]
    fn missing_record_allows_fallback_but_invalid_or_escaping_records_do_not() {
        let temp = tempfile::tempdir().unwrap();
        let out = OutContext {
            root: temp.path().to_path_buf(),
            module: Default::default(),
        };
        assert!(load(&out).unwrap().is_none());
        let paths = out.task(&TaskId::compile()).unwrap();
        std::fs::write(&paths.result, "broken").unwrap();
        assert!(load(&out).is_err());
        let mut record = TaskResult::new(&TaskId::compile(), &out.module);
        record.ir = Some(morphir_devkit::IrDescriptor {
            path: "../secret.json".into(),
            layout: morphir_devkit::IrLayout::SingleFile,
            format: "json".into(),
            version: "v4".into(),
        });
        record.write(&paths.result).unwrap();
        assert!(load(&out).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn compile_records_and_artifacts_cannot_follow_symlinks() {
        for link_record in [false, true] {
            let temp = tempfile::tempdir().unwrap();
            let external = tempfile::tempdir().unwrap();
            let out = OutContext {
                root: temp.path().to_path_buf(),
                module: Default::default(),
            };
            let paths = out.task(&TaskId::compile()).unwrap();
            std::fs::create_dir_all(&paths.dest).unwrap();
            let artifact = paths.dest.join("model.json");
            std::fs::write(&artifact, "{}").unwrap();
            let mut record = TaskResult::new(&TaskId::compile(), &out.module);
            record.ir = Some(morphir_devkit::IrDescriptor {
                path: "model.json".into(),
                layout: morphir_devkit::IrLayout::SingleFile,
                format: "json".into(),
                version: "v4".into(),
            });
            record.write(&paths.result).unwrap();
            assert!(load(&out).unwrap().is_some());
            let path = if link_record { paths.result } else { artifact };
            let outside = external.path().join("outside.json");
            std::fs::rename(&path, &outside).unwrap();
            std::os::unix::fs::symlink(&outside, &path).unwrap();
            assert!(load(&out).is_err());
        }
    }
}

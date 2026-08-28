use std::io::{Seek, SeekFrom, Write};
use std::path::Path;

use morphir_common::ir_transport::{Stage, TransportDiagnostic};
use morphir_common::vfs::{VfsPath, physical_root};
use morphir_core::traversal::IrCursor;

pub(super) fn write_file_atomically(
    path: &Path,
    write: impl FnOnce(&mut dyn Write) -> Result<(), TransportDiagnostic>,
) -> Result<(), TransportDiagnostic> {
    let parent = parent(path);
    std::fs::create_dir_all(parent).map_err(|error| publication_error(path, error))?;
    let mut temporary =
        tempfile::NamedTempFile::new_in(parent).map_err(|error| publication_error(path, error))?;
    write(temporary.as_file_mut())?;
    temporary
        .as_file_mut()
        .flush()
        .map_err(|error| publication_error(path, error))?;
    temporary
        .as_file()
        .sync_all()
        .map_err(|error| publication_error(path, error))?;
    temporary
        .persist(path)
        .map_err(|error| publication_error(path, error.error))?;
    Ok(())
}

pub(super) fn write_stdout_atomically(
    write: impl FnOnce(&mut dyn Write) -> Result<(), TransportDiagnostic>,
) -> Result<(), TransportDiagnostic> {
    let mut temporary =
        tempfile::tempfile().map_err(|error| publication_error(Path::new("<stdout>"), error))?;
    write(&mut temporary)?;
    temporary
        .seek(SeekFrom::Start(0))
        .map_err(|error| publication_error(Path::new("<stdout>"), error))?;
    let mut stdout = std::io::stdout().lock();
    std::io::copy(&mut temporary, &mut stdout)
        .map_err(|error| publication_error(Path::new("<stdout>"), error))?;
    stdout
        .flush()
        .map_err(|error| publication_error(Path::new("<stdout>"), error))
}

pub(super) fn write_tree_atomically(
    path: &Path,
    write: impl FnOnce(VfsPath) -> Result<(), TransportDiagnostic>,
) -> Result<(), TransportDiagnostic> {
    let parent = parent(path);
    std::fs::create_dir_all(parent).map_err(|error| publication_error(path, error))?;
    if path.exists() && !path.is_dir() {
        return Err(publication_error(
            path,
            "document-tree output exists and is not a directory",
        ));
    }
    let staging = tempfile::Builder::new()
        .prefix(".morphir-migrate-")
        .tempdir_in(parent)
        .map_err(|error| publication_error(path, error))?;
    write(physical_root(staging.path()))?;
    let staging_path = staging.keep();
    if !path.exists() {
        return std::fs::rename(&staging_path, path)
            .map_err(|error| publication_error(path, error));
    }
    let backup_holder = tempfile::Builder::new()
        .prefix(".morphir-backup-")
        .tempdir_in(parent)
        .map_err(|error| publication_error(path, error))?;
    let backup_path = backup_holder.path().to_owned();
    backup_holder
        .close()
        .map_err(|error| publication_error(path, error))?;
    std::fs::rename(path, &backup_path).map_err(|error| publication_error(path, error))?;
    if let Err(error) = std::fs::rename(&staging_path, path) {
        let rollback = std::fs::rename(&backup_path, path);
        return Err(publication_error(
            path,
            match rollback {
                Ok(()) => format!("publish failed and the existing tree was restored: {error}"),
                Err(rollback) => format!(
                    "publish failed ({error}); restore failed ({rollback}); backup remains at {}",
                    backup_path.display()
                ),
            },
        ));
    }
    if let Err(error) = std::fs::remove_dir_all(&backup_path) {
        tracing::warn!(
            destination = %path.display(),
            backup = %backup_path.display(),
            %error,
            "published the document tree but could not remove its backup"
        );
    }
    Ok(())
}

fn parent(path: &Path) -> &Path {
    path.parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."))
}

fn publication_error(path: &Path, error: impl std::fmt::Display) -> TransportDiagnostic {
    TransportDiagnostic::error(
        "morphir::ir::publication::failed",
        Stage::Publication,
        IrCursor::root(),
        format!("failed to publish {}: {error}", path.display()),
    )
    .with_guidance("verify the destination permissions and available storage, then retry")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn backup_cleanup_failure_does_not_report_a_failed_tree_publication() {
        use std::os::unix::fs::PermissionsExt as _;

        let temporary = tempfile::tempdir().unwrap();
        let destination = temporary.path().join("model");
        std::fs::create_dir(&destination).unwrap();
        std::fs::write(destination.join("old.txt"), "old").unwrap();
        std::fs::set_permissions(&destination, std::fs::Permissions::from_mode(0o500)).unwrap();

        let result = write_tree_atomically(&destination, |root| {
            let manifest = root.join("manifest.yaml").unwrap();
            let mut writer = manifest.create_file().unwrap();
            writer.write_all(b"formatVersion: 4\n").unwrap();
            Ok(())
        });

        let backups = std::fs::read_dir(temporary.path())
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| {
                path.file_name()
                    .unwrap()
                    .to_string_lossy()
                    .starts_with(".morphir-backup-")
            })
            .collect::<Vec<_>>();
        for backup in &backups {
            std::fs::set_permissions(backup, std::fs::Permissions::from_mode(0o700)).unwrap();
            std::fs::remove_dir_all(backup).unwrap();
        }

        assert!(!backups.is_empty(), "test did not force cleanup failure");
        assert!(result.is_ok(), "publication reported failure: {result:?}");
        assert_eq!(
            std::fs::read_to_string(destination.join("manifest.yaml")).unwrap(),
            "formatVersion: 4\n"
        );
    }
}

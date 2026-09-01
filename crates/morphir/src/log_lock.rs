use std::{
    collections::BTreeSet,
    fs::{self, File},
    io,
    path::{Path, PathBuf},
};

const LOG_ROOT_LOCK_FILE: &str = ".morphir-retention.lock";

pub(crate) struct LogReadLeases {
    _locks: Vec<File>,
    incomplete: bool,
}

impl LogReadLeases {
    pub(crate) fn incomplete(&self) -> bool {
        self.incomplete
    }
}

pub(crate) fn log_root_lock_path(log_root: &Path) -> PathBuf {
    log_root.join(LOG_ROOT_LOCK_FILE)
}

pub(crate) fn acquire_log_read_leases(log_roots: &[PathBuf]) -> LogReadLeases {
    let mut incomplete = false;
    let roots = log_roots
        .iter()
        .filter_map(|root| match root.canonicalize() {
            Ok(root) => Some(root),
            Err(error) if error.kind() == io::ErrorKind::NotFound => None,
            Err(_) => {
                incomplete = true;
                None
            }
        })
        .collect::<BTreeSet<_>>();
    let locks = roots
        .into_iter()
        .filter_map(|root| {
            let file = fs::OpenOptions::new()
                .read(true)
                .write(true)
                .create(true)
                .truncate(false)
                .open(log_root_lock_path(&root));
            match file.and_then(|file| {
                fs2::FileExt::lock_shared(&file)?;
                Ok(file)
            }) {
                Ok(file) => Some(file),
                Err(_) => {
                    incomplete = true;
                    None
                }
            }
        })
        .collect();

    LogReadLeases {
        _locks: locks,
        incomplete,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diagnostic_read_leases_exclude_retention_for_the_entire_log_root() {
        let temporary = tempfile::tempdir().unwrap();
        let leases = acquire_log_read_leases(&[temporary.path().to_path_buf()]);
        assert!(!leases.incomplete());

        let retention_lock = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(log_root_lock_path(temporary.path()))
            .unwrap();
        let error = fs2::FileExt::try_lock_exclusive(&retention_lock).unwrap_err();
        assert_eq!(
            error.raw_os_error(),
            fs2::lock_contended_error().raw_os_error()
        );

        drop(leases);
        fs2::FileExt::try_lock_exclusive(&retention_lock).unwrap();
        fs2::FileExt::unlock(&retention_lock).unwrap();
    }
}

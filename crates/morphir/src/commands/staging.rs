//! Atomic publication of a staged directory without replacing an existing path.
#[cfg(windows)]
use std::fs;
use std::path::Path;

#[cfg(unix)]
pub(crate) fn move_directory_no_replace(
    parent: &Path,
    staged: &Path,
    leaf: &std::ffi::OsStr,
) -> std::io::Result<()> {
    use cap_std::ambient_authority;
    use cap_std::fs::Dir;
    let parent_dir = Dir::open_ambient_dir(parent, ambient_authority())?;
    let staged_leaf = staged.file_name().ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "missing staged directory name",
        )
    })?;
    rustix::fs::renameat_with(
        &parent_dir,
        staged_leaf,
        &parent_dir,
        leaf,
        rustix::fs::RenameFlags::NOREPLACE,
    )
    .map_err(Into::into)
}

#[cfg(windows)]
pub(crate) fn move_directory_no_replace(
    parent: &Path,
    staged: &Path,
    leaf: &std::ffi::OsStr,
) -> std::io::Result<()> {
    // Windows directory rename fails if the destination already exists.
    fs::rename(staged, parent.join(leaf))
}

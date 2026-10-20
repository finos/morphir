//! Actual capture file acquisition; the parent owns the single bounded read loop.
use super::{CaptureControl, CaptureError, SelectedModule};
use cap_fs_ext::{DirExt, FollowSymlinks, OpenOptionsFollowExt, OpenOptionsSyncExt};
use cap_std::fs::{Dir, OpenOptions};
use std::{
    io::Read,
    path::{Component, Path},
};

pub(super) fn open_directory(root: &Dir, path: &Path) -> std::io::Result<Dir> {
    let mut directory = root.try_clone()?;
    for component in path.components() {
        let Component::Normal(name) = component else {
            return Err(std::io::Error::other("unconfined path"));
        };
        directory = directory.open_dir_nofollow(name)?;
    }
    Ok(directory)
}
#[derive(Clone, Copy)]
pub(super) enum CaptureReads<'a> {
    Historical,
    Observed {
        source: &'a crate::commands::ui::model_originals::observation::HostSourceLease,
        binding: &'a crate::commands::ui::provider::originals::OutputContentBinding,
        module: &'a SelectedModule,
    },
}
#[derive(Clone, Copy)]
pub(super) enum CaptureArea {
    Module,
    Destination,
}
/// Closed actual file alternatives, never a caller-supplied synthetic Reader.
pub(super) enum CaptureFile<'a> {
    Historical(cap_std::fs::File),
    Observed(morphir_common::config::observation::ObservedContentFile<'a>),
}
impl CaptureFile<'_> {
    pub(super) fn metadata(&self) -> std::io::Result<cap_std::fs::Metadata> {
        match self {
            Self::Historical(file) => file.metadata(),
            Self::Observed(file) => file.metadata(),
        }
    }
}
impl Read for CaptureFile<'_> {
    fn read(&mut self, bytes: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Self::Historical(file) => file.read(bytes),
            Self::Observed(file) => file.read(bytes),
        }
    }
}
impl CaptureReads<'_> {
    fn parent_label(&self, path: &Path, area: CaptureArea) -> Option<std::path::PathBuf> {
        let Self::Observed {
            source,
            binding,
            module,
        } = self
        else {
            return None;
        };
        let output = binding.label();
        let parent = path.parent().unwrap_or(Path::new(""));
        let bytes = output
            .as_os_str()
            .as_encoded_bytes()
            .len()
            .checked_add(module.as_str().len())?
            .checked_add(parent.as_os_str().as_encoded_bytes().len())?
            .checked_add("compile.dest".len() + 4)?;
        let mut label = std::path::PathBuf::new();
        if label.try_reserve(bytes).is_err() {
            source.mark_incomplete();
            return None;
        }
        label.push(output);
        if !module.as_str().is_empty() {
            label.push(module.as_str());
        }
        if matches!(area, CaptureArea::Destination) {
            label.push("compile.dest");
        }
        label.push(parent);
        Some(label)
    }

    fn root_parent_route(
        &self,
        path: &Path,
        area: CaptureArea,
    ) -> Result<
        Option<morphir_common::config::observation::RootRelativeDirectory>,
        CaptureFileOpenError,
    > {
        use crate::commands::ui::provider::originals::{OutputLocation, WorkspaceOutputRoute};
        use morphir_common::config::observation::RootRelativeDirectory;

        let Self::Observed {
            binding, module, ..
        } = self
        else {
            return Ok(None);
        };
        let OutputLocation::Workspace(route) = binding.location() else {
            return Ok(None);
        };
        let base = match route {
            WorkspaceOutputRoute::SelectedRoot => Path::new(""),
            WorkspaceOutputRoute::Descendant(path) => path.as_path(),
        };
        let parent = path.parent().unwrap_or(Path::new(""));
        let capacity = base
            .as_os_str()
            .len()
            .checked_add(module.as_str().len())
            .and_then(|n| n.checked_add(parent.as_os_str().len()))
            .and_then(|n| n.checked_add("compile.dest".len() + 4))
            .ok_or_else(|| std::io::Error::other("root read path capacity"))?;
        let mut relative = std::path::PathBuf::new();
        relative
            .try_reserve(capacity)
            .map_err(std::io::Error::other)?;
        if !base.as_os_str().is_empty() {
            relative.push(base);
        }
        if !module.as_str().is_empty() {
            relative.push(module.as_str());
        }
        if matches!(area, CaptureArea::Destination) {
            relative.push("compile.dest");
        }
        if !parent.as_os_str().is_empty() {
            relative.push(parent);
        }
        let route = if relative.as_os_str().is_empty() {
            RootRelativeDirectory::SelectedRoot
        } else {
            RootRelativeDirectory::descendant(&relative)?
        };
        Ok(Some(route))
    }
}

pub(super) enum CaptureFileOpenError {
    Io(std::io::Error),
    Native(morphir_common::config::observation::RootReadError),
    Control(CaptureError),
}
impl From<std::io::Error> for CaptureFileOpenError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}
impl From<morphir_common::config::observation::RootReadError> for CaptureFileOpenError {
    fn from(error: morphir_common::config::observation::RootReadError) -> Self {
        Self::Native(error)
    }
}
impl From<CaptureError> for CaptureFileOpenError {
    fn from(error: CaptureError) -> Self {
        Self::Control(error)
    }
}
impl CaptureFileOpenError {
    pub(super) fn is_not_found(&self) -> bool {
        match self {
            Self::Io(error)
            | Self::Native(morphir_common::config::observation::RootReadError::Io(error)) => {
                error.kind() == std::io::ErrorKind::NotFound
            }
            Self::Native(_) | Self::Control(_) => false,
        }
    }
    pub(super) fn into_capture_error(self) -> CaptureError {
        match self {
            Self::Control(error) => error,
            Self::Io(_) | Self::Native(_) => CaptureError::CaptureFailed,
        }
    }
}
pub(super) fn open_file<'a>(
    root: &Dir,
    path: &Path,
    reads: CaptureReads<'a>,
    area: CaptureArea,
    control: &CaptureControl,
) -> Result<CaptureFile<'a>, CaptureFileOpenError> {
    control.check()?;
    let parent = open_directory(root, path.parent().unwrap_or(Path::new("")))?;
    let mut options = OpenOptions::new();
    options.read(true).follow(FollowSymlinks::No).nonblock(true);
    let name = path
        .file_name()
        .ok_or_else(|| std::io::Error::other("missing name"))?;
    let file = match reads {
        CaptureReads::Historical => parent
            .open_with(name, &options)
            .map(CaptureFile::Historical)?,
        CaptureReads::Observed { source, .. } => {
            let scope = source.source_scope();
            match reads.root_parent_route(path, area)? {
                Some(route) => {
                    let relative = morphir_common::config::observation::RootRelativeFile::parse(
                        Path::new(name),
                    )?;
                    let plan = scope.prepare_root_read(&parent, &route, &relative)?;
                    #[cfg(test)]
                    control.read_boundary(super::CaptureReadBoundary::AfterMetadataBeforeData);
                    control.check()?;
                    CaptureFile::Observed(scope.open_read_only_root(&plan)?)
                }
                None => {
                    let label = reads.parent_label(path, area);
                    CaptureFile::Observed(
                        scope
                            .content_directory(&parent, label.as_deref())
                            .open_content_file(Path::new(name), &options)?,
                    )
                }
            }
        }
    };
    // Cancellation after a real acquisition drops the owned file before any
    // content Read. Keep the same cooperative Timeout outcome as the read loop.
    #[cfg(test)]
    control.read_boundary(super::CaptureReadBoundary::AfterDataBeforeRead);
    control.check()?;
    Ok(file)
}

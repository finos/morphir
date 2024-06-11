use std::{
    fmt::Debug,
    path::{Path, PathBuf},
};

pub use crate::workspace::states::*;

pub mod error;
pub mod settings;
mod states;

#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub struct WorkspaceRoot(PathBuf);
impl WorkspaceRoot {
    pub fn new(path: PathBuf) -> Self {
        WorkspaceRoot(path)
    }

    #[inline]
    pub fn as_path(&self) -> &Path {
        self.0.as_path()
    }
}

impl From<PathBuf> for WorkspaceRoot {
    #[inline]
    fn from(path: PathBuf) -> Self {
        WorkspaceRoot(path)
    }
}

impl AsRef<Path> for WorkspaceRoot {
    #[inline]
    fn as_ref(&self) -> &Path {
        self.as_path()
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::create_empty_sandbox;

    #[test]
    fn test_locate() {
        let sandbox = create_empty_sandbox();
        let workspace = LocatingWorkspace::new(sandbox.path());
        let located = workspace.locate().unwrap();
        assert_eq!(sandbox.path(), located.root.as_path());
    }
}

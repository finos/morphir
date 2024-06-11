use std::collections::HashSet;
use std::path::PathBuf;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum FsError {
    #[error("Ambiguous matches, multiple matching paths found: {0:?}")]
    AmbiguousMatches(HashSet<PathBuf>),
    #[error("Glob pattern not found.")]
    GlobPatternNotFound,
    #[error(
        "Failed to find the file or directory we were seeking. The target name(s) were: {0:?}"
    )]
    NotFound(HashSet<String>),
    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Invalid path: {0}")]
    InvalidPath(PathBuf),
}

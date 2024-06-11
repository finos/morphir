use std::path::PathBuf;

use derive_more::From;

pub type Result<T> = core::result::Result<T, Error>;

#[derive(Debug, From)]
pub enum Error {
    #[from]
    ConfigError(config::ConfigError),
    #[from]
    IoError(std::io::Error),
    #[from]
    WorkspaceNotFoundAtPath(PathBuf),
    InvalidPath {
        path: PathBuf,
        reason: String,
    },
}

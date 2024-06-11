pub type Result<T> = core::result::Result<T, Error>;

#[derive(Debug)]
pub enum Error {
    WorkspaceError(crate::workspace::Error),
}

//! Morphir CLI Library
//!
//! This library exposes CLI functionality for programmatic use and testing.

pub mod commands;
pub mod diagnostics;
pub mod error;
pub mod extensions;
pub mod home;
mod log_lock;
pub mod observability;
pub mod output;
mod session;
pub mod tui;

pub use error::CliError;
pub use output::OutputFormat;

// `commands::compile` and `commands::gleam` are compiled under both this
// library crate root and the `morphir` binary crate root, and name the
// session's `Ready` type as `crate::SessionReady` either way. Only the
// binary's `MorphirSession` ever builds a real one; this re-export exists so
// the library crate root has the same name to resolve.
pub use session::Ready;
pub(crate) use session::SessionReady;

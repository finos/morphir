//! Resolution of the user-level Morphir home directory.
//!
//! The canonical implementation lives in `morphir-common` so the whole
//! Morphir Rust ecosystem shares one definition; see
//! [`morphir_common::home`] for the resolution rules (`MORPHIR_HOME`
//! environment variable, falling back to the OS-specific `~/.morphir`).

pub use morphir_common::home::{MORPHIR_HOME_ENV, MorphirHome};

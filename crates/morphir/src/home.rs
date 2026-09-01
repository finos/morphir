//! Resolution of the user-level Morphir home directory.
//!
//! The canonical implementation lives in `morphir-common` so the whole
//! Morphir Rust ecosystem shares one definition; see
//! [`morphir_common::home`] for the resolution rules (`MORPHIR_HOME`
//! environment variable, falling back to the OS-specific `~/.morphir`).

pub use morphir_common::home::{MORPHIR_HOME_ENV, MorphirHome};

/// Resolve the effective CLI file-log directory for a known Morphir Home.
pub fn effective_cli_logs_dir(home: &MorphirHome) -> std::path::PathBuf {
    std::env::var_os("MORPHIR_LOG_DIR")
        .filter(|path| !path.is_empty())
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| home.cli_logs_dir())
}

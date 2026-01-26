//! Application configuration passed from CLI to UI.

use std::path::PathBuf;

/// Configuration for the Morphir Live application.
///
/// On native targets, this is populated from CLI arguments.
/// On WASM targets, this uses default values.
#[derive(Clone, Debug, Default)]
pub struct AppConfig {
    /// Path to morphir.toml, morphir.json, or containing directory
    pub config_path: Option<PathBuf>,
}

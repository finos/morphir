//! Platform-specific TOML editor module.
//!
//! This module provides a unified `TomlEditor` component that automatically
//! selects the appropriate implementation based on the target platform:
//!
//! - **Web (wasm32)**: Uses Monaco Editor with full syntax highlighting,
//!   code completion hints, and rich editing features.
//!
//! - **Desktop/Mobile (non-wasm32)**: Uses syntect for syntax highlighting
//!   with an editable textarea and live preview.

#[cfg(target_arch = "wasm32")]
mod web;

#[cfg(not(target_arch = "wasm32"))]
mod desktop;

// Re-export the platform-specific TomlEditor component
#[cfg(target_arch = "wasm32")]
pub use web::TomlEditor;

#[cfg(not(target_arch = "wasm32"))]
pub use desktop::TomlEditor;

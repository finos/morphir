//! Additive original-source capture. No connected method is advertised yet.
//!
//! The caller supplies an already-authorized output-directory capability and
//! selected module, never paths received from a model-originals request.

mod capture;
mod domain;
mod record;

pub use capture::{CaptureControl, capture_compiled};
pub use domain::*;

#[cfg(test)]
mod tests;

//! Additive original-source capture for an authenticated workspace host.
//!
//! The caller supplies an already-authorized output-directory capability and
//! selected module, never paths received from a model-originals request.

mod capture;
mod domain;
mod lifecycle;
pub(super) mod observation;
mod record;
pub(super) mod source_header;
pub(crate) mod wire;

#[cfg(test)]
mod provider_tests;

pub use capture::{CaptureControl, capture_compiled};
pub use domain::*;
pub use lifecycle::*;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod lifecycle_tests;

#[cfg(test)]
mod worker_observation_tests;

#[cfg(test)]
mod worker_boundary_tests;

#[cfg(test)]
mod host_source_tests;

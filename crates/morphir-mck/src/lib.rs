//! The Morphir Compatibility Kit (MCK) engine.
//!
//! The kit is a corpus of cases with fixed expected results; an implementation
//! under test takes part through an adapter process. This crate interprets the
//! kit. It never links an implementation's IR codec: expectations stay
//! independent of whatever is being tested.
//!
//! The contracts live in `spec/mck/` (`cli-contract.md`, `kit-manifest.md`,
//! `migration.md`). [`kit`] provides parsing, loading, content identity and
//! managed snapshots. [`ir`] provides adapter execution and vocabulary coverage;
//! [`schema`] validates the offline schema catalog and examples. [`report`]
//! validates and adjudicates consolidated reports and renders optional offline HTML.

pub mod format_version;
pub mod ir;
pub mod json;
pub mod kit;
pub mod metadata;
pub mod node_address;
pub mod package;
pub mod provenance;
pub mod report;
pub mod schema;
pub mod transport;

/// The runner's interpretation of a kit, as an integer a vendored kit's
/// manifest can bound (`driverContract`). It increases only when that
/// interpretation changes incompatibly.
pub const DRIVER_CONTRACT: u32 = 1;

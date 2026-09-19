//! The Morphir Compatibility Kit (MCK) engine.
//!
//! The kit is a corpus of cases with fixed expected results; an implementation
//! under test takes part through an adapter process. This crate interprets the
//! kit. It never links an implementation's IR codec: expectations stay
//! independent of whatever is being tested.
//!
//! The contracts live in `spec/mck/` (`cli-contract.md`, `kit-manifest.md`,
//! `migration.md`). This crate currently provides [`kit`]: the case grammar,
//! kit loading from a directory or the embedded copy, the
//! `mck-file-map-sha256/1` digest, kit status, and managed snapshots with
//! their `mck-kit.lock.json` manifest (vendor, verify, update). Adapter
//! transport, IR execution and reports follow in later slices of
//! finos/morphir#851.

pub mod json;
pub mod kit;

/// The runner's interpretation of a kit, as an integer a vendored kit's
/// manifest can bound (`driverContract`). It increases only when that
/// interpretation changes incompatibly.
pub const DRIVER_CONTRACT: u32 = 1;

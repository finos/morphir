//! The IR suite: comparison rules and the run loop.

pub mod compare;
pub mod coverage;
pub mod run;

pub use run::{Run, RunOptions, RunVerdict, Testee, run_kit, verdict};

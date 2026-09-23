//! Existing package integrity and resolution contracts. Fixed corpus expectations
//! are independent of adapters; no package implementation is linked here.
mod contract;
mod corpus;
mod json;
pub mod local_registry;
mod mvp_run;
mod projection;
mod report;
mod run;
mod schemas;

pub use contract::{Artifact, Capabilities, Contract, Operation, Request};
pub use corpus::{Case, Kit, load_kit};
pub use mvp_run::{MvpRun, run_mvp_process};
pub use report::{Record, Report, ResultKind};
pub use run::{run_kit, run_process};

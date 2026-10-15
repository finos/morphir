//! Workbench codec cases with parent-owned expectations and explicit adapters.

mod contract;
mod corpus;
mod jobs;
mod outcomes;
mod report;
mod run;

pub use contract::{
    ADMISSION_VERSION, Capabilities, Format, INVOCATION_VERSION, JOBS_VERSION, MAX_VALUE_BYTES,
    OUTCOMES_VERSION, OUTPUT_VERSION, Observation, Operation, VERSION,
};
pub use corpus::{Corpus, load};
pub use report::{
    Failure, MAX_OBSERVATION_BYTES, MAX_REPORT_BYTES, Phase, Record, Report, ResultKind,
    check_report,
};
pub use run::{RunOptions, run, run_with_session};

#[cfg(test)]
use contract::projection;
#[cfg(test)]
use run::{Testee, execute};

#[cfg(test)]
mod tests;

#[cfg(test)]
mod outcomes_tests;

#[cfg(test)]
mod jobs_tests;

//! Workbench codec cases with parent-owned expectations and explicit adapters.

mod capability_jobs;
mod capability_policy;
mod contract;
mod corpus;
mod jobs;
mod native_client;
mod native_frames;
mod native_owner;
mod native_replies;
mod outcomes;
mod report;
mod run;
mod selected_scheme;

pub use contract::{
    ADMISSION_VERSION, CAPABILITY_JOBS_VERSION, CAPABILITY_POLICY_VERSION, Capabilities, Format,
    INVOCATION_VERSION, JOBS_VERSION, MAX_VALUE_BYTES, NATIVE_CLIENT_VERSION,
    NATIVE_FRAMES_VERSION, NATIVE_OWNER_VERSION, NATIVE_REPLIES_VERSION, OUTCOMES_VERSION,
    OUTPUT_VERSION, Observation, Operation, SELECTED_SCHEME_VERSION, VERSION,
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

#[cfg(test)]
mod native_frames_tests;

#[cfg(test)]
mod native_replies_tests;

#[cfg(test)]
mod native_client_tests;

#[cfg(test)]
mod native_owner_tests;

#[cfg(test)]
mod selected_scheme_tests;

#[cfg(test)]
mod capability_policy_tests;

#[cfg(test)]
mod capability_jobs_tests;

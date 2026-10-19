//! Workbench codec cases with parent-owned expectations and explicit adapters.

mod artifact_client;
mod artifacts;
mod capability_executions;
mod capability_policy;
mod codec_comparison;
mod contract;
mod corpus;
mod executions;
mod http_policy;
mod local_models;
pub mod model_originals;
mod native_client;
mod native_frames;
mod native_owner;
mod native_policy_boundary;
mod native_policy_client;
mod native_policy_owner;
mod native_replies;
mod outcomes;
mod report;
mod run;
mod selected_scheme;
mod worksheet;

pub use contract::{
    ADMISSION_VERSION, ARTIFACT_TRANSFER_VERSION, CAPABILITY_EXECUTIONS_VERSION,
    CAPABILITY_POLICY_VERSION, CODEC_COMPARISON_VERSION, Capabilities, EXECUTIONS_VERSION, Format,
    HTTP_POLICY_BOUNDARY_VERSION, HTTP_POLICY_CLIENT_VERSION, HTTP_POLICY_PROVIDER_VERSION,
    INVOCATION_VERSION, LOCAL_MODELS_VERSION, MAX_VALUE_BYTES, NATIVE_CLIENT_VERSION,
    NATIVE_FRAMES_VERSION, NATIVE_OWNER_VERSION, NATIVE_POLICY_BOUNDARY_VERSION,
    NATIVE_POLICY_CLIENT_VERSION, NATIVE_POLICY_OWNER_VERSION, NATIVE_REPLIES_VERSION,
    OUTCOMES_VERSION, OUTPUT_VERSION, Observation, Operation, SELECTED_SCHEME_VERSION, VERSION,
    WORKSHEET_PROFILE_VERSION, WORKSHEET_VERSION,
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
mod executions_tests;

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
mod capability_executions_tests;

#[cfg(test)]
mod native_policy_tests;

#[cfg(test)]
mod http_policy_tests;

#[cfg(test)]
mod codec_comparison_tests;

#[cfg(test)]
mod worksheet_tests;

#[cfg(test)]
mod artifact_tests;

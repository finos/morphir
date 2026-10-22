//! Workbench codec cases with parent-owned expectations and explicit adapters.
pub use model_originals::{
    BrowserActionCursorFault, BrowserActionCursorTerminal, BrowserActionIssueError,
    BrowserConnectedOpening, BrowserExecutionAction,
};
pub use model_originals::{
    BrowserConnectedBoundary, BrowserEffectKind, BrowserEffectRef, BrowserUnsupportedActionKind,
};
pub use model_originals::{
    BrowserHostFact, BrowserHostInterruption, BrowserHostIoFailure, BrowserHostManifestFailure,
    BrowserHostPeerFinish, BrowserHostPollState, BrowserHostReadOutcome, BrowserHostReadPending,
    BrowserHostReadResult, BrowserHostSendOutcome, BrowserHostTranscript,
    BrowserHostTranscriptFault, BrowserHostTranscriptPrepareError, BrowserHostTranscriptRecord,
    BrowserHostTranscriptSnapshot, BrowserHostTranscriptTerminal, BrowserIssuedHostsTerminal,
    BrowserManifestPending, BrowserReplyPending,
};

mod artifact_client;
mod artifacts;
mod capability_executions;
mod capability_policy;
mod codec_comparison;
mod configuration;
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
mod report_facade;
mod run;
mod selected_scheme;
mod worksheet;

pub use configuration::{
    AdapterProtocol, ConsumerObservationSelection, OperationPortRevision, RunConfiguration,
    WorkbenchExecutionMode,
};
pub use contract::{
    ADMISSION_VERSION, ARTIFACT_TRANSFER_VERSION, CAPABILITY_EXECUTIONS_VERSION,
    CAPABILITY_POLICY_VERSION, CODEC_COMPARISON_VERSION, Capabilities, EXECUTIONS_VERSION, Format,
    HTTP_POLICY_BOUNDARY_VERSION, HTTP_POLICY_CLIENT_VERSION, HTTP_POLICY_PROVIDER_VERSION,
    INVOCATION_VERSION, LOCAL_MODELS_VERSION, MAX_VALUE_BYTES, MODEL_ORIGINALS_VERSION,
    NATIVE_CLIENT_VERSION, NATIVE_FRAMES_VERSION, NATIVE_OWNER_VERSION,
    NATIVE_POLICY_BOUNDARY_VERSION, NATIVE_POLICY_CLIENT_VERSION, NATIVE_POLICY_OWNER_VERSION,
    NATIVE_REPLIES_VERSION, OUTCOMES_VERSION, OUTPUT_VERSION, Observation, Operation,
    SELECTED_SCHEME_VERSION, VERSION, WORKSHEET_PROFILE_VERSION, WORKSHEET_VERSION,
};
pub use corpus::{Corpus, load};
pub use model_originals::{
    BrowserAction, BrowserActionKind, BrowserAdapterCompletion, BrowserApplicationRead,
    BrowserApplicationSource, BrowserCallbackOutcome, BrowserClient, BrowserClients,
    BrowserCollectionFault, BrowserCollectionTerminal, BrowserDocumentBounds,
    BrowserDocumentDecoder, BrowserDocumentError, BrowserDocumentErrorKind,
    BrowserDocumentProducer, BrowserDocumentRecord, BrowserDocumentSnapshot, BrowserDownloadTarget,
    BrowserExecutionInventory, BrowserExecutionOpening, BrowserExecutionPreparationError,
    BrowserExecutionRow, BrowserInputError, BrowserLoans, BrowserPreparationError,
    BrowserPreparationErrorKind, BrowserRetainedDocumentFrame, BrowserRowAttempt,
    BrowserRowCollection, BrowserRowProducer, BrowserRowSetupFailure, BrowserRowState,
    BrowserScope, BrowserSemantic, BrowserSourceFault, BrowserSourceIdentity,
    BrowserSourceTerminal, BrowserVisitError, PreparedBrowserClientRun,
    with_executed_browser_originals, with_prepared_browser_clients,
};
pub use model_originals::{
    BrowserArchiveData, BrowserDocumentContent, BrowserDocumentFactData, BrowserDocumentFrameData,
    BrowserDownloadOutcomeData, BrowserDownloadResultData, BrowserInventoryData,
    BrowserJsonStringSpan, BrowserOpeningData, BrowserProjectSelectionData,
    BrowserReadyArchiveData, BrowserSourceSelectionData, BrowserVisitData,
};
pub use model_originals::{
    ControlledDeliveryFault, ControlledHostDelivery, ControlledHostStimulus,
    ControlledManifestDelivery, ControlledOpening, ControlledPeerDelivery,
};
pub use report::{
    Failure, HistoricalReport, MAX_OBSERVATION_BYTES, MAX_REPORT_BYTES, Phase, Record, ResultKind,
};
pub use report_facade::{Report, check_report};
pub use run::{
    RunOptions, check_report_configured, run, run_configured,
    run_configured_with_installed_client_adapter, run_configured_with_native_adapter,
    run_configured_with_session_factory, run_with_session, run_with_session_configured,
};

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

#[cfg(test)]
mod model_originals_connected_tests;

#[cfg(test)]
mod native_pipeline_tests;

#[cfg(test)]
mod native_typed_fault_tests;

#[cfg(test)]
mod native_record_receiver_tests;

#[cfg(test)]
mod installed_borrowed_tests;

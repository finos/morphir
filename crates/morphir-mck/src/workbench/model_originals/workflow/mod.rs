//! Private workflow operand compiler, not registered capability or authority.
pub use pipeline::{
    BrowserActionCursorFault, BrowserActionCursorTerminal, BrowserActionIssueError,
    BrowserConnectedControlFault, BrowserConnectedJournalFault, BrowserConnectedOpening,
    BrowserConnectedOperationObservation, BrowserConnectedOperationsSnapshot,
    BrowserConnectedPreparationFailure, BrowserControllerPreparation, BrowserExecutionAction,
    BrowserInspectionBoundarySource, BrowserOwnedInspectionBoundary, BrowserInspectionPendingReply, BrowserOpeningSelectionReply, BrowserOwnedConnectedOpening,
    BrowserPreparedControllerStep, BrowserPreparedListenerStart,
};
pub use pipeline::{
    BrowserConnectedBoundary, BrowserEffectKind, BrowserEffectRef, BrowserUnsupportedActionKind,
};
pub use pipeline::{
    BrowserHostFact, BrowserHostInterruption, BrowserHostIoFailure, BrowserHostManifestFailure,
    BrowserHostPeerFinish, BrowserHostPollState, BrowserHostReadOutcome, BrowserHostReadPending,
    BrowserHostReadResult, BrowserHostSendOutcome, BrowserHostTranscript,
    BrowserHostTranscriptFault, BrowserHostTranscriptPrepareError, BrowserHostTranscriptRecord,
    BrowserHostTranscriptSnapshot, BrowserHostTranscriptTerminal, BrowserIssuedHostsTerminal,
    BrowserManifestPending, BrowserReplyPending,
};
mod decode;
use decode::*;
pub use pipeline::{
    BrowserAction, BrowserActionKind, BrowserApplicationRead, BrowserApplicationSource,
    BrowserCallbackOutcome, BrowserClient, BrowserClients, BrowserDocumentDecoder,
    BrowserDocumentError, BrowserDocumentErrorKind, BrowserDownloadTarget, BrowserInputError,
    BrowserLoans, BrowserPreparationError, BrowserPreparationErrorKind, BrowserScope,
    BrowserSemantic, BrowserSourceFault, BrowserSourceIdentity, BrowserSourceTerminal,
    BrowserVisitError, with_prepared_browser_clients,
};
pub use pipeline::{
    BrowserAdapterCompletion, BrowserExecutionInventory, BrowserExecutionPreparationError,
    BrowserExecutionRow, BrowserRowAttempt, BrowserRowSetupFailure, BrowserRowState,
    with_executed_browser_originals,
};
pub use pipeline::{
    BrowserArchiveData, BrowserDocumentContent, BrowserDocumentFactData, BrowserDocumentFrameData,
    BrowserDownloadOutcomeData, BrowserDownloadResultData, BrowserInventoryData,
    BrowserJsonStringSpan, BrowserOpeningData, BrowserProjectSelectionData,
    BrowserReadyArchiveData, BrowserSourceSelectionData, BrowserVisitData,
};
pub use pipeline::{
    BrowserCollectionFault, BrowserCollectionTerminal, BrowserDocumentBounds,
    BrowserDocumentProducer, BrowserDocumentRecord, BrowserDocumentSnapshot,
    BrowserExecutionOpening, BrowserRetainedDocumentFrame, BrowserRowCollection,
    BrowserRowProducer, PreparedBrowserClientRun,
};
pub use pipeline::{
    ControlledDeliveryFault, ControlledHostDelivery, ControlledHostStimulus,
    ControlledManifestDelivery, ControlledOpening, ControlledPeerDelivery,
};
#[macro_use]
mod macros;
mod compile;
mod domain;
mod expansion;
mod identity_input;
mod input;
mod installed_client;
mod installed_measurements;
mod meaning;
pub mod native;
pub use pipeline::installed::adapter as installed;
mod native_original;
mod pairing;
mod scope;
mod walk;
mod work;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod translated_tests;

#[cfg(test)]
mod input_shapes_tests;

#[cfg(test)]
mod input_boundaries_tests;

#[cfg(test)]
mod input_corpus_tests;

#[cfg(test)]
mod paired_corpus_tests;

mod ingress;

mod reviewed_sources;
mod source_proof;

mod source_compile;

#[cfg(test)]
mod bound_input_tests;

#[cfg(test)]
mod observed_tests;

mod observation_check;
mod observed;
mod record_check;

#[cfg(test)]
mod identity_tests;

#[cfg(test)]
mod report_context_tests;

#[cfg(test)]
mod context_checker_tests;

#[cfg(test)]
mod report_record_tests;

#[cfg(test)]
mod identity_source_baseline_tests;

#[cfg(test)]
mod record_boundary_tests;

#[cfg(test)]
mod record_boundary_support;

#[cfg(test)]
mod identity_additive_source_tests;

#[cfg(test)]
mod record_attempt_tests;

#[cfg(test)]
mod fixture_tests;

#[cfg(test)]
mod pipeline_tests;

#[cfg(test)]
mod workspace_predicate_tests;

pub(in crate::workbench) mod pipeline;

#[cfg(test)]
mod factory_tests;

#[cfg(test)]
mod pipeline_negotiation_tests;

#[cfg(test)]
mod pipeline_negotiation_evidence_tests;

#[cfg(test)]
mod native_original_unit_controls;

#[cfg(test)]
mod streaming_field_tests;

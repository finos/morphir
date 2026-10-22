//! Private browser observation support. No browser execution or source grant.
pub use adapter::execution_loans::{
    BrowserActionCursorFault, BrowserActionCursorTerminal, BrowserActionIssueError,
    BrowserConnectedControlFault, BrowserConnectedJournalFault, BrowserConnectedOpening,
    BrowserConnectedOperationObservation, BrowserConnectedOperationsSnapshot,
    BrowserConnectedPreparationFailure, BrowserControllerDispatch, BrowserControllerPreparation,
    BrowserControllerStepDispatcher, BrowserExecutionAction, BrowserInspectionBoundarySource,
    BrowserInspectionPendingReply, BrowserListenerDispatch, BrowserListenerStartDispatcher,
    BrowserOpeningSelectionReply, BrowserOwnedConnectedOpening, BrowserOwnedInspectionBoundary,
    BrowserPreparedControllerStep, BrowserPreparedListenerStart, BrowserSourcePumpGuardWork,
};
pub use collection::{
    BrowserHostFact, BrowserHostInterruption, BrowserHostIoFailure, BrowserHostManifestFailure,
    BrowserHostPeerFinish, BrowserHostPollState, BrowserHostReadOutcome, BrowserHostReadPending,
    BrowserHostReadResult, BrowserHostSendOutcome, BrowserHostTranscript,
    BrowserHostTranscriptFault, BrowserHostTranscriptPrepareError, BrowserHostTranscriptRecord,
    BrowserHostTranscriptSnapshot, BrowserHostTranscriptTerminal, BrowserIssuedHostsTerminal,
    BrowserManifestPending, BrowserReplyPending,
};
mod adapter;
mod archive_download;
mod collection;
mod controlled_input;
#[cfg(target_os = "macos")]
mod controller;
#[cfg(all(test, target_os = "macos"))]
#[path = "browser/controller/tests.rs"]
mod controller_tests;
mod execution;
mod funded_workflow;
#[cfg(test)]
#[path = "browser/funded_workflow/tests.rs"]
mod funded_workflow_tests;
mod inputs;
mod source_scope;
pub use adapter::execution_loans::{BrowserExecutionOpening, PreparedBrowserClientRun};
pub use adapter::*;
pub use collection::{
    BrowserCollectionFault, BrowserCollectionTerminal, BrowserDocumentBounds,
    BrowserDocumentProducer, BrowserDocumentRecord, BrowserDocumentSnapshot,
    BrowserRetainedDocumentFrame, BrowserRowCollection, BrowserRowProducer,
};
pub use execution::{
    BrowserAdapterCompletion, BrowserExecutionInventory, BrowserExecutionPreparationError,
    BrowserExecutionRow, BrowserRowAttempt, BrowserRowSetupFailure, BrowserRowState,
    with_executed_browser_originals,
};

use super::installed::observation::InstalledObservationOwner;
use super::{PreparationFault, Source, prepared_typed};
use crate::workbench::configuration::{
    BrowserClient as ConfiguredBrowserClient, Configuration, RunConfiguration,
};
use crate::workbench::model_originals::workflow::reviewed_sources::ReviewedSources;
use inputs::{BorrowedOriginalClients, BrowserOwnerLoans};

#[derive(Debug)]
enum BrowserPreparationFault<E> {
    WrongConfiguration,
    Preparation(PreparationFault<E>),
}
/// Source preparation and input loans only. No browser or artifact authority.
fn prepared_browser_originals<R, E>(
    source: &Source,
    configuration: &RunConfiguration,
    action: impl FnOnce(
        BorrowedOriginalClients<'_, '_, '_, '_, '_>,
        &mut BrowserOwnerLoans<'_>,
    ) -> Result<R, E>,
) -> Result<R, BrowserPreparationFault<E>> {
    let Configuration::BrowserOriginals {
        checker,
        receiving,
        client: ConfiguredBrowserClient::Chromium,
    } = &configuration.mode
    else {
        return Err(BrowserPreparationFault::WrongConfiguration);
    };
    // One storage-domain owner spans every input; it is not a CLI invocation.
    let mut receiving = InstalledObservationOwner::new(receiving);
    prepared_typed(
        source,
        checker,
        ReviewedSources::selected(),
        |compiled, owners| {
            action(
                BorrowedOriginalClients::new(compiled),
                &mut BrowserOwnerLoans::new(owners, &mut receiving),
            )
        },
    )
    .map_err(BrowserPreparationFault::Preparation)
}

#[cfg(test)]
mod privacy_probe;

#[cfg(target_os = "macos")]
pub use controller::{BrowserControllerBusinessCredit, BrowserControllerBusinessFundingFault};

#[cfg(target_os = "macos")]
pub use controller::{
    BrowserConnectedObservation, BrowserContinuingController, BrowserControllerContinueFailure,
    BrowserControllerFile, BrowserControllerFiles, BrowserControllerFinished,
    BrowserControllerLaunchFailure, BrowserControllerLaunchStage,
    BrowserControllerPreparationFailure, BrowserControllerPreparationFinished,
    BrowserControllerPreparationStage, BrowserControllerRetirement, BrowserFixedController,
    BrowserInspectionPreparationFailure, BrowserInspectionSettlementFailure,
    BrowserMaterializedController, BrowserStoppedController, BrowserUnlaunchedControllerFinished,
};

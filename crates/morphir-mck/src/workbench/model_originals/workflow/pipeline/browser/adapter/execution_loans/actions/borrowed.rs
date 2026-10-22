//! Borrowed source0 identity for the maintained native composite. This lends no
//! browser program, image permission, completion receipt or physical ownership.
use super::super::super::super::collection::{
    BrowserSourceHostAssociation, BrowserSourceHostAssociationError,
};
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::{
    BrowserApplicationSource, BrowserDocumentProducer, BrowserHostTranscript,
    ControlledHostStimulus,
};
use std::time::Instant;

trait OpeningToken: Sync {
    fn validate(&self, loans: &BrowserLoans<'_, '_>) -> Result<(), BrowserActionIssueError>;
    fn retention_gate(
        &self,
        action: &mut dyn FnMut() -> Result<(), BrowserActionIssueError>,
    ) -> Result<(), BrowserActionIssueError>;
}
impl OpeningToken for BrowserExecutionAction<'_, '_, '_, '_, '_, '_, '_> {
    fn validate(&self, loans: &BrowserLoans<'_, '_>) -> Result<(), BrowserActionIssueError> {
        self.owner.validate_action(self, loans)
    }
    fn retention_gate(
        &self,
        action: &mut dyn FnMut() -> Result<(), BrowserActionIssueError>,
    ) -> Result<(), BrowserActionIssueError> {
        self.owner
            .child
            .identity
            .while_active(|| {
                let cursor = lock(&self.owner.actions);
                match cursor.phase {
                    Phase::Issued(position)
                        if position == self.position()
                            && matches!(self.state, TokenState::Outstanding) => {}
                    Phase::Refused { cause, .. } => {
                        return Err(BrowserActionIssueError::Cursor(cause));
                    }
                    _ => {
                        return Err(BrowserActionIssueError::Cursor(
                            BrowserActionCursorFault::ForeignAction,
                        ));
                    }
                }
                drop(cursor);
                action()
            })
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?
    }
}

/// An engine-issued borrowed reference to ONE outstanding connected opening.
/// Its selectors are descriptive DATA. The actual native composite separately
/// verifies and retains its SAME acquired image, one-use host launch and joins.
/// It deliberately has no constructor, Clone or completion operation.
pub struct BrowserConnectedOpening<'a> {
    action: &'a dyn OpeningToken,
    association: BrowserSourceHostAssociation,
    selection: [&'a str; 3],
}
impl BrowserConnectedOpening<'_> {
    pub fn provider_id(&self) -> &str {
        self.selection[0]
    }
    pub fn locator(&self) -> &str {
        self.selection[1]
    }
    pub fn project_id(&self) -> &str {
        self.selection[2]
    }
    /// Validate the moved actual host owners against the SAME prepared journal.
    /// The returned end is descriptive and cannot renew the original lifetime.
    pub fn validate_host(
        &self,
        producer: &BrowserDocumentProducer,
        transcript: &BrowserHostTranscript,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Instant, BrowserActionIssueError> {
        self.action.validate(loans)?;
        self.association
            .validate_host(producer, transcript, stimulus, loans)
            .map_err(association_error)
    }
    pub fn validate_application(
        &self,
        application: &BrowserApplicationSource,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        self.action.validate(loans)?;
        loans.validate_controlled_application(application, stimulus)?;
        self.while_host_active(loans, || ()).map(|_| ())
    }
    /// Only the maintained native shell's already-funded retention/copy work
    /// belongs in this closure. Do not re-enter source/loan APIs here. No closure
    /// or module is accepted from DATA/wire. Returning never settles source0 or
    /// proves client acceptance, image association or physical joins.
    pub fn while_host_active<R>(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
        operation: impl FnOnce() -> R,
    ) -> Result<R, BrowserActionIssueError> {
        self.action.validate(loans)?;
        self.association.prepare_validation(loans)?;
        let mut operation = Some(operation);
        let mut result = None;
        self.action.retention_gate(&mut || {
            self.association
                .while_current(|| {
                    result = Some(operation.take().expect("exclusive one-call retention gate")());
                })
                .map_err(association_error)
        })?;
        Ok(result.expect("successful retention gate executed its closure"))
    }
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    /// Issue descriptive borrowed source0 identity from this exact live token.
    /// No host/controller effect or logical action consumption occurs here.
    pub fn connected_opening<'b>(
        &'b self,
        producer: &BrowserDocumentProducer,
        transcript: &BrowserHostTranscript,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<BrowserConnectedOpening<'b>, BrowserActionIssueError> {
        self.owner.validate_action(self, loans)?;
        let BrowserActionKind::BeginConnectedOpening {
            source: selected,
            project_id,
            scope: BrowserScope::Complete,
            semantic: BrowserSemantic::Projection,
            inventory_max_entries: 256,
            read_max_bytes: 65536,
            ..
        } = self.kind()
        else {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ));
        };
        if self.position() != 0 {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ));
        }
        let end = transcript
            .source_controller_end(producer, stimulus, self.position(), loans)
            .map_err(host_error)?;
        // The association funds its own Weak wrapper/counter work. The remainder
        // of this borrowed SDK and the selector scan are paid before retaining it.
        let bytes = size_of::<BrowserConnectedOpening<'_>>()
            .checked_sub(size_of::<BrowserSourceHostAssociation>())
            .ok_or_else(|| overflow(loans.inner))?;
        let selection = [selected.provider_id, selected.locator, project_id];
        let visits = selection
            .iter()
            .try_fold(bytes, |n, text| n.checked_add(text.len()))
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(bytes, 1, visits)?;
        if selection.iter().any(|text| text.as_bytes().contains(&0)) {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ));
        }
        let association = transcript
            .source_controller_association(producer, stimulus, self.position(), loans)
            .map_err(association_error)?;
        debug_assert_eq!(association.end(), end);
        Ok(BrowserConnectedOpening {
            action: self,
            association,
            selection,
        })
    }
}
fn host_error(
    error: super::super::super::super::collection::BrowserHostTranscriptPrepareError,
) -> BrowserActionIssueError {
    match error {
        super::super::super::super::collection::BrowserHostTranscriptPrepareError::Input(error) => {
            BrowserActionIssueError::Input(error)
        }
        super::super::super::super::collection::BrowserHostTranscriptPrepareError::Transcript(
            error,
        ) => BrowserActionIssueError::Host(error),
    }
}

pub(super) fn association_error(
    error: BrowserSourceHostAssociationError,
) -> BrowserActionIssueError {
    match error {
        BrowserSourceHostAssociationError::Input(error) => BrowserActionIssueError::Input(error),
        BrowserSourceHostAssociationError::Host(error) => BrowserActionIssueError::Host(error),
        BrowserSourceHostAssociationError::Collection(error) => {
            BrowserActionIssueError::Collection(error)
        }
        BrowserSourceHostAssociationError::DocumentClosed => {
            BrowserActionIssueError::DocumentClosed
        }
    }
}

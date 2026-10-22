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

pub(super) trait OpeningToken: Sync {
    fn validate_business_origin(
        &self,
        origin: &SourceBusinessOrigin,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError>;
    fn validate(&self, loans: &BrowserLoans<'_, '_>) -> Result<(), BrowserActionIssueError>;
    fn validate_lifetime(
        &self,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError>;
    fn same_lifetime(&self, lifetime: &SourceControllerLifetime) -> bool;
    fn supports(&self, operation: SourceOperationKind) -> bool;
    fn retention_gate(
        &self,
        action: &mut dyn FnMut() -> Result<(), BrowserActionIssueError>,
    ) -> Result<(), BrowserActionIssueError>;
    fn request(
        &self,
        operation: SourceOperationKind,
    ) -> Result<PendingSourceOperation, BrowserActionCursorFault>;
}
impl OpeningToken for BrowserExecutionAction<'_, '_, '_, '_, '_, '_, '_> {
    fn validate_business_origin(
        &self,
        origin: &SourceBusinessOrigin,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        origin.validate_action(self, loans)
    }
    fn supports(&self, operation: SourceOperationKind) -> bool {
        matches!(
            (self.kind(), operation),
            (
                BrowserActionKind::BeginConnectedOpening { .. },
                SourceOperationKind::Opening
            ) | (
                BrowserActionKind::AwaitConnectedBoundary {
                    boundary: BrowserConnectedBoundary::InspectionPending,
                    ..
                },
                SourceOperationKind::InspectionBoundary
            )
        )
    }
    fn same_lifetime(&self, lifetime: &SourceControllerLifetime) -> bool {
        lifetime.same_action_journal(self)
    }
    fn validate_lifetime(
        &self,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        lifetime.validate_action_relation(self, loans)
    }
    fn request(
        &self,
        operation: SourceOperationKind,
    ) -> Result<PendingSourceOperation, BrowserActionCursorFault> {
        if !self.supports(operation) {
            return Err(BrowserActionCursorFault::UnsupportedOperation);
        }
        lock(&self.owner.actions).operations.requested(operation)
    }
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
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_lifetime(
        &self,
        lifetime: &SourceControllerLifetime,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        self.action.validate_lifetime(lifetime, loans)?;
        if !self.association.same_relation(lifetime.association()) {
            return Err(BrowserActionIssueError::Input(source(
                BrowserSourceFault::ForeignSource,
            )));
        }
        self.while_host_active(loans, || ())
    }
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
        self.under_current_source_gate(loans, operation)
    }
    fn under_current_source_gate<R>(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
        operation: impl FnOnce() -> R,
    ) -> Result<R, BrowserActionIssueError> {
        current_source_gate(self.action, &self.association, loans, operation)
    }
}
pub(super) fn current_source_gate<R>(
    action: &dyn OpeningToken,
    association: &BrowserSourceHostAssociation,
    loans: &mut BrowserLoans<'_, '_>,
    operation: impl FnOnce() -> R,
) -> Result<R, BrowserActionIssueError> {
    action.validate(loans)?;
    association.prepare_validation(loans)?;
    let mut operation = Some(operation);
    let mut result = None;
    action.retention_gate(&mut || {
        association
            .while_current(|| {
                result = Some(operation.take().expect("exclusive one-call retention gate")());
            })
            .map_err(association_error)
    })?;
    Ok(result.expect("successful retention gate executed its closure"))
}

struct ControllerStepGateBrand;
/// One fixed mechanical controller step inside the SAME source and journal
/// gate. Native ownership and its independent first fault remain required.
pub struct BrowserPreparedControllerStep<'gate> {
    end: Instant,
    association: &'gate BrowserSourceHostAssociation,
    action: &'gate dyn OpeningToken,
    _brand: &'gate mut ControllerStepGateBrand,
}
impl BrowserPreparedControllerStep<'_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn supports(
        &self,
        operation: SourceOperationKind,
    ) -> bool {
        self.action.supports(operation)
    }
    pub fn original_end(&self) -> Instant {
        self.end
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn matches_lifetime(
        &self,
        lifetime: &SourceControllerLifetime,
    ) -> bool {
        self.association.same_relation(lifetime.association())
            && self.action.same_lifetime(lifetime)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn requested(
        &self,
        operation: SourceOperationKind,
    ) -> Result<PendingSourceOperation, BrowserActionCursorFault> {
        self.action.request(operation)
    }
}
impl BrowserConnectedOpening<'_> {
    /// The maintained native shell checks and holds its actual first-fault
    /// owner while the fixed controller performs its already-paid step. No
    /// source or loan API may be re-entered inside this scoped operation.
    pub fn with_prepared_controller_step<R, F>(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
        advance: F,
    ) -> Result<R, BrowserActionIssueError>
    where
        F: for<'gate> FnOnce(BrowserPreparedControllerStep<'gate>) -> R,
    {
        with_controller_step(self.action, &self.association, loans, advance)
    }
}
pub(super) fn with_controller_step<R, F>(
    action: &dyn OpeningToken,
    association: &BrowserSourceHostAssociation,
    loans: &mut BrowserLoans<'_, '_>,
    advance: F,
) -> Result<R, BrowserActionIssueError>
where
    F: for<'gate> FnOnce(BrowserPreparedControllerStep<'gate>) -> R,
{
    current_source_gate(action, association, loans, || ())?;
    let bytes = size_of::<BrowserPreparedControllerStep<'_>>()
        .checked_add(size_of::<Option<F>>())
        .and_then(|n| n.checked_add(size_of::<Option<R>>()))
        .and_then(|n| n.checked_add(size_of::<ControllerStepGateBrand>()))
        .ok_or_else(|| overflow(loans.inner))?;
    loans.reserve_controlled_host_storage(bytes, 4, bytes)?;
    current_source_gate(action, association, loans, || {
        let mut brand = ControllerStepGateBrand;
        advance(BrowserPreparedControllerStep {
            end: association.end(),
            association,
            action,
            _brand: &mut brand,
        })
    })
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

struct ListenerStartGateBrand;
/// Scoped permission for the maintained native shell's ONE already-prepared
/// Bound listener installation. It carries no completion or join assertion.
pub struct BrowserPreparedListenerStart<'gate> {
    end: std::time::Instant,
    _brand: &'gate mut ListenerStartGateBrand,
}
impl BrowserPreparedListenerStart<'_> {
    /// Descriptive original end. The native owner must check it immediately
    /// before its actual spawn, along with its own first fault and Bound state.
    pub fn original_end(&self) -> std::time::Instant {
        self.end
    }
}
impl BrowserConnectedOpening<'_> {
    /// Run ONLY the maintained native nominal SelectedSourceLaunch's fixed,
    /// already-funded Bound→Running installation. Do not re-enter loans/source
    /// APIs or call the legacy source-gated host.start inside this closure.
    /// No callback/program/module is accepted through DATA or the driver wire.
    ///
    /// A descriptive result may leave the held gate:
    /// ```
    /// use morphir_mck::workbench::{BrowserActionIssueError,
    ///     BrowserConnectedOpening, BrowserLoans};
    /// fn inspect(opening: &BrowserConnectedOpening<'_>, loans: &mut BrowserLoans<'_, '_>)
    ///     -> Result<std::time::Instant, BrowserActionIssueError> {
    ///     opening.with_prepared_listener_start(loans, |permit| permit.original_end())
    /// }
    /// ```
    /// The scope brand cannot escape the held source+journal gate:
    /// ```compile_fail
    /// use morphir_mck::workbench::{BrowserConnectedOpening, BrowserLoans,
    ///     BrowserPreparedListenerStart};
    /// fn escape<'a>(opening: &'a BrowserConnectedOpening<'a>,
    ///     loans: &mut BrowserLoans<'_, '_>) -> BrowserPreparedListenerStart<'a> {
    ///     opening.with_prepared_listener_start(loans, |permit| permit).unwrap()
    /// }
    /// ```
    pub fn with_prepared_listener_start<R, F>(
        &self,
        loans: &mut BrowserLoans<'_, '_>,
        start: F,
    ) -> Result<R, BrowserActionIssueError>
    where
        F: for<'gate> FnOnce(BrowserPreparedListenerStart<'gate>) -> R,
    {
        // First inspect the actual token/journal/end using the existing paid
        // guard. A revoked/refused/closed owner cannot fund a new start wrapper.
        self.while_host_active(loans, || ())?;
        let bytes = size_of::<BrowserPreparedListenerStart<'_>>()
            .checked_add(size_of::<Option<F>>())
            .and_then(|n| n.checked_add(size_of::<Option<R>>()))
            .and_then(|n| n.checked_add(size_of::<ListenerStartGateBrand>()))
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(bytes, 4, bytes)?;
        // This must use the private shared gate implementation, not widen the
        // retention-only public while_host_active closure contract.
        self.under_current_source_gate(loans, || {
            let mut brand = ListenerStartGateBrand;
            start(BrowserPreparedListenerStart {
                end: self.association.end(),
                _brand: &mut brand,
            })
        })
    }
}

/// A fixed maintained native controller dispatch. Native refusal is factual;
/// it is not a source reply, application result, or physical completion.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserControllerDispatch {
    Advanced(Result<(), BrowserConnectedControlFault>),
    NativeRefused,
}
pub trait BrowserControllerStepDispatcher {
    fn dispatch(&mut self, permit: BrowserPreparedControllerStep<'_>) -> BrowserControllerDispatch;
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserListenerDispatch {
    Installed,
    Refused,
}
pub trait BrowserListenerStartDispatcher {
    fn dispatch(&mut self, permit: BrowserPreparedListenerStart<'_>) -> BrowserListenerDispatch;
}
pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn business_gate_headers()
-> Option<(usize, usize)> {
    let step = size_of::<BrowserPreparedControllerStep<'_>>()
        .checked_add(size_of::<Option<&mut dyn BrowserControllerStepDispatcher>>())?
        .checked_add(size_of::<Option<BrowserControllerDispatch>>())?
        .checked_add(size_of::<ControllerStepGateBrand>())?;
    let listener = size_of::<BrowserPreparedListenerStart<'_>>()
        .checked_add(size_of::<Option<&mut dyn BrowserListenerStartDispatcher>>())?
        .checked_add(size_of::<Option<BrowserListenerDispatch>>())?
        .checked_add(size_of::<ListenerStartGateBrand>())?;
    Some((step, listener))
}
#[cfg(target_os = "macos")]
pub(super) fn prepaid_source_gate<R>(
    action: &dyn OpeningToken,
    association: &BrowserSourceHostAssociation,
    loans: &BrowserLoans<'_, '_>,
    credit:&mut crate::workbench::model_originals::workflow::pipeline::browser::controller::source_business::SourceBusinessCredit,
    operation:crate::workbench::model_originals::workflow::pipeline::browser::controller::source_business::SourceBusinessOperation,
    bytes: usize,
    execute: impl FnOnce() -> R,
) -> Result<R, BrowserActionIssueError> {
    // Nominal affinity is inspected before mutating the funding allowance.
    action.validate_business_origin(credit.origin(), loans)?;
    credit.origin().validate_host_association(association)?;
    // A known source/host/end refusal wins before funding bookkeeping faults.
    action.retention_gate(&mut || association.while_current(|| ()).map_err(association_error))?;
    credit
        .require_operation(operation)
        .map_err(BrowserActionIssueError::Funding)?;
    let work = SourceControllerLifetime::business_validation_work_upper()
        .and_then(|n| n.checked_mul(4))
        .and_then(|n| n.checked_add(bytes))
        .expect("business layout checked before credit issuance");
    credit
        .storage(bytes, 4, work)
        .map_err(BrowserActionIssueError::Funding)?;
    let mut execute = Some(execute);
    let mut result = None;
    action.retention_gate(&mut || {
        association
            .while_current(|| {
                result = Some(execute.take().expect("exclusive fixed dispatch")());
            })
            .map_err(association_error)
    })?;
    Ok(result.expect("successful fixed dispatch gate executed"))
}
#[cfg(target_os = "macos")]
pub(super) fn with_prepaid_controller_step(
    action: &dyn OpeningToken,
    association: &BrowserSourceHostAssociation,
    mut credit:crate::workbench::model_originals::workflow::pipeline::browser::controller::source_business::SourceBusinessCredit,
    loans: &BrowserLoans<'_, '_>,
    dispatcher: &mut dyn BrowserControllerStepDispatcher,
) -> Result<BrowserControllerDispatch, BrowserActionIssueError> {
    let bytes = business_gate_headers().expect("checked business layout").0;
    prepaid_source_gate(action,association,loans,&mut credit,
        crate::workbench::model_originals::workflow::pipeline::browser::controller::source_business::SourceBusinessOperation::ControllerDispatch,bytes,|| {
        let mut brand=ControllerStepGateBrand;
        dispatcher.dispatch(BrowserPreparedControllerStep{end:association.end(),association,action,_brand:&mut brand})
    })
}
#[cfg(target_os = "macos")]
impl BrowserConnectedOpening<'_> {
    pub fn with_prepaid_controller_step(
        &self,
        credit:crate::workbench::model_originals::workflow::pipeline::browser::controller::source_business::SourceBusinessCredit,
        loans: &BrowserLoans<'_, '_>,
        dispatcher: &mut dyn BrowserControllerStepDispatcher,
    ) -> Result<BrowserControllerDispatch, BrowserActionIssueError> {
        with_prepaid_controller_step(self.action, &self.association, credit, loans, dispatcher)
    }
    pub fn with_prepaid_listener_start(
        &self,
        mut credit:crate::workbench::model_originals::workflow::pipeline::browser::controller::source_business::SourceBusinessCredit,
        loans: &BrowserLoans<'_, '_>,
        dispatcher: &mut dyn BrowserListenerStartDispatcher,
    ) -> Result<BrowserListenerDispatch, BrowserActionIssueError> {
        let bytes = business_gate_headers().expect("checked business layout").1;
        prepaid_source_gate(self.action,&self.association,loans,&mut credit,
            crate::workbench::model_originals::workflow::pipeline::browser::controller::source_business::SourceBusinessOperation::ListenerStart,bytes,|| {
            let mut brand=ListenerStartGateBrand;
            dispatcher.dispatch(BrowserPreparedListenerStart{end:self.association.end(),_brand:&mut brand})
        })
    }
}

#[cfg(target_os = "macos")]
impl BrowserConnectedOpening<'_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_lifetime_prepaid(
        &self,
        lifetime: &SourceControllerLifetime,
        mut credit:crate::workbench::model_originals::workflow::pipeline::browser::controller::BrowserControllerBusinessCredit,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        lifetime.validate(loans)?;
        if !self.action.same_lifetime(lifetime)
            || !self.association.same_relation(lifetime.association())
        {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::ForeignAction,
            ));
        }
        prepaid_source_gate(self.action,&self.association,loans,&mut credit,
            crate::workbench::model_originals::workflow::pipeline::browser::controller::source_business::SourceBusinessOperation::LaunchValidation,
            size_of::<Self>(),||())
    }
}

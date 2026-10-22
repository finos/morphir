//! Fixed mechanical source conversation. Native image/host association remains
//! separate; these owners never construct a workflow verdict or physical join.
use super::super::adapter::BrowserLoans;
use super::super::adapter::execution_loans::{
    BrowserActionIssueError, BrowserConnectedControlFault, BrowserConnectedOpening,
    BrowserExecutionAction, BrowserInspectionBoundarySource, BrowserInspectionPendingReply,
    BrowserOpeningSelectionReply, BrowserOwnedConnectedOpening, BrowserOwnedInspectionBoundary,
    BrowserPreparedControllerStep,
};
use super::super::adapter::execution_loans::{
    MeasuredInspectionReply, MeasuredOpeningReply, PendingSourceOperation, SourceOperationKind,
};
use super::source_facade::SourceControllerPhysical;
use super::source_facade::{BrowserControllerRetirement, SourceControllerFinished};
use super::*;
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserConnectedObservation {
    Pending,
    Opening(BrowserOpeningSelectionReply),
    InspectionBoundary(BrowserInspectionPendingReply),
}
enum SourceReplyState {
    Starting,
    OpeningPending(PendingSourceOperation),
    OpeningObserved(MeasuredOpeningReply),
    InspectionPending(PendingSourceOperation),
    InspectionObserved(MeasuredInspectionReply),
    Unavailable,
}
/// Sole MCK physical controller plus its matching sealed source reply. No
/// public constructor accepts a reply, source index, expected result or program.
pub struct BrowserFixedController {
    physical: SourceControllerPhysical,
    reply: SourceReplyState,
    last_dispatch: Option<Instant>,
}
pub struct BrowserContinuingController {
    fixed: BrowserFixedController,
}
pub struct BrowserStoppedController {
    fixed: BrowserFixedController,
}
impl BrowserStoppedController {
    pub fn into_cleanup(self) -> BrowserFixedController {
        self.fixed
    }
}
pub struct BrowserInspectionPreparationFailure<
    'a,
    'compiled,
    'run,
    'case,
    'sources,
    'raw,
    'supplied,
> {
    controller: BrowserContinuingController,
    action: BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    BrowserInspectionPreparationFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub fn inspect_cause<R>(&self, inspect: impl FnOnce(&BrowserActionIssueError) -> R) -> R {
        self.action.inspect_controller_cause(inspect)
    }
    pub fn into_parts(
        self,
    ) -> (
        BrowserContinuingController,
        BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    ) {
        (self.controller, self.action)
    }
}
pub struct BrowserInspectionSettlementFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    controller: BrowserFixedController,
    boundary: BrowserOwnedInspectionBoundary<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    BrowserInspectionSettlementFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub fn inspect_cause<R>(&self, inspect: impl FnOnce(&BrowserActionIssueError) -> R) -> R {
        self.boundary.inspect_controller_cause(inspect)
    }
    pub fn into_parts(
        self,
    ) -> (
        BrowserFixedController,
        BrowserOwnedInspectionBoundary<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    ) {
        (self.controller, self.boundary)
    }
}
pub struct BrowserControllerFinished {
    physical: SourceControllerFinished,
}
impl BrowserControllerFinished {
    pub fn retirement(&self) -> BrowserControllerRetirement {
        self.physical.retirement
    }
    pub fn first_control_fault(&self) -> Option<BrowserConnectedControlFault> {
        self.physical.files.first_fault().map(control_fault)
    }
}
pub struct BrowserControllerContinueFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied> {
    controller: BrowserFixedController,
    opening: BrowserOwnedConnectedOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    BrowserControllerContinueFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub fn inspect_cause<R>(&self, inspect: impl FnOnce(&BrowserActionIssueError) -> R) -> R {
        self.opening.inspect_controller_cause(inspect)
    }
    pub fn into_parts(
        self,
    ) -> (
        BrowserFixedController,
        BrowserOwnedConnectedOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    ) {
        (self.controller, self.opening)
    }
}
impl BrowserContinuingController {
    pub fn into_cleanup(self) -> BrowserFixedController {
        self.fixed
    }
    pub fn prepare_inspection_boundary<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>(
        mut self,
        action: BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<
        (
            BrowserOwnedInspectionBoundary<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
            BrowserFixedController,
        ),
        BrowserInspectionPreparationFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    > {
        let credit = BrowserOwnedInspectionBoundary::preflight_action(
            &action,
            &self.fixed.physical.lifetime,
            loans,
        )
        .and_then(|()| {
            self.fixed
                .physical
                .prepayment
                .take_business(
                    super::source_business::SourceBusinessOperation::InspectionPreparation,
                )
                .map_err(BrowserActionIssueError::Funding)
        });
        let prepared = match credit {
            Ok(credit) => BrowserOwnedInspectionBoundary::prepare_prepaid(
                action,
                &self.fixed.physical.lifetime,
                credit,
                loans,
            ),
            Err(cause) => Err((action, cause)),
        };
        match prepared {
            Ok(boundary) => Ok((boundary, self.fixed)),
            Err((mut action, cause)) => {
                action.refuse_controller(cause);
                Err(BrowserInspectionPreparationFailure {
                    controller: self,
                    action,
                })
            }
        }
    }
}
impl BrowserFixedController {
    pub fn inspection_source<'a>(
        &mut self,
        boundary: &'a BrowserOwnedInspectionBoundary<'_, '_, '_, '_, '_, '_, '_>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<BrowserInspectionBoundarySource<'a>, BrowserActionIssueError> {
        boundary.preflight(&self.physical.lifetime, loans)?;
        let credit = self
            .physical
            .prepayment
            .take_business(super::source_business::SourceBusinessOperation::InspectionSource)
            .map_err(BrowserActionIssueError::Funding)?;
        boundary.source_prepaid(&self.physical.lifetime, credit, loans)
    }
    /// Source2 is the mandatory before-core checkpoint. This return type offers
    /// cleanup only; it cannot enqueue inspection or skip that unimplemented step.
    pub fn settle_inspection<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>(
        mut self,
        mut boundary: BrowserOwnedInspectionBoundary<
            'a,
            'compiled,
            'run,
            'case,
            'sources,
            'raw,
            'supplied,
        >,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<
        BrowserStoppedController,
        BrowserInspectionSettlementFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    > {
        let result=match &self.reply {
            SourceReplyState::InspectionObserved(measured)=>boundary.preflight(&self.physical.lifetime,loans)
                .and_then(|()|self.physical.prepayment.take_business(super::source_business::SourceBusinessOperation::InspectionSettlement).map_err(BrowserActionIssueError::Funding))
                .and_then(|credit|boundary.settle_controller_reply_prepaid(measured,&self.physical.lifetime,credit,loans)),
            _=>Err(BrowserActionIssueError::Cursor(super::super::adapter::execution_loans::BrowserActionCursorFault::UnsupportedOperation)),
        };
        match result {
            Ok(()) => Ok(BrowserStoppedController { fixed: self }),
            Err(cause) => {
                boundary.refuse_controller(cause);
                Err(BrowserInspectionSettlementFailure {
                    controller: self,
                    boundary,
                })
            }
        }
    }
    pub(super) fn from_physical(physical: SourceControllerPhysical) -> Self {
        Self {
            physical,
            reply: SourceReplyState::Starting,
            last_dispatch: None,
        }
    }
    /// Teardown retains its existing authority after business end/revocation.
    pub fn request_shutdown(&mut self) {
        self.physical.controller.request_shutdown();
    }
    pub fn poll_cleanup(&mut self) -> bool {
        self.physical.controller.poll_cleanup()
    }
    pub fn finish(self) -> Result<BrowserControllerFinished, Self> {
        let Self {
            physical,
            reply,
            last_dispatch,
        } = self;
        match physical.finish() {
            Ok(physical) => Ok(BrowserControllerFinished { physical }),
            Err(physical) => Err(Self {
                physical,
                reply,
                last_dispatch,
            }),
        }
    }
    /// Only existing collector DATA is inspected here. No current source/end or
    /// native fault can erase an earlier retained reply. No new business I/O is
    /// performed, and DATA arriving after the engine cut cannot heal that cut.
    pub fn observe_retained(
        &mut self,
    ) -> Result<BrowserConnectedObservation, BrowserConnectedControlFault> {
        let reply = match self.physical.controller.observe_source_retained() {
            Ok(ControllerProgress::Reply(reply)) => reply,
            Ok(_) => return Ok(BrowserConnectedObservation::Pending),
            Err(fault) => {
                self.record_fault(fault);
                return Err(control_fault(fault));
            }
        };
        match reply {
            ControllerReply::Attached | ControllerReply::ObservedDocumentStarted => {
                Ok(BrowserConnectedObservation::Pending)
            }
            ControllerReply::SourceOpening(reply) => {
                let pending =
                    match std::mem::replace(&mut self.reply, SourceReplyState::Unavailable) {
                        SourceReplyState::OpeningPending(pending) => pending,
                        other => {
                            self.reply = other;
                            self.record_fault(ControllerFault::Order);
                            return Err(BrowserConnectedControlFault::Order);
                        }
                    };
                let reply = opening_reply(reply);
                match pending.opening(reply) {
                    Ok(measured) => self.reply = SourceReplyState::OpeningObserved(measured),
                    Err(pending) => {
                        self.reply = SourceReplyState::OpeningPending(pending);
                        self.record_fault(ControllerFault::Order);
                        return Err(BrowserConnectedControlFault::Order);
                    }
                }
                Ok(BrowserConnectedObservation::Opening(reply))
            }
            ControllerReply::CapturedBoundary(reply) => {
                let pending =
                    match std::mem::replace(&mut self.reply, SourceReplyState::Unavailable) {
                        SourceReplyState::InspectionPending(pending) => pending,
                        other => {
                            self.reply = other;
                            self.record_fault(ControllerFault::Order);
                            return Err(BrowserConnectedControlFault::Order);
                        }
                    };
                let reply = boundary_reply(reply);
                match pending.inspection(reply) {
                    Ok(measured) => self.reply = SourceReplyState::InspectionObserved(measured),
                    Err(pending) => {
                        self.reply = SourceReplyState::InspectionPending(pending);
                        self.record_fault(ControllerFault::Order);
                        return Err(BrowserConnectedControlFault::Order);
                    }
                }
                Ok(BrowserConnectedObservation::InspectionBoundary(reply))
            }
            _ => {
                self.record_fault(ControllerFault::Order);
                Err(BrowserConnectedControlFault::Order)
            }
        }
    }
    /// Guard DATA for every probe, including the early cadence-None path.
    /// The three groups are outer lifetime validation, prepayment validation
    /// (lifetime plus retained relation stamp), and the final business gate.
    /// Credit transfer/dispatch-body work is already funded by the envelope.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn dispatch_probe_work_upper()
    -> Option<usize> {
        use super::super::adapter::execution_loans::{
            SourceControllerActivity, SourceControllerOperationShape,
        };
        use std::mem::size_of;
        SourceControllerActivity::validation_work_upper()?
            .checked_mul(3)?
            .checked_add(size_of::<Limits>().checked_mul(2)?)?
            .checked_add(size_of::<SourceControllerOperationShape>().checked_mul(2)?)?
            .checked_add(size_of::<Instant>().checked_mul(4)?)?
            .checked_add(size_of::<Option<Instant>>())?
            .checked_add(size_of::<Duration>().checked_mul(2)?)
    }
    /// Obtain the allowance before entering the scoped source/native dispatch
    /// gate. This probe validates the source and loan relation itself.
    pub fn dispatch_credit(
        &mut self,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<Option<super::BrowserControllerBusinessCredit>, BrowserActionIssueError> {
        self.physical.lifetime.validate(loans)?;
        if self
            .last_dispatch
            .is_some_and(|last| last.elapsed() < Duration::from_millis(1))
        {
            return Ok(None);
        }
        self.physical.prepayment.validate(
            &self.physical.lifetime,
            self.physical.controller.limits,
            loans,
        )?;
        self.physical
            .lifetime
            .while_business_active(|| {
                self.physical.prepayment.take_business(
                    super::source_business::SourceBusinessOperation::ControllerDispatch,
                )
            })?
            .map(Some)
            .map_err(BrowserActionIssueError::Funding)
    }
    /// Invoke only from the maintained native owner's scoped dispatch while its
    /// actual first-fault guard is held. The source permit cannot escape its
    /// parent→child→journal gate and must match this lifetime nominally.
    pub fn advance(
        &mut self,
        permit: BrowserPreparedControllerStep<'_>,
        interrupted: &AtomicBool,
    ) -> Result<(), BrowserConnectedControlFault> {
        if !permit.matches_lifetime(&self.physical.lifetime) {
            self.record_fault(ControllerFault::Order);
            return Err(BrowserConnectedControlFault::Order);
        }
        // Notifications may reveal DATA but cannot mint extra effect ticks.
        let now = Instant::now();
        if self
            .last_dispatch
            .is_some_and(|last| now.saturating_duration_since(last) < Duration::from_millis(1))
        {
            return Ok(());
        }
        self.last_dispatch = Some(now);
        if matches!(
            self.physical.controller.conversation,
            Conversation::PageReady
        ) && matches!(self.reply, SourceReplyState::Starting)
            && permit.supports(SourceOperationKind::Opening)
        {
            self.physical
                .controller
                .begin(ControllerCommand::BeginConnectedOpening)
                .map_err(control_fault)?;
            let pending = match permit.requested(SourceOperationKind::Opening) {
                Ok(pending) => pending,
                Err(_) => {
                    self.record_fault(ControllerFault::Order);
                    return Err(BrowserConnectedControlFault::Order);
                }
            };
            self.reply = SourceReplyState::OpeningPending(pending);
        }
        if matches!(
            self.physical.controller.conversation,
            Conversation::SourceReady
        ) && matches!(self.reply, SourceReplyState::OpeningObserved(_))
            && permit.supports(SourceOperationKind::InspectionBoundary)
        {
            self.physical
                .controller
                .begin(ControllerCommand::AwaitCapturedInspectionPending)
                .map_err(control_fault)?;
            let pending = match permit.requested(SourceOperationKind::InspectionBoundary) {
                Ok(pending) => pending,
                Err(_) => {
                    self.record_fault(ControllerFault::Order);
                    return Err(BrowserConnectedControlFault::Order);
                }
            };
            self.reply = SourceReplyState::InspectionPending(pending);
        }
        let result = self
            .physical
            .controller
            .advance_source_effects(permit.original_end(), interrupted);
        if let Err(fault) = result {
            self.record_fault(fault);
        }
        result.map_err(control_fault)
    }
    pub fn into_continuing<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>(
        mut self,
        mut opening: BrowserOwnedConnectedOpening<
            'a,
            'compiled,
            'run,
            'case,
            'sources,
            'raw,
            'supplied,
        >,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<
        BrowserContinuingController,
        BrowserControllerContinueFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    > {
        let result = match &self.reply {
            SourceReplyState::OpeningObserved(measured) => {
                let preflight=opening.validate_controller_lifetime(&self.physical.lifetime,loans);
                preflight.and_then(|()| self.physical.prepayment.take_business(super::source_business::SourceBusinessOperation::OpeningSettlement).map_err(BrowserActionIssueError::Funding))
                    .and_then(|credit|opening.settle_controller_reply_prepaid(measured,&self.physical.lifetime,credit,loans))
            },
            _ => Err(BrowserActionIssueError::Cursor(super::super::adapter::execution_loans::BrowserActionCursorFault::UnsupportedOperation)),
        };
        match result {
            Ok(()) => Ok(BrowserContinuingController { fixed: self }),
            Err(cause) => {
                opening.refuse_controller(cause);
                Err(BrowserControllerContinueFailure {
                    controller: self,
                    opening,
                })
            }
        }
    }
    fn record_fault(&mut self, fault: ControllerFault) {
        self.physical.controller.fail(fault);
        match &mut self.reply {
            SourceReplyState::OpeningPending(pending)
            | SourceReplyState::InspectionPending(pending) => pending.fault(control_fault(fault)),
            SourceReplyState::OpeningObserved(measured) => measured.fault(control_fault(fault)),
            SourceReplyState::InspectionObserved(measured) => measured.fault(control_fault(fault)),
            SourceReplyState::Starting | SourceReplyState::Unavailable => {}
        }
    }
}
fn opening_reply(reply: ControllerChoiceReply) -> BrowserOpeningSelectionReply {
    match reply {
        ControllerChoiceReply::ProjectSelected => BrowserOpeningSelectionReply::ProjectSelected,
        ControllerChoiceReply::NotReady => BrowserOpeningSelectionReply::NotReady,
        ControllerChoiceReply::Unavailable => BrowserOpeningSelectionReply::Unavailable,
        ControllerChoiceReply::OtherSelection => BrowserOpeningSelectionReply::OtherSelection,
        ControllerChoiceReply::Retired => BrowserOpeningSelectionReply::Retired,
        ControllerChoiceReply::Replaced => BrowserOpeningSelectionReply::Replaced,
    }
}
fn boundary_reply(reply: ControllerBoundaryReply) -> BrowserInspectionPendingReply {
    match reply {
        ControllerBoundaryReply::InspectionPending => {
            BrowserInspectionPendingReply::InspectionPending
        }
        ControllerBoundaryReply::OriginalsOnly => BrowserInspectionPendingReply::OriginalsOnly,
        ControllerBoundaryReply::Retired => BrowserInspectionPendingReply::Retired,
        ControllerBoundaryReply::Failed => BrowserInspectionPendingReply::Failed,
        ControllerBoundaryReply::NoOpening => BrowserInspectionPendingReply::NoOpening,
        ControllerBoundaryReply::Replaced => BrowserInspectionPendingReply::Replaced,
    }
}
fn control_fault(fault: ControllerFault) -> BrowserConnectedControlFault {
    match fault {
        ControllerFault::Acquisition => BrowserConnectedControlFault::Acquisition,
        ControllerFault::Clock => BrowserConnectedControlFault::Clock,
        ControllerFault::Spawn => BrowserConnectedControlFault::Spawn,
        ControllerFault::ChromiumExited => BrowserConnectedControlFault::ChromiumExited,
        ControllerFault::DriverExited => BrowserConnectedControlFault::DriverExited,
        ControllerFault::Process => BrowserConnectedControlFault::Process,
        ControllerFault::Shape => BrowserConnectedControlFault::Shape,
        ControllerFault::Order => BrowserConnectedControlFault::Order,
        ControllerFault::End => BrowserConnectedControlFault::End,
        ControllerFault::Cancelled => BrowserConnectedControlFault::Cancelled,
        ControllerFault::Input => BrowserConnectedControlFault::Input,
        ControllerFault::Output => BrowserConnectedControlFault::Output,
    }
}

/// Concrete maintained wrapper layouts. Six validation passes cover the
/// source/loan and lifetime preflights, exact operation journal, currentness
/// before bookkeeping, final child+host gate and receipt transition. Alias operands are added by the source-derived envelope.
pub(super) fn business_layout() -> Option<super::source_business::SourceBusinessLayout> {
    use super::super::adapter::execution_loans::{SourceControllerLifetime, business_gate_headers};
    use super::source_business::{SourceBusinessLayout, SourceBusinessResources};
    use std::mem::size_of;
    let guard = SourceControllerLifetime::business_validation_work_upper()?.checked_mul(6)?;
    let resources = |bytes: usize| -> Option<SourceBusinessResources> {
        Some(SourceBusinessResources {
            retained_bytes: bytes,
            slots: 4,
            visits: guard.checked_add(bytes)?,
            ..SourceBusinessResources::default()
        })
    };
    let (dispatch, listener) = business_gate_headers()?;
    Some(SourceBusinessLayout {
        launch_validation: resources(size_of::<BrowserConnectedOpening<'_>>())?,
        listener_start: resources(listener)?,
        opening_settlement: resources(
            size_of::<BrowserControllerContinueFailure<'_, '_, '_, '_, '_, '_, '_>>()
                .checked_add(size_of::<BrowserContinuingController>())?,
        )?,
        inspection_preparation: resources(
            size_of::<BrowserOwnedInspectionBoundary<'_, '_, '_, '_, '_, '_, '_>>()
                .checked_add(size_of::<
                    BrowserInspectionPreparationFailure<'_, '_, '_, '_, '_, '_, '_>,
                >())?
                .checked_add(2 * size_of::<usize>())?,
        )?,
        inspection_source: resources(
            size_of::<BrowserInspectionBoundarySource<'_>>()
                .checked_add(2 * size_of::<std::sync::atomic::AtomicUsize>())?,
        )?,
        inspection_settlement: resources(
            size_of::<BrowserInspectionSettlementFailure<'_, '_, '_, '_, '_, '_, '_>>()
                .checked_add(size_of::<BrowserStoppedController>())?,
        )?,
        controller_dispatch: resources(dispatch)?,
    })
}

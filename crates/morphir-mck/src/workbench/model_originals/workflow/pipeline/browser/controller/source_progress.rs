//! Fixed mechanical source conversation. Native image/host association remains
//! separate; these owners never construct a workflow verdict or physical join.
use super::*;
use super::source_facade::SourceControllerPhysical;
use super::source_facade::{SourceControllerFinished, BrowserControllerRetirement};
use super::super::adapter::execution_loans::{
    BrowserActionIssueError, BrowserConnectedControlFault, BrowserConnectedOpening,
    BrowserInspectionPendingReply, BrowserOpeningSelectionReply,
    BrowserOwnedConnectedOpening, BrowserPreparedControllerStep,
    BrowserExecutionAction, BrowserOwnedInspectionBoundary, BrowserInspectionBoundarySource,
};
use super::super::adapter::BrowserLoans;
use super::super::adapter::execution_loans::{
    MeasuredInspectionReply, MeasuredOpeningReply, PendingSourceOperation,
    SourceOperationKind,
};

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
}
pub struct BrowserContinuingController {
    fixed: BrowserFixedController,
}
pub struct BrowserStoppedController {fixed:BrowserFixedController}
impl BrowserStoppedController {
    pub fn into_cleanup(self)->BrowserFixedController {self.fixed}
}
pub struct BrowserInspectionPreparationFailure<'a,'compiled,'run,'case,'sources,'raw,'supplied> {
    controller:BrowserContinuingController,
    action:BrowserExecutionAction<'a,'compiled,'run,'case,'sources,'raw,'supplied>,
}
impl<'a,'compiled,'run,'case,'sources,'raw,'supplied> BrowserInspectionPreparationFailure<'a,'compiled,'run,'case,'sources,'raw,'supplied> {
    pub fn inspect_cause<R>(&self, inspect:impl FnOnce(&BrowserActionIssueError)->R)->R {self.action.inspect_controller_cause(inspect)}
    pub fn into_parts(self)->(BrowserContinuingController,BrowserExecutionAction<'a,'compiled,'run,'case,'sources,'raw,'supplied>){(self.controller,self.action)}
}
pub struct BrowserInspectionSettlementFailure<'a,'compiled,'run,'case,'sources,'raw,'supplied> {
    controller:BrowserFixedController,
    boundary:BrowserOwnedInspectionBoundary<'a,'compiled,'run,'case,'sources,'raw,'supplied>,
}
impl<'a,'compiled,'run,'case,'sources,'raw,'supplied> BrowserInspectionSettlementFailure<'a,'compiled,'run,'case,'sources,'raw,'supplied> {
    pub fn inspect_cause<R>(&self, inspect:impl FnOnce(&BrowserActionIssueError)->R)->R {self.boundary.inspect_controller_cause(inspect)}
    pub fn into_parts(self)->(BrowserFixedController,BrowserOwnedInspectionBoundary<'a,'compiled,'run,'case,'sources,'raw,'supplied>){(self.controller,self.boundary)}
}
pub struct BrowserControllerFinished {
    physical: SourceControllerFinished,
}
impl BrowserControllerFinished {
    pub fn retirement(&self) -> BrowserControllerRetirement {self.physical.retirement}
    pub fn first_control_fault(&self) -> Option<BrowserConnectedControlFault> {
        self.physical.files.first_fault().map(control_fault)
    }
}
pub struct BrowserControllerContinueFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied> {
    controller: BrowserFixedController,
    opening: BrowserOwnedConnectedOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied> BrowserControllerContinueFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied> {
    pub fn inspect_cause<R>(&self, inspect:impl FnOnce(&BrowserActionIssueError)->R)->R {
        self.opening.inspect_controller_cause(inspect)
    }
    pub fn into_parts(self)->(BrowserFixedController, BrowserOwnedConnectedOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>) {
        (self.controller,self.opening)
    }
}
impl BrowserContinuingController {
    pub fn into_cleanup(self)->BrowserFixedController {self.fixed}
    pub fn prepare_inspection_boundary<'a,'compiled,'run,'case,'sources,'raw,'supplied>(
        self,action:BrowserExecutionAction<'a,'compiled,'run,'case,'sources,'raw,'supplied>, loans:&mut BrowserLoans<'_,'_>,
    )->Result<(BrowserOwnedInspectionBoundary<'a,'compiled,'run,'case,'sources,'raw,'supplied>,BrowserFixedController),BrowserInspectionPreparationFailure<'a,'compiled,'run,'case,'sources,'raw,'supplied>> {
        match BrowserOwnedInspectionBoundary::prepare(action,&self.fixed.physical.lifetime,loans) {
            Ok(boundary)=>Ok((boundary,self.fixed)),
            Err((mut action,cause))=>{action.refuse_controller(cause);Err(BrowserInspectionPreparationFailure{controller:self,action})},
        }
    }
}
impl BrowserFixedController {
    pub fn inspection_source<'a>(
        &self, boundary:&'a BrowserOwnedInspectionBoundary<'_,'_,'_,'_,'_,'_,'_>, loans:&mut BrowserLoans<'_,'_>,
    )->Result<BrowserInspectionBoundarySource<'a>,BrowserActionIssueError> {
        boundary.source(&self.physical.lifetime,loans)
    }
    /// Source2 is the mandatory before-core checkpoint. This return type offers
    /// cleanup only; it cannot enqueue inspection or skip that unimplemented step.
    pub fn settle_inspection<'a,'compiled,'run,'case,'sources,'raw,'supplied>(
        self,mut boundary:BrowserOwnedInspectionBoundary<'a,'compiled,'run,'case,'sources,'raw,'supplied>,loans:&mut BrowserLoans<'_,'_>,
    )->Result<BrowserStoppedController,BrowserInspectionSettlementFailure<'a,'compiled,'run,'case,'sources,'raw,'supplied>> {
        let result=match &self.reply {
            SourceReplyState::InspectionObserved(measured)=>boundary.settle_controller_reply(measured,&self.physical.lifetime,loans),
            _=>Err(BrowserActionIssueError::Cursor(super::super::adapter::execution_loans::BrowserActionCursorFault::UnsupportedOperation)),
        };
        match result {
            Ok(())=>Ok(BrowserStoppedController{fixed:self}),
            Err(cause)=>{boundary.refuse_controller(cause);Err(BrowserInspectionSettlementFailure{controller:self,boundary})},
        }
    }
    pub(super) fn from_physical(physical: SourceControllerPhysical) -> Self {
        Self {physical, reply: SourceReplyState::Starting}
    }
    /// Teardown retains its existing authority after business end/revocation.
    pub fn request_shutdown(&mut self) {self.physical.controller.request_shutdown();}
    pub fn poll_cleanup(&mut self)->bool {self.physical.controller.poll_cleanup()}
    pub fn finish(self)->Result<BrowserControllerFinished,Self> {
        let Self {physical,reply}=self;
        match physical.finish() {
            Ok(physical)=>Ok(BrowserControllerFinished{physical}),
            Err(physical)=>Err(Self{physical,reply}),
        }
    }
    /// Only existing collector DATA is inspected here. No current source/end or
    /// native fault can erase an earlier retained reply. No new business I/O is
    /// performed, and DATA arriving after the engine cut cannot heal that cut.
    pub fn observe_retained(&mut self) -> Result<BrowserConnectedObservation, BrowserConnectedControlFault> {
        let reply = match self.physical.controller.observe_source_retained() {
            Ok(ControllerProgress::Reply(reply)) => reply,
            Ok(_) => return Ok(BrowserConnectedObservation::Pending),
            Err(fault) => {self.record_fault(fault); return Err(control_fault(fault));}
        };
        match reply {
            ControllerReply::Attached | ControllerReply::ObservedDocumentStarted => Ok(BrowserConnectedObservation::Pending),
            ControllerReply::SourceOpening(reply) => {
                let pending = match std::mem::replace(&mut self.reply, SourceReplyState::Unavailable) {
                    SourceReplyState::OpeningPending(pending) => pending,
                    other => {self.reply=other; self.record_fault(ControllerFault::Order); return Err(BrowserConnectedControlFault::Order);}
                };
                let reply = opening_reply(reply);
                match pending.opening(reply) {
                    Ok(measured) => self.reply=SourceReplyState::OpeningObserved(measured),
                    Err(pending) => {self.reply=SourceReplyState::OpeningPending(pending); self.record_fault(ControllerFault::Order); return Err(BrowserConnectedControlFault::Order);}
                }
                Ok(BrowserConnectedObservation::Opening(reply))
            }
            ControllerReply::CapturedBoundary(reply) => {
                let pending = match std::mem::replace(&mut self.reply, SourceReplyState::Unavailable) {
                    SourceReplyState::InspectionPending(pending) => pending,
                    other => {self.reply=other; self.record_fault(ControllerFault::Order); return Err(BrowserConnectedControlFault::Order);}
                };
                let reply = boundary_reply(reply);
                match pending.inspection(reply) {
                    Ok(measured) => self.reply=SourceReplyState::InspectionObserved(measured),
                    Err(pending) => {self.reply=SourceReplyState::InspectionPending(pending); self.record_fault(ControllerFault::Order); return Err(BrowserConnectedControlFault::Order);}
                }
                Ok(BrowserConnectedObservation::InspectionBoundary(reply))
            }
            _ => {self.record_fault(ControllerFault::Order); Err(BrowserConnectedControlFault::Order)}
        }
    }
    /// Invoke only from the maintained native owner's scoped dispatch while its
    /// actual first-fault guard is held. The source permit cannot escape its
    /// parent→child→journal gate and must match this lifetime nominally.
    pub fn advance(&mut self, permit: BrowserPreparedControllerStep<'_>, interrupted: &AtomicBool) -> Result<(), BrowserConnectedControlFault> {
        if !permit.matches_lifetime(&self.physical.lifetime) {
            self.record_fault(ControllerFault::Order);
            return Err(BrowserConnectedControlFault::Order);
        }
        if matches!(self.physical.controller.conversation, Conversation::PageReady)
            && matches!(self.reply, SourceReplyState::Starting)
            && permit.supports(SourceOperationKind::Opening) {
            self.physical.controller.begin(ControllerCommand::BeginConnectedOpening).map_err(control_fault)?;
            let pending = permit.requested(SourceOperationKind::Opening).map_err(|_| BrowserConnectedControlFault::Order)?;
            self.reply=SourceReplyState::OpeningPending(pending);
        }
        if matches!(self.physical.controller.conversation, Conversation::SourceReady)
            && matches!(self.reply, SourceReplyState::OpeningObserved(_))
            && permit.supports(SourceOperationKind::InspectionBoundary) {
            self.physical.controller.begin(ControllerCommand::AwaitCapturedInspectionPending).map_err(control_fault)?;
            let pending=permit.requested(SourceOperationKind::InspectionBoundary).map_err(|_|BrowserConnectedControlFault::Order)?;
            self.reply=SourceReplyState::InspectionPending(pending);
        }
        let result = self.physical.controller.advance_source_effects(permit.original_end(), interrupted);
        if let Err(fault)=result {self.record_fault(fault);}
        result.map_err(control_fault)
    }
    pub fn into_continuing<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>(
        self,
        mut opening: BrowserOwnedConnectedOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<BrowserContinuingController, BrowserControllerContinueFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>> {
        let result = match &self.reply {
            SourceReplyState::OpeningObserved(measured) => opening.settle_controller_reply(measured, &self.physical.lifetime, loans),
            _ => Err(BrowserActionIssueError::Cursor(super::super::adapter::execution_loans::BrowserActionCursorFault::UnsupportedOperation)),
        };
        match result {
            Ok(()) => Ok(BrowserContinuingController {fixed:self}),
            Err(cause) => {opening.refuse_controller(cause); Err(BrowserControllerContinueFailure {controller:self, opening})},
        }
    }
    fn record_fault(&mut self, fault: ControllerFault) {
        self.physical.controller.fail(fault);
        match &mut self.reply {
            SourceReplyState::OpeningPending(pending) | SourceReplyState::InspectionPending(pending) => pending.fault(control_fault(fault)),
            SourceReplyState::OpeningObserved(measured) => measured.fault(control_fault(fault)),
            SourceReplyState::InspectionObserved(measured) => measured.fault(control_fault(fault)),
            SourceReplyState::Starting | SourceReplyState::Unavailable => {}
        }
    }
}
fn opening_reply(reply: ControllerChoiceReply) -> BrowserOpeningSelectionReply {
    match reply {
        ControllerChoiceReply::ProjectSelected=>BrowserOpeningSelectionReply::ProjectSelected,
        ControllerChoiceReply::NotReady=>BrowserOpeningSelectionReply::NotReady,
        ControllerChoiceReply::Unavailable=>BrowserOpeningSelectionReply::Unavailable,
        ControllerChoiceReply::OtherSelection=>BrowserOpeningSelectionReply::OtherSelection,
        ControllerChoiceReply::Retired=>BrowserOpeningSelectionReply::Retired,
        ControllerChoiceReply::Replaced=>BrowserOpeningSelectionReply::Replaced,
    }
}
fn boundary_reply(reply: ControllerBoundaryReply) -> BrowserInspectionPendingReply {
    match reply {
        ControllerBoundaryReply::InspectionPending=>BrowserInspectionPendingReply::InspectionPending,
        ControllerBoundaryReply::OriginalsOnly=>BrowserInspectionPendingReply::OriginalsOnly,
        ControllerBoundaryReply::Retired=>BrowserInspectionPendingReply::Retired,
        ControllerBoundaryReply::Failed=>BrowserInspectionPendingReply::Failed,
        ControllerBoundaryReply::NoOpening=>BrowserInspectionPendingReply::NoOpening,
        ControllerBoundaryReply::Replaced=>BrowserInspectionPendingReply::Replaced,
    }
}
fn control_fault(fault: ControllerFault) -> BrowserConnectedControlFault {
    match fault {
        ControllerFault::Acquisition=>BrowserConnectedControlFault::Acquisition,
        ControllerFault::Clock=>BrowserConnectedControlFault::Clock,
        ControllerFault::Spawn=>BrowserConnectedControlFault::Spawn,
        ControllerFault::ChromiumExited=>BrowserConnectedControlFault::ChromiumExited,
        ControllerFault::DriverExited=>BrowserConnectedControlFault::DriverExited,
        ControllerFault::Process=>BrowserConnectedControlFault::Process,
        ControllerFault::Shape=>BrowserConnectedControlFault::Shape,
        ControllerFault::Order=>BrowserConnectedControlFault::Order,
        ControllerFault::End=>BrowserConnectedControlFault::End,
        ControllerFault::Cancelled=>BrowserConnectedControlFault::Cancelled,
        ControllerFault::Input=>BrowserConnectedControlFault::Input,
        ControllerFault::Output=>BrowserConnectedControlFault::Output,
    }
}

//! One bounded native/controller iteration and its loan-free wait. All source
//! authority remains in the actual SDK; these wrappers retain no new grant.
use super::*;
use crate::commands::ui::server::controlled_originals::{
    ControlledHostFault, ListenerOwner,
    ingress::{DocumentCollectOutcome, DocumentCollectStep},
};
use morphir_mck::workbench::{
    BrowserActionCursorFault, BrowserConnectedControlFault, BrowserConnectedObservation,
    BrowserControllerDispatch, BrowserControllerStepDispatcher, BrowserFixedController,
    BrowserInspectionBoundarySource, BrowserPreparedControllerStep,
};
use std::{mem::size_of, sync::atomic::AtomicBool, time::Duration};

pub(super) enum SelectedSourcePumpSource<'sdk, 'action> {
    Opening(&'sdk BrowserConnectedOpening<'action>),
    Inspection(&'sdk BrowserInspectionBoundarySource<'action>),
}
pub(super) struct SelectedSourcePumpStep {
    pub(super) observation: Result<BrowserConnectedObservation, BrowserConnectedControlFault>,
    pub(super) progress: SelectedSourcePumpProgress,
}
pub(super) enum SelectedSourcePumpProgress {
    // The maintained caller waits after BOTH nonterminal states. More is a
    // factual retained frame, not permission to spin without the fixed wait.
    More,
    AwaitingChange,
    Stopped(SelectedSourcePumpStop),
}
pub(super) enum SelectedSourcePumpStop {
    Controller(BrowserConnectedControlFault),
    Action(BrowserActionIssueError),
    Native(SelectedSourceStartFault),
    Document(DocumentCollectOutcome),
}
/// Requested native storage/work only, never a reusable source allowance.
pub(super) struct SelectedSourcePumpFunding {
    pub(super) bytes: usize,
    pub(super) slots: usize,
    pub(super) visits: usize,
}
enum DispatchState {
    Prepared,
    Entered,
    NativeRefused(SelectedSourceStartFault),
    Advanced(Result<(), BrowserConnectedControlFault>),
}
struct Dispatcher<'a> {
    host: &'a SelectedSourceHost,
    controller: &'a mut BrowserFixedController,
    interrupted: &'a AtomicBool,
    actual: DispatchState,
}
impl BrowserControllerStepDispatcher for Dispatcher<'_> {
    fn dispatch(&mut self, permit: BrowserPreparedControllerStep<'_>) -> BrowserControllerDispatch {
        if !matches!(self.actual, DispatchState::Prepared) {
            return BrowserControllerDispatch::NativeRefused;
        }
        self.actual = DispatchState::Entered;
        let native = (|| {
            // The SDK already holds parent→child→journal. Keep native first
            // held through the actual fixed advance, with no source reentry.
            let first = SelectedSourceHost::active_native_first(&self.host.host.state)?;
            if self.host.application.end != permit.original_end()
                || self.host.host.state.end != permit.original_end()
            {
                return Err(SelectedSourceStartFault::OriginalEnd);
            }
            if Instant::now() >= permit.original_end() {
                return Err(SelectedSourceStartFault::Native(ControlledHostFault::End));
            }
            if !matches!(self.host.host.listener, ListenerOwner::Running { .. }) {
                return Err(SelectedSourceStartFault::Native(
                    ControlledHostFault::Listener,
                ));
            }
            let actual = self.controller.advance(permit, self.interrupted);
            drop(first);
            Ok(actual)
        })();
        match native {
            Ok(actual) => {
                self.actual = DispatchState::Advanced(actual);
                BrowserControllerDispatch::Advanced(actual)
            }
            Err(cause) => {
                self.actual = DispatchState::NativeRefused(cause);
                BrowserControllerDispatch::NativeRefused
            }
        }
    }
}

pub(super) fn step(
    host: &mut SelectedSourceHost,
    controller: &mut BrowserFixedController,
    source: SelectedSourcePumpSource<'_, '_>,
    loans: &mut BrowserLoans<'_, '_>,
    interrupted: &AtomicBool,
) -> SelectedSourcePumpStep {
    // DATA already retained by the actual collector is folded before any later
    // source/native/end refusal. Never convert a later stop into lost history.
    let observation = controller.observe_retained();
    if let Err(cause) = observation {
        return SelectedSourcePumpStep {
            observation,
            progress: SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Controller(
                cause,
            )),
        };
    }
    let progress = match host.host.collect_document_step(loans) {
        DocumentCollectStep::FrameRetained => SelectedSourcePumpProgress::More,
        DocumentCollectStep::AwaitingChange => SelectedSourcePumpProgress::AwaitingChange,
        DocumentCollectStep::Terminal(actual) => {
            return SelectedSourcePumpStep {
                observation,
                progress: SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Document(
                    actual,
                )),
            };
        }
    };
    let native_check = SelectedSourceHost::active_native_first(&host.host.state).map(drop);
    if let Err(cause) = native_check {
        return SelectedSourcePumpStep {
            observation,
            progress: SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Native(cause)),
        };
    }
    let credit = match controller.dispatch_credit(loans) {
        Ok(Some(credit)) => credit,
        Ok(None) => {
            return SelectedSourcePumpStep {
                observation,
                progress,
            };
        }
        Err(cause) => {
            return SelectedSourcePumpStep {
                observation,
                progress: SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Action(
                    cause,
                )),
            };
        }
    };
    let mut dispatcher = Dispatcher {
        host,
        controller,
        interrupted,
        actual: DispatchState::Prepared,
    };
    let gate = match source {
        SelectedSourcePumpSource::Opening(source) => {
            source.with_prepaid_controller_step(credit, loans, &mut dispatcher)
        }
        SelectedSourcePumpSource::Inspection(source) => {
            source.with_prepaid_controller_step(credit, loans, &mut dispatcher)
        }
    };
    // The actual native/advance result is retained separately from the SDK
    // result. A later gate refusal cannot rewrite a performed advance.
    let progress = match dispatcher.actual {
        DispatchState::NativeRefused(cause) => {
            SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Native(cause))
        }
        DispatchState::Advanced(Err(cause)) => {
            SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Controller(cause))
        }
        DispatchState::Advanced(Ok(())) => match gate {
            Ok(BrowserControllerDispatch::Advanced(Ok(()))) => progress,
            Err(cause) => {
                SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Action(cause))
            }
            _ => invalid_dispatch(),
        },
        DispatchState::Prepared | DispatchState::Entered => match gate {
            Err(cause) => {
                SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Action(cause))
            }
            _ => invalid_dispatch(),
        },
    };
    SelectedSourcePumpStep {
        observation,
        progress,
    }
}
fn invalid_dispatch() -> SelectedSourcePumpProgress {
    SelectedSourcePumpProgress::Stopped(SelectedSourcePumpStop::Action(
        BrowserActionIssueError::Cursor(BrowserActionCursorFault::UnsupportedOperation),
    ))
}

/// One fixed absolute tick. ACK/other non-ready notifications do not return a
/// new pump iteration or reset its timer. No mutable owner loan crosses await.
pub(super) async fn wait(host: &BoundControlledUiHost) {
    let tick = (Instant::now() + Duration::from_millis(1)).min(host.state.end);
    // Even an already-queued frame must not let a caller's More loop starve
    // the SAME current-thread runtime that writes its ACK. This fixed yield
    // is part of the measured future, not a caller-supplied future or task.
    tokio::task::yield_now().await;
    let timer = tokio::time::sleep_until(tick.into());
    tokio::pin!(timer);
    loop {
        if host.document_collection_ready() {
            return;
        }
        tokio::select! {
            biased;
            _ = &mut timer => return,
            _ = host.wait_document_change() => (),
        }
    }
}

pub(super) fn funding(
    host: &BoundControlledUiHost,
) -> Result<SelectedSourcePumpFunding, SelectedSourceStartFault> {
    let layout = host.document_pump_layout().ok_or(SelectedSourceStartFault::Native(
        ControlledHostFault::Document(
            crate::commands::ui::server::controlled_originals::ingress::DocumentIngressFault::ForeignDocument,
        ),
    ))?;
    let checked = || -> Option<SelectedSourcePumpFunding> {
        // This exact future borrows the retained host only. Creating/dropping
        // it unpolled neither registers a timer nor polls a source or socket.
        let actual_wait = wait(host);
        let wait_bytes = std::mem::size_of_val(&actual_wait);
        drop(actual_wait);
        let headers = size_of::<Dispatcher<'_>>()
            .checked_add(size_of::<DispatchState>())?
            .checked_add(size_of::<SelectedSourcePumpSource<'_, '_>>())?
            .checked_add(size_of::<SelectedSourcePumpStep>())?
            .checked_add(size_of::<SelectedSourcePumpProgress>())?
            .checked_add(size_of::<SelectedSourcePumpStop>())?
            .checked_add(size_of::<SelectedSourcePumpFunding>())?
            .checked_add(size_of::<
                std::sync::MutexGuard<'_, Option<ControlledHostFault>>,
            >())?;
        let repeated_headers = headers.checked_add(wait_bytes)?;
        let ticks = usize::try_from(
            host.state
                .end
                .saturating_duration_since(Instant::now())
                .as_nanos()
                .div_ceil(1_000_000),
        )
        .ok()?
        .checked_add(2)?;
        // A returned queued-frame wake is consumed by one synchronous step.
        // Internal non-ready notifications stay within the SAME absolute tick.
        let steps = ticks.checked_add(layout.record_bound)?.checked_add(2)?;
        let scans = steps
            .checked_mul(3)?
            .checked_add(layout.notification_bound.checked_mul(3)?)?;
        // Empty collection/probe ticks still traverse the SAME MCK loan,
        // application, producer and source relation guards. Those costs come
        // from their maintained layouts, independently of native headers and
        // per-frame decoding. Waiting can restart only for a finite admitted
        // notification; it never resets the original absolute tick.
        let guards = BrowserLoans::source_pump_guard_work_upper()?;
        let guard_metadata = std::mem::size_of_val(&guards);
        let bytes = repeated_headers.checked_add(guard_metadata)?;
        // Each admitted notification can finish one previously Pending
        // source-gated poll and begin its replacement wait. Initial waits are
        // bounded by steps; both notification-side polls are prepaid here.
        let wait_calls = steps.checked_add(layout.notification_bound.checked_mul(2)?)?;
        let visits = repeated_headers
            .checked_mul(steps)?
            .checked_add(guard_metadata)?
            .checked_add(layout.readiness_scan_bytes.checked_mul(scans)?)?
            .checked_add(size_of::<Instant>().checked_mul(ticks)?.checked_mul(3)?)?
            .checked_add(guards.collection_step_visits.checked_mul(steps)?)?
            .checked_add(guards.controller_probe_visits.checked_mul(steps)?)?
            .checked_add(guards.wait_source_poll_visits.checked_mul(wait_calls)?)?;
        Some(SelectedSourcePumpFunding {
            bytes,
            slots: 10,
            visits,
        })
    };
    checked().ok_or(SelectedSourceStartFault::SizeOverflow)
}

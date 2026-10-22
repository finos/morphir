//! Native listener transition under the genuine source0 SDK.
//! No controller reply, logical settlement or process join is synthesized here.
use super::*;
use morphir_mck::workbench::{
    BrowserListenerDispatch, BrowserListenerStartDispatcher, BrowserPreparedListenerStart,
};

#[cfg(target_os = "macos")]
mod composition;
#[cfg(target_os = "macos")]
use composition::{
    SelectedSourceControllerLaunchFailure, SelectedSourceControllerLaunched,
    SelectedSourceControllerPreparationFailure, SelectedSourceControllerPrepared,
};

#[derive(Debug)]
enum SelectedSourceStartFault {
    Action(BrowserActionIssueError),
    Funding(BrowserInputError),
    Native(super::super::super::ControlledHostFault),
    OriginalEnd,
    SizeOverflow,
}

/// The SAME native owner after actual listener installation. This is not a
/// controller reply, action completion or physical join receipt.
struct SelectedSourceStarted<'a> {
    owner: SelectedSourceHost,
    opening: BrowserConnectedOpening<'a>,
}

struct SelectedSourceStartFailure<'a> {
    fault: SelectedSourceStartFault,
    launch: SelectedSourceLaunch<'a>,
}

/// Native context retained before physical acquisition spends residual cleanup
/// capacity. This owns a real runtime Handle, not listener-start authority.
struct SelectedSourcePrepared<'a> {
    launch: SelectedSourceLaunch<'a>,
    runtime: tokio::runtime::Handle,
}

/// Native effects and the SDK gate result are separate factual dimensions.
/// In particular, a later gate refusal must not erase an installed listener.
enum SelectedSourceListenerOutcome {
    NotDispatched,
    EnteredWithoutResult,
    Completed(Result<(), SelectedSourceStartFault>),
}

enum SelectedSourceListenerState {
    Prepared(tokio::runtime::Handle),
    Entered,
    Completed(Result<(), SelectedSourceStartFault>),
}

struct SelectedSourceListenerDispatcher<'a> {
    owner: &'a mut SelectedSourceHost,
    state: SelectedSourceListenerState,
}

impl<'a> SelectedSourceListenerDispatcher<'a> {
    fn new(owner: &'a mut SelectedSourceHost, runtime: tokio::runtime::Handle) -> Self {
        Self {
            owner,
            state: SelectedSourceListenerState::Prepared(runtime),
        }
    }

    fn into_outcome(self) -> SelectedSourceListenerOutcome {
        match self.state {
            SelectedSourceListenerState::Prepared(_) => {
                SelectedSourceListenerOutcome::NotDispatched
            }
            SelectedSourceListenerState::Entered => {
                SelectedSourceListenerOutcome::EnteredWithoutResult
            }
            SelectedSourceListenerState::Completed(result) => {
                SelectedSourceListenerOutcome::Completed(result)
            }
        }
    }
}

impl BrowserListenerStartDispatcher for SelectedSourceListenerDispatcher<'_> {
    fn dispatch(&mut self, permit: BrowserPreparedListenerStart<'_>) -> BrowserListenerDispatch {
        let prior = std::mem::replace(&mut self.state, SelectedSourceListenerState::Entered);
        let SelectedSourceListenerState::Prepared(runtime) = prior else {
            // This concrete owner never installs twice. Keep its actual first
            // outcome, including successful installation, on a repeated hook.
            self.state = prior;
            return BrowserListenerDispatch::Refused;
        };
        let actual = self.owner.install_listener(permit, runtime);
        let tag = match &actual {
            Ok(()) => BrowserListenerDispatch::Installed,
            Err(_) => BrowserListenerDispatch::Refused,
        };
        self.state = SelectedSourceListenerState::Completed(actual);
        tag
    }
}

#[cfg(target_os = "macos")]
struct SelectedSourcePrepaidStartFailure<'a> {
    launch: SelectedSourceLaunch<'a>,
    gate: Result<BrowserListenerDispatch, BrowserActionIssueError>,
    native: SelectedSourceListenerOutcome,
}

#[cfg(target_os = "macos")]
impl<'a> SelectedSourcePrepared<'a> {
    /// The caller moves the sole materialized listener allowance here only
    /// after retaining the actual physical controller. No fresh loan debit or
    /// runtime lookup is permitted at this transition.
    fn start_prepaid_listener(
        self,
        credit: morphir_mck::workbench::BrowserControllerBusinessCredit,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<SelectedSourceStarted<'a>, SelectedSourcePrepaidStartFailure<'a>> {
        let Self {
            mut launch,
            runtime,
        } = self;
        let mut dispatcher = SelectedSourceListenerDispatcher::new(&mut launch.owner, runtime);
        let gate = launch
            .opening
            .with_prepaid_listener_start(credit, loans, &mut dispatcher);
        let native = dispatcher.into_outcome();
        if matches!(gate, Ok(BrowserListenerDispatch::Installed))
            && matches!(native, SelectedSourceListenerOutcome::Completed(Ok(())))
        {
            Ok(SelectedSourceStarted {
                owner: launch.owner,
                opening: launch.opening,
            })
        } else {
            Err(SelectedSourcePrepaidStartFailure {
                launch,
                gate,
                native,
            })
        }
    }
}

impl SelectedSourceHost {
    fn active_native_first(
        state: &super::super::super::HostState,
    ) -> Result<
        std::sync::MutexGuard<'_, Option<super::super::super::ControlledHostFault>>,
        SelectedSourceStartFault,
    > {
        let first = match state.first.lock() {
            Ok(first) => first,
            Err(poison) => {
                let mut first = poison.into_inner();
                let cause =
                    *first.get_or_insert(super::super::super::ControlledHostFault::Poisoned);
                return Err(SelectedSourceStartFault::Native(cause));
            }
        };
        if let Some(cause) = *first {
            return Err(SelectedSourceStartFault::Native(cause));
        }
        Ok(first)
    }

    fn check_prepared_listener(&self, end: Instant) -> Result<(), SelectedSourceStartFault> {
        if self.application.end != end || self.host.state.end != end {
            return Err(SelectedSourceStartFault::OriginalEnd);
        }
        if Instant::now() >= end {
            return Err(SelectedSourceStartFault::Native(
                super::super::super::ControlledHostFault::End,
            ));
        }
        if !matches!(
            self.host.listener,
            super::super::super::ListenerOwner::Bound(_)
        ) {
            return Err(SelectedSourceStartFault::Native(
                super::super::super::ControlledHostFault::Listener,
            ));
        }
        Ok(())
    }

    /// Called only inside the genuine SDK's scoped listener gate. The permit
    /// carries no reusable authority. Do not call source/loan APIs here.
    fn install_listener(
        &mut self,
        permit: BrowserPreparedListenerStart<'_>,
        runtime: tokio::runtime::Handle,
    ) -> Result<(), SelectedSourceStartFault> {
        // Retain the actual first-fault guard through listener installation.
        // A copied `first()` result would allow a concurrent native refusal
        // between validation and the spawn effect. Lock order is the SDK's
        // parent/child and journal gates, then this native first-fault lock.
        let first = Self::active_native_first(&self.host.state)?;
        self.check_prepared_listener(permit.original_end())?;
        let super::super::super::ListenerOwner::Bound(future) = std::mem::replace(
            &mut self.host.listener,
            super::super::super::ListenerOwner::Unserved,
        ) else {
            unreachable!("exclusive owner checked inside the source gate")
        };
        self.host.listener = super::super::super::ListenerOwner::Running {
            actual: runtime.spawn(future),
            stop_requested: false,
        };
        drop(first);
        Ok(())
    }
}

impl<'a> SelectedSourceLaunch<'a> {
    /// Retain the concrete native runtime and transition storage before the
    /// physical controller sizes cleanup from the remaining capacity. This
    /// prepares ownership only; installation still needs a scoped source gate.
    fn prepare_native_runtime(
        self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<SelectedSourcePrepared<'a>, SelectedSourceStartFailure<'a>> {
        let result = (|| {
            // Source currentness precedes new requested storage. Native first
            // is checked under the final gate before any listener effect.
            self.opening
                .while_host_active(loans, || ())
                .map_err(SelectedSourceStartFault::Action)?;
            // Pay visible transition wrappers, runtime Handle retention and
            // JoinHandle installation before obtaining or moving that Handle.
            // Tokio's private allocator/runtime storage is not an RSS claim.
            let bytes = std::mem::size_of::<SelectedSourceStarted<'_>>()
                .checked_add(std::mem::size_of::<SelectedSourceStartFailure<'_>>())
                .and_then(|bytes| {
                    bytes.checked_add(std::mem::size_of::<SelectedSourcePrepared<'_>>())
                })
                .and_then(|bytes| {
                    bytes.checked_add(std::mem::size_of::<
                        tokio::task::JoinHandle<Result<(), CliError>>,
                    >())
                })
                .and_then(|bytes| bytes.checked_add(std::mem::size_of::<tokio::runtime::Handle>()))
                .and_then(|bytes| {
                    bytes.checked_add(std::mem::size_of::<SelectedSourceListenerDispatcher<'_>>())
                })
                .and_then(|bytes| {
                    bytes.checked_add(std::mem::size_of::<SelectedSourceListenerState>())
                })
                .and_then(|bytes| {
                    bytes.checked_add(std::mem::size_of::<SelectedSourceListenerOutcome>())
                })
                .ok_or(SelectedSourceStartFault::SizeOverflow)?;
            #[cfg(target_os = "macos")]
            let bytes = bytes
                .checked_add(std::mem::size_of::<SelectedSourcePrepaidStartFailure<'_>>())
                .and_then(|bytes| {
                    bytes.checked_add(std::mem::size_of::<SelectedSourceControllerPrepared<'_>>())
                })
                .and_then(|bytes| {
                    bytes.checked_add(std::mem::size_of::<
                        SelectedSourceControllerPreparationFailure<'_>,
                    >())
                })
                .and_then(|bytes| {
                    bytes.checked_add(std::mem::size_of::<SelectedSourceControllerLaunched<'_>>())
                })
                .and_then(|bytes| {
                    bytes.checked_add(
                        std::mem::size_of::<SelectedSourceControllerLaunchFailure<'_>>(),
                    )
                })
                .ok_or(SelectedSourceStartFault::SizeOverflow)?;
            let work = bytes
                .checked_add(std::mem::size_of::<super::super::super::ListenerOwner>())
                .and_then(|work| {
                    work.checked_add(std::mem::size_of::<
                        Option<super::super::super::ControlledHostFault>,
                    >())
                })
                .and_then(|work| work.checked_add(4 * std::mem::size_of::<Instant>()))
                .and_then(|work| {
                    work.checked_add(2 * std::mem::size_of::<tokio::runtime::Handle>())
                })
                .ok_or(SelectedSourceStartFault::SizeOverflow)?;
            let slots = if cfg!(target_os = "macos") { 13 } else { 9 };
            loans
                .reserve_controlled_host_storage(bytes, slots, work)
                .map_err(SelectedSourceStartFault::Funding)?;
            tokio::runtime::Handle::try_current().map_err(|_| {
                SelectedSourceStartFault::Native(super::super::super::ControlledHostFault::Listener)
            })
        })();
        match result {
            Ok(runtime) => Ok(SelectedSourcePrepared {
                launch: self,
                runtime,
            }),
            Err(fault) => Err(SelectedSourceStartFailure {
                fault,
                launch: self,
            }),
        }
    }

    /// Standalone component path. Composed execution instead uses the prepared
    /// context with its separately prepaid fixed listener allowance.
    fn start_listener(
        self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<SelectedSourceStarted<'a>, SelectedSourceStartFailure<'a>> {
        let SelectedSourcePrepared {
            mut launch,
            runtime,
        } = self.prepare_native_runtime(loans)?;
        let result = (|| {
            launch
                .opening
                .with_prepared_listener_start(loans, |permit| {
                    launch.owner.install_listener(permit, runtime)
                })
                .map_err(SelectedSourceStartFault::Action)?
        })();
        match result {
            Ok(()) => Ok(SelectedSourceStarted {
                owner: launch.owner,
                opening: launch.opening,
            }),
            Err(fault) => Err(SelectedSourceStartFailure { fault, launch }),
        }
    }
}

#[cfg(test)]
#[path = "execution_tests.rs"]
mod tests;

#[cfg(all(test, target_os = "macos"))]
#[path = "execution/composition_tests.rs"]
mod composition_tests;

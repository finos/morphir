//! Native listener transition under the genuine source0 SDK.
//! No controller reply, logical settlement or process join is synthesized here.
use super::*;
use morphir_mck::workbench::BrowserPreparedListenerStart;

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

impl SelectedSourceHost {
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
        let first = match self.host.state.first.lock() {
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
    fn start_listener(
        mut self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<SelectedSourceStarted<'a>, SelectedSourceStartFailure<'a>> {
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
                    bytes.checked_add(std::mem::size_of::<
                        tokio::task::JoinHandle<Result<(), CliError>>,
                    >())
                })
                .and_then(|bytes| bytes.checked_add(std::mem::size_of::<tokio::runtime::Handle>()))
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
            loans
                .reserve_controlled_host_storage(bytes, 4, work)
                .map_err(SelectedSourceStartFault::Funding)?;
            let runtime = tokio::runtime::Handle::try_current().map_err(|_| {
                SelectedSourceStartFault::Native(super::super::super::ControlledHostFault::Listener)
            })?;
            self.opening
                .with_prepared_listener_start(loans, |permit| {
                    self.owner.install_listener(permit, runtime)
                })
                .map_err(SelectedSourceStartFault::Action)?
        })();
        match result {
            Ok(()) => Ok(SelectedSourceStarted {
                owner: self.owner,
                opening: self.opening,
            }),
            Err(fault) => Err(SelectedSourceStartFailure {
                fault,
                launch: self,
            }),
        }
    }
}

#[cfg(test)]
#[path = "execution_tests.rs"]
mod tests;

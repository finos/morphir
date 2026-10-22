//! Consuming native host completion. Bookkeeping is not physical qualification.
use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum ControlledHostJoined {
    Clean,
    Fault(ControlledHostFault),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::commands::ui) enum ControlledHostFinishRefusal {
    Pending,
    SharedState,
    SharedSource,
    Retirement(morphir_mck::workbench::BrowserSourceFault),
}

pub(in crate::commands::ui) enum ControlledHostFinish {
    Joined(ControlledHostJoined),
    Retained {
        host: BoundControlledUiHost,
        shutdown: ControlledHostShutdown,
        reason: ControlledHostFinishRefusal,
    },
}

impl BoundControlledUiHost {
    /// Settle the actual listener and socket registry, then retire the exact
    /// source binding only with exclusive state and stimulus ownership.
    /// Strong or Weak external observers conservatively retain this SAME host.
    /// This outcome says nothing about driver, Chromium or product ownership.
    pub(in crate::commands::ui) async fn finish_joined(mut self) -> ControlledHostFinish {
        let shutdown = self.shutdown().await;
        let joined = match shutdown {
            ControlledHostShutdown::Joined => ControlledHostJoined::Clean,
            ControlledHostShutdown::JoinedWithFault(cause) => ControlledHostJoined::Fault(cause),
            ControlledHostShutdown::Pending { .. } => {
                return ControlledHostFinish::Retained {
                    host: self,
                    shutdown,
                    reason: ControlledHostFinishRefusal::Pending,
                };
            }
        };
        // No source relation is consumed until both proofs succeed. get_mut
        // rejects external Weak references as well as extra strong references.
        let refusal = match Arc::get_mut(&mut self.state) {
            None => Some(ControlledHostFinishRefusal::SharedState),
            Some(state) => match Arc::get_mut(&mut state.source) {
                None => Some(ControlledHostFinishRefusal::SharedSource),
                Some(stimulus) => stimulus
                    .retire_after_join_in_place()
                    .err()
                    .map(ControlledHostFinishRefusal::Retirement),
            },
        };
        match refusal {
            Some(reason) => ControlledHostFinish::Retained {
                host: self,
                shutdown,
                reason,
            },
            None => ControlledHostFinish::Joined(joined),
        }
    }
}

#[cfg(test)]
#[path = "joined/tests.rs"]
mod tests;

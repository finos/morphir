//! Revocable relation to one actual prepared source lifetime. This control
//! admits no source/action by itself and cannot attest physical joins.
use super::inputs::{BrowserInputFault, BrowserOwnerLoans};
use crate::workbench::model_originals::workflow::pipeline::installed::observation::{
    InstalledObservationFault, InstalledObservationResource,
};
use std::{
    alloc::Layout,
    sync::{Arc, Mutex, MutexGuard, Weak, atomic::AtomicUsize},
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScopeFault {
    Revoked,
    ForeignSource,
    Abandoned,
    Poisoned,
    SizeOverflow,
}
#[derive(Debug)]
pub(super) enum ScopeIssueFault {
    Input(BrowserInputFault),
    Scope(ScopeFault),
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScopeTerminal {
    Quiescent,
    Unfinished { bindings: usize },
    Incomplete { first: ScopeFault, bindings: usize },
}
enum State {
    Active {
        bindings: usize,
    },
    Revoked {
        bindings: usize,
        first: Option<ScopeFault>,
    },
}
impl State {
    fn revoke(&mut self, cause: Option<ScopeFault>) {
        *self = match *self {
            Self::Active { bindings } => Self::Revoked {
                bindings,
                first: cause,
            },
            Self::Revoked { bindings, first } => Self::Revoked {
                bindings,
                first: first.or(cause),
            },
        };
    }
    fn active(&self) -> Result<(), ScopeFault> {
        match self {
            Self::Active { .. } => Ok(()),
            Self::Revoked { first, .. } => Err(first.unwrap_or(ScopeFault::Revoked)),
        }
    }
    fn terminal(&self) -> ScopeTerminal {
        match *self {
            Self::Revoked {
                first: Some(first),
                bindings,
            } => ScopeTerminal::Incomplete { first, bindings },
            Self::Active { bindings: 0 } | Self::Revoked { bindings: 0, .. } => {
                ScopeTerminal::Quiescent
            }
            Self::Active { bindings } | Self::Revoked { bindings, .. } => {
                ScopeTerminal::Unfinished { bindings }
            }
        }
    }
}
struct Control {
    state: Mutex<State>,
}
impl Control {
    fn lock(&self) -> MutexGuard<'_, State> {
        match self.state.lock() {
            Ok(state) => state,
            Err(poison) => {
                let mut state = poison.into_inner();
                state.revoke(Some(ScopeFault::Poisoned));
                state
            }
        }
    }
}
pub(super) struct BrowserSourceScope {
    control: Arc<Control>,
}
/// Identity/liveness only. This creates no physical debt or effect permission.
pub(super) struct ApplicationSourceIdentity {
    control: Weak<Control>,
}
impl ApplicationSourceIdentity {
    pub(super) fn validate(&self, scope: &BrowserSourceScope) -> Result<(), ScopeFault> {
        if !Weak::ptr_eq(&self.control, &Arc::downgrade(&scope.control)) {
            return Err(ScopeFault::ForeignSource);
        }
        self.while_active(|| ())
    }
    pub(super) fn while_active<R>(&self, action: impl FnOnce() -> R) -> Result<R, ScopeFault> {
        let control = self.control.upgrade().ok_or(ScopeFault::Revoked)?;
        let state = control.lock();
        state.active()?;
        Ok(action())
    }
}
pub(super) struct BrowserSourceBinding {
    control: Option<Arc<Control>>,
}
impl BrowserSourceScope {
    pub(super) fn application_identity(&self) -> Result<ApplicationSourceIdentity, ScopeFault> {
        self.ready()?;
        Ok(ApplicationSourceIdentity {
            control: Arc::downgrade(&self.control),
        })
    }
    pub(super) fn prepare(loans: &mut BrowserOwnerLoans<'_>) -> Result<Self, BrowserInputFault> {
        let (decode, receiving, _) = loans.physical_owners()?;
        // Pinned alloc::sync::ArcInner is repr(C): strong, weak, data. This
        // accounts requested backing and this owner, not allocator/RSS overhead.
        let layout = (|| {
            let atomic = Layout::new::<AtomicUsize>();
            let header = atomic.extend(atomic).ok()?.0;
            let backing = header
                .extend(Layout::new::<Control>())
                .ok()?
                .0
                .pad_to_align();
            backing.size().checked_add(std::mem::size_of::<Self>())
        })();
        let Some(bytes) = layout else {
            return Err(BrowserInputFault::Receiving(
                *receiving.fail(InstalledObservationFault::SizeOverflow),
            ));
        };
        decode.slots(1).map_err(BrowserInputFault::Decode)?;
        receiving
            .reserve_span(InstalledObservationResource::RetainedBytes, bytes)
            .map_err(BrowserInputFault::Receiving)?;
        Ok(Self {
            control: Arc::new(Control {
                state: Mutex::new(State::Active { bindings: 0 }),
            }),
        })
    }
    pub(super) fn bind(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<BrowserSourceBinding, ScopeIssueFault> {
        let (decode, receiving, _) = loans.physical_owners().map_err(ScopeIssueFault::Input)?;
        self.control
            .lock()
            .active()
            .map_err(ScopeIssueFault::Scope)?;
        decode
            .slots(1)
            .map_err(|fault| ScopeIssueFault::Input(BrowserInputFault::Decode(fault)))?;
        receiving
            .reserve_span(
                InstalledObservationResource::RetainedBytes,
                std::mem::size_of::<BrowserSourceBinding>(),
            )
            .map_err(|fault| ScopeIssueFault::Input(BrowserInputFault::Receiving(fault)))?;
        let mut state = self.control.lock();
        state.active().map_err(ScopeIssueFault::Scope)?;
        let State::Active { bindings } = &mut *state else {
            unreachable!("checked under the same lock")
        };
        let Some(next) = bindings.checked_add(1) else {
            state.revoke(Some(ScopeFault::SizeOverflow));
            return Err(ScopeIssueFault::Scope(ScopeFault::SizeOverflow));
        };
        *bindings = next;
        Ok(BrowserSourceBinding {
            control: Some(Arc::clone(&self.control)),
        })
    }
    pub(super) fn revoke(&mut self) -> ScopeTerminal {
        let mut state = self.control.lock();
        state.revoke(None);
        state.terminal()
    }
    pub(super) fn terminal(&self) -> ScopeTerminal {
        self.control.lock().terminal()
    }
    pub(super) fn ready(&self) -> Result<(), ScopeFault> {
        self.control.lock().active()
    }
}
impl Drop for BrowserSourceScope {
    fn drop(&mut self) {
        self.control.lock().revoke(None);
    }
}
impl BrowserSourceBinding {
    pub(super) fn validate_scope(&self, scope: &BrowserSourceScope) -> Result<(), ScopeFault> {
        if Arc::ptr_eq(self.control.as_ref().expect("live binding"), &scope.control) {
            Ok(())
        } else {
            Err(ScopeFault::ForeignSource)
        }
    }
    /// Synchronous admission/send linearizes with revocation under this lock.
    /// No physical work may be scheduled by this callback after it returns.
    pub(super) fn while_active<R>(&self, action: impl FnOnce() -> R) -> Result<R, ScopeFault> {
        let control = self.control.as_ref().expect("live binding");
        let state = control.lock();
        state.active()?;
        Ok(action())
    }
    /// Bookkeeping only. The actual host caller must first settle every owner
    /// covered by this binding. Drop is deliberately not this operation.
    pub(super) fn retire_after_join(mut self) -> Result<(), ScopeFault> {
        let control = self.control.take().expect("consumed exactly once");
        let mut state = control.lock();
        let bindings = match &mut *state {
            State::Active { bindings } | State::Revoked { bindings, .. } => bindings,
        };
        let Some(next) = bindings.checked_sub(1) else {
            state.revoke(Some(ScopeFault::SizeOverflow));
            return Err(ScopeFault::SizeOverflow);
        };
        *bindings = next;
        Ok(())
    }
    #[cfg(test)]
    pub(super) fn identity(&self) -> usize {
        Arc::as_ptr(self.control.as_ref().expect("live binding")) as usize
    }
}
impl Drop for BrowserSourceBinding {
    fn drop(&mut self) {
        if let Some(control) = self.control.take() {
            control.lock().revoke(Some(ScopeFault::Abandoned));
        }
    }
}

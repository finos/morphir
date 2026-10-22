//! Revocable relation to one actual prepared source lifetime. This control
//! admits no source/action by itself and cannot attest physical joins.
#[path = "source_scope/invocation.rs"]
mod invocation;
#[cfg(test)]
#[path = "source_scope/tests.rs"]
mod tests;
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
// Pinned alloc::sync::ArcInner is repr(C): strong, weak, data. This is
// requested backing, including layout padding, not allocator/RSS overhead.
fn arc_backing_layout<T>() -> Option<Layout> {
    let atomic = Layout::new::<AtomicUsize>();
    atomic
        .extend(atomic)
        .ok()?
        .0
        .extend(Layout::new::<T>())
        .ok()
        .map(|(layout, _)| layout.pad_to_align())
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
        if self.control.as_ptr() != Arc::as_ptr(&scope.control) {
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
    control: Option<BindingControl>,
}
enum BindingControl {
    Global(Arc<Control>),
    Invocation {
        parent: Arc<Control>,
        child: Arc<InvocationControl>,
    },
}
struct InvocationControl {
    inner: Control,
}
/// Engine-owned child lifetime only; no physical-effect permission.
pub(super) struct BrowserInvocationScope {
    parent: Arc<Control>,
    control: Arc<InvocationControl>,
}
/// A nominal, funded relation to one exact parent and issued child.
pub(super) struct BrowserInvocationIdentity {
    parent: Weak<Control>,
    child: Weak<InvocationControl>,
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
        let layout = arc_backing_layout::<Control>()
            .and_then(|backing| backing.size().checked_add(std::mem::size_of::<Self>()));
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
            control: Some(BindingControl::Global(Arc::clone(&self.control))),
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
        match self.control.as_ref() {
            Some(BindingControl::Global(control)) if Arc::ptr_eq(control, &scope.control) => Ok(()),
            // An invocation cannot be downgraded into an application grant.
            Some(BindingControl::Global(_) | BindingControl::Invocation { .. }) => {
                Err(ScopeFault::ForeignSource)
            }
            None => Err(ScopeFault::Revoked),
        }
    }
    /// Synchronous admission/send linearizes with revocation under this lock.
    /// No physical work may be scheduled by this callback after it returns.
    pub(super) fn while_active<R>(&self, action: impl FnOnce() -> R) -> Result<R, ScopeFault> {
        match self.control.as_ref() {
            Some(BindingControl::Global(control)) => {
                let state = control.lock();
                state.active()?;
                Ok(action())
            }
            Some(BindingControl::Invocation { parent, child }) => {
                invocation::while_active(parent, child, action)
            }
            None => Err(ScopeFault::Revoked),
        }
    }
    /// Bookkeeping only, never proof of a physical join. The actual caller must
    /// first settle every covered owner. Drop is deliberately not this operation.
    pub(super) fn retire_after_join(mut self) -> Result<(), ScopeFault> {
        self.retire_after_join_in_place()
    }
    /// Native owners can retire in place after proving exclusive ownership.
    /// Keeping an inert wrapper permits safe field access during final Drop.
    pub(super) fn retire_after_join_in_place(&mut self) -> Result<(), ScopeFault> {
        let control = self.control.take().ok_or(ScopeFault::Revoked)?;
        let control = match control {
            BindingControl::Global(control) => control,
            BindingControl::Invocation { parent, child } => {
                return invocation::retire(&parent, &child);
            }
        };
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
        match self.control.as_ref().expect("live binding") {
            BindingControl::Global(control) => Arc::as_ptr(control) as usize,
            BindingControl::Invocation { child, .. } => Arc::as_ptr(child) as usize,
        }
    }
}
impl Drop for BrowserSourceBinding {
    fn drop(&mut self) {
        match self.control.take() {
            Some(BindingControl::Global(control)) => {
                control.lock().revoke(Some(ScopeFault::Abandoned))
            }
            Some(BindingControl::Invocation { parent, child }) => {
                invocation::abandon(&parent, &child)
            }
            None => (),
        }
    }
}

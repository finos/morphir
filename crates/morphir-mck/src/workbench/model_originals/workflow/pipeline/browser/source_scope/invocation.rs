//! Child lifetime/debt bookkeeping. This never establishes physical provenance.
use super::*;

fn reserve(
    loans: &mut BrowserOwnerLoans<'_>,
    bytes: usize,
    slots: usize,
    initialized: usize,
) -> Result<(), ScopeIssueFault> {
    let (decode, receiving, _) = loans.physical_owners().map_err(ScopeIssueFault::Input)?;
    decode
        .slots(slots)
        .map_err(|cause| ScopeIssueFault::Input(BrowserInputFault::Decode(cause)))?;
    receiving
        .reserve_span(InstalledObservationResource::RetainedBytes, bytes)
        .map_err(|cause| ScopeIssueFault::Input(BrowserInputFault::Receiving(cause)))?;
    // Source-visible initialization/counter writes, with possible layout
    // padding included. This is not total allocator/lock/runtime work.
    receiving
        .reserve_span(InstalledObservationResource::ByteVisits, initialized)
        .map_err(|cause| ScopeIssueFault::Input(BrowserInputFault::Receiving(cause)))
}
fn size_overflow(loans: &mut BrowserOwnerLoans<'_>) -> ScopeIssueFault {
    match loans.physical_owners() {
        Ok((_, receiving, _)) => ScopeIssueFault::Input(BrowserInputFault::Receiving(
            *receiving.fail(InstalledObservationFault::SizeOverflow),
        )),
        Err(cause) => ScopeIssueFault::Input(cause),
    }
}
fn count(state: &State) -> usize {
    match state {
        State::Active { bindings } | State::Revoked { bindings, .. } => *bindings,
    }
}
fn set_count(state: &mut State, count: usize) {
    match state {
        State::Active { bindings } | State::Revoked { bindings, .. } => *bindings = count,
    }
}
fn propagate_fault(parent: &mut State, child: &State) {
    if let State::Revoked {
        first: Some(cause), ..
    } = child
    {
        parent.revoke(Some(*cause));
    }
}
fn active(parent: &mut State, child: &State) -> Result<(), ScopeFault> {
    parent.active()?;
    propagate_fault(parent, child);
    parent.active()?;
    child.active()
}
pub(super) fn while_active<R>(
    parent: &Arc<Control>,
    child: &Arc<InvocationControl>,
    action: impl FnOnce() -> R,
) -> Result<R, ScopeFault> {
    let mut parent = parent.lock();
    let child = child.inner.lock();
    active(&mut parent, &child)?;
    // No nested parent/source callbacks and no await inside this synchronous gate.
    Ok(action())
}
impl BrowserSourceScope {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare_invocation(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<BrowserInvocationScope, ScopeIssueFault> {
        loans.ready().map_err(ScopeIssueFault::Input)?;
        self.ready().map_err(ScopeIssueFault::Scope)?;
        let bytes = arc_backing_layout::<InvocationControl>()
            .and_then(|layout| {
                layout
                    .size()
                    .checked_add(std::mem::size_of::<BrowserInvocationScope>())
            })
            .ok_or_else(|| size_overflow(loans))?;
        // One actual Arc control and its retained guard; both are funded before
        // allocation/initialization or retaining another strong parent relation.
        let initialized = bytes
            .checked_add(std::mem::size_of::<AtomicUsize>())
            .ok_or_else(|| size_overflow(loans))?;
        reserve(loans, bytes, 2, initialized)?;
        let parent = self.control.lock();
        parent.active().map_err(ScopeIssueFault::Scope)?;
        let control = Arc::new(InvocationControl {
            inner: Control {
                state: Mutex::new(State::Active { bindings: 0 }),
            },
        });
        Ok(BrowserInvocationScope {
            parent: Arc::clone(&self.control),
            control,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn with_invocation<R>(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
        action: impl FnOnce(&BrowserInvocationScope, &mut BrowserOwnerLoans<'_>) -> R,
    ) -> Result<(R, ScopeTerminal), ScopeIssueFault> {
        let mut child = self.prepare_invocation(loans)?;
        // No state lock is held across user work. Drop revokes during unwinding.
        let result = action(&child, loans);
        let terminal = child.revoke();
        Ok((result, terminal))
    }
}
impl BrowserInvocationScope {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_parent(
        &self,
        parent: &BrowserSourceScope,
    ) -> Result<(), ScopeFault> {
        if !Arc::ptr_eq(&self.parent, &parent.control) {
            return Err(ScopeFault::ForeignSource);
        }
        while_active(&self.parent, &self.control, || ())
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn identity(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<BrowserInvocationIdentity, ScopeIssueFault> {
        loans.ready().map_err(ScopeIssueFault::Input)?;
        while_active(&self.parent, &self.control, || ()).map_err(ScopeIssueFault::Scope)?;
        let bytes = std::mem::size_of::<BrowserInvocationIdentity>();
        let initialized = bytes
            .checked_add(2 * std::mem::size_of::<AtomicUsize>())
            .ok_or_else(|| size_overflow(loans))?;
        reserve(loans, bytes, 1, initialized)?;
        while_active(&self.parent, &self.control, || BrowserInvocationIdentity {
            parent: Arc::downgrade(&self.parent),
            child: Arc::downgrade(&self.control),
        })
        .map_err(ScopeIssueFault::Scope)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn bind(
        &self,
        loans: &mut BrowserOwnerLoans<'_>,
    ) -> Result<BrowserSourceBinding, ScopeIssueFault> {
        loans.ready().map_err(ScopeIssueFault::Input)?;
        while_active(&self.parent, &self.control, || ()).map_err(ScopeIssueFault::Scope)?;
        let bytes = std::mem::size_of::<BrowserSourceBinding>();
        let initialized = bytes
            .checked_add(2 * std::mem::size_of::<AtomicUsize>())
            .and_then(|bytes| bytes.checked_add(2 * std::mem::size_of::<usize>()))
            .ok_or_else(|| size_overflow(loans))?;
        reserve(loans, bytes, 1, initialized)?;
        let mut parent = self.parent.lock();
        let mut child = self.control.inner.lock();
        active(&mut parent, &child).map_err(ScopeIssueFault::Scope)?;
        match (count(&parent).checked_add(1), count(&child).checked_add(1)) {
            (Some(p), Some(c)) => {
                set_count(&mut parent, p);
                set_count(&mut child, c);
            }
            _ => {
                parent.revoke(Some(ScopeFault::SizeOverflow));
                child.revoke(Some(ScopeFault::SizeOverflow));
                return Err(ScopeIssueFault::Scope(ScopeFault::SizeOverflow));
            }
        }
        Ok(BrowserSourceBinding {
            control: Some(BindingControl::Invocation {
                parent: Arc::clone(&self.parent),
                child: Arc::clone(&self.control),
            }),
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn revoke(
        &mut self,
    ) -> ScopeTerminal {
        let mut parent = self.parent.lock();
        let mut child = self.control.inner.lock();
        child.revoke(None);
        propagate_fault(&mut parent, &child);
        child.terminal()
    }
    /// Engine-only synchronous cut: parent then child remain locked while the
    /// caller inspects retained journals, and revocation occurs before either
    /// source gate can reopen. Capture must not reenter source/loan operations.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn revoke_with_capture<
        R,
    >(
        &mut self,
        capture: impl FnOnce() -> R,
    ) -> (R, ScopeTerminal) {
        let mut parent = self.parent.lock();
        let mut child = self.control.inner.lock();
        // Preserve the original unwind without leaving an active child or
        // poisoning either source mutex merely because capture itself unwound.
        let captured = std::panic::catch_unwind(std::panic::AssertUnwindSafe(capture));
        child.revoke(None);
        propagate_fault(&mut parent, &child);
        let terminal = child.terminal();
        drop(child);
        drop(parent);
        match captured {
            Ok(captured) => (captured, terminal),
            Err(original) => std::panic::resume_unwind(original),
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn terminal(
        &self,
    ) -> ScopeTerminal {
        let mut parent = self.parent.lock();
        let child = self.control.inner.lock();
        propagate_fault(&mut parent, &child);
        child.terminal()
    }
}
impl Drop for BrowserInvocationScope {
    fn drop(&mut self) {
        self.revoke();
    }
}
impl BrowserInvocationIdentity {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate(
        &self,
        scope: &BrowserInvocationScope,
    ) -> Result<(), ScopeFault> {
        if self.parent.as_ptr() != Arc::as_ptr(&scope.parent)
            || self.child.as_ptr() != Arc::as_ptr(&scope.control)
        {
            return Err(ScopeFault::ForeignSource);
        }
        self.while_active(|| ())
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn while_active<R>(
        &self,
        action: impl FnOnce() -> R,
    ) -> Result<R, ScopeFault> {
        let parent = self.parent.upgrade().ok_or(ScopeFault::Revoked)?;
        let mut parent = parent.lock();
        parent.active()?;
        let child = self.child.upgrade().ok_or(ScopeFault::Revoked)?;
        let child = child.inner.lock();
        active(&mut parent, &child)?;
        Ok(action())
    }
}
impl BrowserSourceBinding {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate_invocation(
        &self,
        identity: &BrowserInvocationIdentity,
    ) -> Result<(), ScopeFault> {
        match self.control.as_ref() {
            Some(BindingControl::Invocation { parent, child })
                if Arc::as_ptr(parent) == identity.parent.as_ptr()
                    && Arc::as_ptr(child) == identity.child.as_ptr() =>
            {
                while_active(parent, child, || ())
            }
            Some(BindingControl::Global(_) | BindingControl::Invocation { .. }) => {
                Err(ScopeFault::ForeignSource)
            }
            None => Err(ScopeFault::Revoked),
        }
    }
}
pub(super) fn retire(
    parent: &Arc<Control>,
    child: &Arc<InvocationControl>,
) -> Result<(), ScopeFault> {
    let mut parent = parent.lock();
    let mut child = child.inner.lock();
    match (count(&parent).checked_sub(1), count(&child).checked_sub(1)) {
        (Some(p), Some(c)) => {
            set_count(&mut parent, p);
            set_count(&mut child, c);
            Ok(())
        }
        _ => {
            parent.revoke(Some(ScopeFault::SizeOverflow));
            child.revoke(Some(ScopeFault::SizeOverflow));
            parent.active()
        }
    }
}
pub(super) fn abandon(parent: &Arc<Control>, child: &Arc<InvocationControl>) {
    let mut parent = parent.lock();
    let mut child = child.inner.lock();
    parent.revoke(Some(ScopeFault::Abandoned));
    child.revoke(Some(ScopeFault::Abandoned));
}

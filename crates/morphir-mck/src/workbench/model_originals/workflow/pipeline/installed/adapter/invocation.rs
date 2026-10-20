//! Engine-issued lifecycle permission in the caller's existing owner allocation.
//! The weak projection neither retains source writers nor grants OS authority.
use std::sync::{Mutex, Weak};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InvocationObservationError {
    Revoked,
    ForeignInvocation,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum State {
    Dormant,
    Open,
    Revoked,
}
pub struct InvocationGate(Mutex<State>);
impl InvocationGate {
    pub fn dormant() -> Self {
        Self(Mutex::new(State::Dormant))
    }
    fn activate_with_registration(
        &self,
        register: impl FnOnce(),
    ) -> Result<(), InvocationObservationError> {
        let mut state = self
            .0
            .lock()
            .map_err(|_| InvocationObservationError::Revoked)?;
        if *state != State::Dormant {
            return Err(InvocationObservationError::Revoked);
        }
        // The callback-external revoker is registered before Open under this
        // SAME lock, but a foreign already-Open owner is never registered.
        register();
        *state = State::Open;
        Ok(())
    }
    pub fn while_open<T>(
        &self,
        action: impl FnOnce() -> T,
    ) -> Result<T, InvocationObservationError> {
        let state = self
            .0
            .lock()
            .map_err(|_| InvocationObservationError::Revoked)?;
        if *state != State::Open {
            return Err(InvocationObservationError::Revoked);
        }
        Ok(action())
    }
    fn revoke(&self) {
        *self.0.lock().unwrap_or_else(|poison| poison.into_inner()) = State::Revoked;
    }
}
pub trait InvocationGateSource: Send + Sync {
    fn invocation_gate(&self) -> &InvocationGate;
    fn wake_observers(&self);
}
pub struct InvocationObservation {
    source: Weak<dyn InvocationGateSource>,
}
impl InvocationObservation {
    pub fn check_active(&self) -> Result<(), InvocationObservationError> {
        self.source
            .upgrade()
            .ok_or(InvocationObservationError::Revoked)?
            .invocation_gate()
            .while_open(|| ())
    }
    pub fn check_source(
        &self,
        actual: &Weak<dyn InvocationGateSource>,
    ) -> Result<(), InvocationObservationError> {
        if !Weak::ptr_eq(&self.source, actual) {
            return Err(InvocationObservationError::ForeignInvocation);
        }
        self.check_active()
    }
    #[cfg(test)]
    pub(super) fn test_view(&self) -> InvocationObservationView {
        InvocationObservationView(self.source.clone())
    }
}
#[derive(Default)]
pub(in crate::workbench::model_originals::workflow::pipeline::installed) struct InvocationRevoker {
    source: Option<Weak<dyn InvocationGateSource>>,
}
impl InvocationRevoker {
    pub(super) fn issue(
        &mut self,
        source: Weak<dyn InvocationGateSource>,
    ) -> Result<InvocationObservation, InvocationObservationError> {
        if self.source.is_some() {
            return Err(InvocationObservationError::Revoked);
        }
        let owner = source
            .upgrade()
            .ok_or(InvocationObservationError::Revoked)?;
        owner
            .invocation_gate()
            .activate_with_registration(|| self.source = Some(source.clone()))?;
        Ok(InvocationObservation { source })
    }
    pub(super) fn matches(&self, source: &Weak<dyn InvocationGateSource>) -> bool {
        self.source
            .as_ref()
            .is_some_and(|own| Weak::ptr_eq(own, source))
            && source
                .upgrade()
                .is_some_and(|owner| owner.invocation_gate().while_open(|| ()).is_ok())
    }
}
impl Drop for InvocationRevoker {
    fn drop(&mut self) {
        if let Some(owner) = self.source.as_ref().and_then(Weak::upgrade) {
            owner.invocation_gate().revoke();
            owner.wake_observers();
        }
    }
}
#[cfg(test)]
#[derive(Debug, PartialEq, Eq)]
pub(super) enum InvocationObservationState {
    Open,
    Revoked,
}
#[cfg(test)]
pub(super) struct InvocationObservationView(Weak<dyn InvocationGateSource>);
#[cfg(test)]
impl InvocationObservationView {
    pub(super) fn state(&self) -> InvocationObservationState {
        if self
            .0
            .upgrade()
            .is_some_and(|owner| owner.invocation_gate().while_open(|| ()).is_ok())
        {
            InvocationObservationState::Open
        } else {
            InvocationObservationState::Revoked
        }
    }
}

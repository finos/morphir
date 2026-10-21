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
pub(in crate::workbench::model_originals::workflow::pipeline::installed) struct InvocationRevoker {
    source: Option<Weak<dyn InvocationGateSource>>,
    pub(super) consumer_selection: crate::workbench::configuration::ConsumerObservationSelection,
    pub(super) consumer_window: ConsumerWindow,
    #[cfg(target_os = "macos")]
    pub(super) consumer_ports: ConsumerRegistration,
}
pub(super) enum ConsumerWindow {
    Unbound,
    Bound(std::time::Instant),
    Revoked,
}
#[cfg(target_os = "macos")]
pub(super) enum ConsumerRegistration {
    Unprepared,
    Registered(Weak<super::processes::consumer::ConsumerPortControl>),
}
impl Default for InvocationRevoker {
    fn default() -> Self {
        Self::new(crate::workbench::configuration::ConsumerObservationSelection::Disabled)
    }
}
impl InvocationRevoker {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed) fn new(
        consumer_selection: crate::workbench::configuration::ConsumerObservationSelection,
    ) -> Self {
        Self {
            source: None,
            consumer_selection,
            consumer_window: ConsumerWindow::Unbound,
            #[cfg(target_os = "macos")]
            consumer_ports: ConsumerRegistration::Unprepared,
        }
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed) fn consumer_fault(
        &self,
    ) -> bool {
        #[cfg(target_os = "macos")]
        if let ConsumerRegistration::Registered(control) = &self.consumer_ports {
            return control.upgrade().is_none_or(|control| control.revoked());
        }
        false
    }
    #[cfg(target_os = "macos")]
    pub(super) fn register_consumer(
        &mut self,
        control: Weak<super::processes::consumer::ConsumerPortControl>,
    ) -> Result<(), InvocationObservationError> {
        if !matches!(self.consumer_ports, ConsumerRegistration::Unprepared) {
            return Err(InvocationObservationError::Revoked);
        }
        let owner = self
            .source
            .as_ref()
            .and_then(Weak::upgrade)
            .ok_or(InvocationObservationError::Revoked)?;
        owner.invocation_gate().while_open(|| {
            self.consumer_ports = ConsumerRegistration::Registered(control);
        })
    }
    pub(super) fn active(&self) -> bool {
        self.source
            .as_ref()
            .is_some_and(|source| self.matches(source))
    }
    pub(super) fn projection(&self) -> Option<Weak<dyn InvocationGateSource>> {
        self.source.clone()
    }
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
        self.consumer_window = ConsumerWindow::Revoked;
        if let Some(owner) = self.source.as_ref().and_then(Weak::upgrade) {
            owner.invocation_gate().revoke();
            owner.wake_observers();
        }
        #[cfg(target_os = "macos")]
        if let ConsumerRegistration::Registered(control) = &self.consumer_ports
            && let Some(control) = control.upgrade()
        {
            control.revoke();
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

///|
/// Declaration admission events carry no provider payload or authority.
pub(all) enum ProviderSignal {
  Started
  Succeeded
  Refused(String)
  Cancelled
} derive(Eq, Debug)

///|
/// Notification failures are contained. Observations cannot change admission.
pub(all) struct ProviderObserver {
  notify : (ProviderSignal) -> Unit raise
}

///|
pub fn ProviderObserver::noop() -> ProviderObserver {
  { notify: fn(_) { () }, }
}

///|
fn ProviderObserver::emit(
  self : ProviderObserver,
  signal : ProviderSignal,
) -> Unit {
  (self.notify)(signal) catch {
    _ => ()
  }
}

///|
fn observed_provider(
  predicate : String,
  restored : RestoredLibrary,
  capabilities : Capabilities,
) -> String raise {
  let observer = capabilities.provider_observer
  observer.emit(Started)
  let result = validate_provider(predicate, restored, capabilities) catch {
    error => {
      let code = match error {
        Invalid(code, _, _) => code
        _ => "metadata.admission_failed"
      }
      observer.emit(
        if code == "metadata.restore_cancelled" {
          Cancelled
        } else {
          Refused(code)
        },
      )
      raise error
    }
  }
  observer.emit(Succeeded)
  result
}

///|
/// Declaration admission events carry no provider payload or authority.
pub(all) enum ProviderSignal {
  Started
  Succeeded
  Refused(String)
  Cancelled
} derive(Eq, Debug)

///|
pub extend ProviderSignal with Eq::{equal, not_equal}

///|
pub extend ProviderSignal with @debug.Debug::{to_repr}

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
  let attempt = Ok(validate_provider(predicate, restored, capabilities)) catch {
    error => Err(error)
  }
  let result = match attempt {
    Ok(value) => value
    Err(error) => {
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

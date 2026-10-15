///|
/// An explicitly granted session owns its resources until disposal. Acquisition
/// must clean up partial resources itself if it raises before returning a session.
/// This host contract does not implement authentication or process transport.
pub(all) struct MetadataSession {
  capabilities : @linked_metadata.Capabilities
  dispose : () -> Unit raise
}

///|
priv enum MetadataSessionState {
  Idle
  Executing(Array[() -> Unit raise])
  Disposing
  CleanupFailed(String, Array[() -> Unit raise])
}

///|
/// Opaque host-owned lifecycle state. Failed cleanup retains its callbacks and
/// refuses further execution until an explicit cleanup retry succeeds.
pub struct MetadataSessions {
  priv mut state : MetadataSessionState
}

///|
priv enum MetadataSessionSlotState {
  Empty
  Acquiring
  Acquired(MetadataSession)
}

///|
priv struct MetadataSessionSlot {
  mut state : MetadataSessionSlotState
}

///|
priv enum MetadataDisposal {
  FinishExecution
  RetryCleanup
}

///|
fn MetadataSessions::new() -> MetadataSessions {
  { state: Idle, }
}

///|
fn MetadataSessions::begin(self : MetadataSessions) -> Unit raise {
  match self.state {
    Idle => self.state = Executing([])
    CleanupFailed(message, _) => raise @config.Invalid(message)
    Executing(_) | Disposing =>
      raise @config.Invalid(
        "metadata.restore_session_active: Host execution is already active",
      )
  }
}

///|
fn MetadataSessions::acquire(
  self : MetadataSessions,
  slot : MetadataSessionSlot,
  scope : @engine.ProjectMetadataScope,
  acquire : (@engine.ProjectMetadataScope) -> MetadataSession raise,
) -> MetadataSession raise {
  guard self.state is Executing(cleanups) else {
    raise @linked_metadata.Invalid(
      "metadata.restore_session_required",
      scope.project_root,
      "Execute this capability through its owning host",
    )
  }
  match slot.state {
    Acquired(session) => return session
    Acquiring =>
      raise @linked_metadata.Invalid(
        "metadata.restore_session_active",
        scope.project_root,
        "Recursive session acquisition is unavailable",
      )
    Empty => ()
  }
  slot.state = Acquiring
  let session = {
    errdefer {
      slot.state = Empty
    }
    acquire(scope) catch {
      @linked_metadata.Invalid(_, _, _) as error => raise error
      error =>
        raise @linked_metadata.Invalid(
          "metadata.restore_acquisition_failed",
          scope.project_root,
          error_message(error),
        )
    }
  }
  slot.state = Acquired(session)
  cleanups.push(fn() raise {
    // Revoke capability access even when disposal fails. Keep the cleanup
    // callback itself in the failed owner so it can be retried explicitly.
    slot.state = Empty
    (session.dispose)()
  })
  session
}

///|
fn MetadataSessions::dispose(
  self : MetadataSessions,
  operation : MetadataDisposal,
) -> String? raise {
  let cleanups = match self.state {
    Idle => return None
    Executing(cleanups) if operation is FinishExecution => cleanups
    CleanupFailed(_, cleanups) if operation is RetryCleanup => cleanups
    _ =>
      raise @config.Invalid(
        "metadata.restore_session_active: Cannot retry cleanup during execution",
      )
  }
  self.state = Disposing
  let failed = []
  let errors : Array[String] = []
  for i = cleanups.length() - 1; i >= 0; i = i - 1 {
    let cleanup = cleanups[i]
    cleanup() catch {
      error => {
        failed.push(cleanup)
        errors.push(error_message(error))
      }
    }
  }
  if errors.is_empty() {
    self.state = Idle
    None
  } else {
    let message = "metadata.restore_cleanup_failed: " + errors.join("; ")
    // Retain acquisition order: every disposal pass traverses it in reverse.
    self.state = CleanupFailed(message, failed.rev())
    Some(message)
  }
}

///|
/// Bind project-specific capabilities without acquiring resources during
/// planning. The supplied acquisition callback runs lazily during run_content.
/// Its session is reused only within that execution and disposed before any
/// output publication. The callback must enforce its own explicit host grants.
/// Static engine capabilities and this binder remain mutually exclusive.
pub fn Host::register_project_metadata_provider(
  self : Host,
  engine : @engine.Engine,
  acquire : (@engine.ProjectMetadataScope) -> MetadataSession raise,
) -> Unit raise {
  engine.register_project_metadata_provider(scope => {
    self.metadata_capabilities(scope, acquire)
  })
}

///|
fn Host::metadata_capabilities(
  self : Host,
  scope : @engine.ProjectMetadataScope,
  acquire : (@engine.ProjectMetadataScope) -> MetadataSession raise,
) -> @linked_metadata.Capabilities {
  let slot = MetadataSessionSlot::{ state: Empty, }
  let sessions = self.metadata_sessions
  {
    restore_library: Some(fn(predicate) raise {
      let capabilities = sessions.acquire(slot, scope, acquire).capabilities
      guard capabilities.restore_library is Some(restore) else {
        raise @linked_metadata.Invalid(
          "metadata.provider_unavailable", predicate, "The scoped session does not provide authenticated restoration",
        )
      }
      if !capabilities.target_names_interpreter {
        raise @linked_metadata.Invalid(
          "metadata.required_interpreter_unavailable", predicate, "The scoped session does not grant the target-name interpreter",
        )
      }
      restore(predicate)
    }),
    load_context: Some(fn(url, base) raise {
      let capabilities = sessions.acquire(slot, scope, acquire).capabilities
      guard capabilities.load_context is Some(load) else {
        raise @linked_metadata.Invalid(
          "metadata.context_resource_unavailable", url, "The scoped session does not provide this context",
        )
      }
      load(url, base)
    }),
    target_names_interpreter: true,
  }
}

///|
/// A CLI selection of none does not request a service. Explicit embedding
/// capabilities keep their separate authority through the general binder.
fn Host::register_requested_metadata_provider(
  self : Host,
  engine : @engine.Engine,
  acquire : (@engine.ProjectMetadataScope) -> MetadataSession raise,
) -> Unit raise {
  engine.register_project_metadata_provider(scope => {
    if scope.request is Disabled {
      @linked_metadata.Capabilities::unavailable()
    } else {
      self.metadata_capabilities(scope, acquire)
    }
  })
}

///|
/// Retry only callbacks retained after failed cleanup. This never restores a
/// provider or permits a concurrent retry during an active host execution.
pub fn Host::dispose_metadata_sessions(self : Host) -> Unit raise {
  if self.metadata_sessions.dispose(RetryCleanup) is Some(message) {
    raise @config.Invalid(message)
  }
}

///|
/// Preserve the effect-free binder on pure targets without linking process or
/// filesystem adapters. No provider or weaker profile is acquired as a fallback.
#cfg(any(target="wasm", target="wasm-gc"))
pub fn Host::register_process_metadata_provider(
  self : Host,
  engine : @engine.Engine,
  grants : @metadata_grants.Grants?,
  workspace_root : String,
  invocation_root : String,
  timeout~ : Int32 = 120000,
  cancel_file~ : String = "",
  observer~ : @observe.Observer = @observe.Observer::noop(),
  audit_sink~ : MetadataAuditSink = MetadataAuditSink::noop(),
) -> Unit raise {
  ignore((workspace_root, invocation_root, cancel_file, observer, audit_sink))
  if timeout < 6001 || timeout > 600000 {
    raise @config.Invalid("metadata.restore_invalid_deadline")
  }
  self.register_requested_metadata_provider(engine, fn(scope) raise {
    if grants is None {
      raise @linked_metadata.Invalid(
        "metadata.restore_host_grants_required",
        scope.project_root,
        "Select an explicit --metadata-grants file",
      )
    }
    raise @linked_metadata.Invalid(
      "metadata.restore_runtime_unavailable",
      scope.project_root,
      "Use a qualified native or Node JS host; this runtime has no qualified process pin adapter",
    )
  })
}

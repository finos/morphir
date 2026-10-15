///|
fn an_audit_record() -> MetadataAuditRecord {
  {
    run_id: "run",
    operation: "operation",
    project: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    phase: Restore,
    signal: @observe.Succeeded,
    code: "",
    evidence: Some({
      service: "morphir-package/provider-snapshot/0.1.0-draft.1",
      service_sha256: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      service_verified: true,
      release: "example.com/morphir/naming@1.0.0",
      native_revision: Some(
        "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      ),
      profile: "local-library-mvp",
      profile_version: "0.1.0-draft.1",
      assurance: "portable",
      profile_verified: true,
    }),
    wall_seconds: 1.0,
    duration_seconds: 0.25,
  }
}

///|
test "audit evidence is typed bounded and separate from ordinary metric dimensions" {
  let session = TelemetrySession::{
    sequence: Ref(0),
    metrics: Map([]),
    dimensions: Map([]),
    metrics_overflow: 0,
    records: [],
    audit_records: [],
    path: Some("unused"),
    local_root: None,
    format: "ion-binary",
    record_traces: true,
    run_id: "run",
    next: 0,
    dropped: 0,
    closed: false,
  }
  let sink = session.metadata_audit_sink()
  let record = an_audit_record()
  assert_true(record.valid())
  assert_false({ ..record, code: "secret body /private/path", }.valid())
  assert_false({ ..record, project: "private-path", }.valid())
  assert_false({ ..record, duration_seconds: -1.0, }.valid())
  assert_true((sink.try_record)({ ..record, evidence: None, }) is Accepted)
  for _ in 0..<255 {
    assert_true((sink.try_record)(record) is Accepted)
  }
  assert_true((sink.try_record)(record) is Dropped)
  assert_eq(session.audit_records.length(), 256)
  assert_eq(session.metrics.length(), 0)
  assert_eq(session.dimensions.length(), 0)
  assert_true(
    (sink.try_record)({ ..record, code: "secret body /private/path", })
    is Dropped,
  )
  assert_eq(session.dropped, 2)
  session.closed = true
  assert_true((sink.try_record)(record) is Unavailable)
}

///|
test "audit failures cannot replace original refusal or fabricate verification evidence" {
  let captured : Array[MetadataAuditRecord] = []
  let time = Ref(1.0)
  let context = MetadataAuditContext::{
    operation: "op",
    project: an_audit_record().project,
    evidence: None,
    sink: {
      enabled: fn() { true },
      try_record: fn(record) {
        captured.push(record)
        @observe.Accepted
      },
      monotonic: fn() {
        time.val += 0.1
        time.val
      },
      wall: fn() { 1.0 },
      run_id: "run",
    },
  }
  let message = try {
    context.observe(Acquire, fn() raise {
      raise @config.Invalid(
        "metadata.restore_host_grants_required: private repair",
      )
    })
    "wrong"
  } catch {
    error => error_message(error)
  }
  assert_eq(message, "metadata.restore_host_grants_required: private repair")
  assert_eq(captured.length(), 2)
  assert_true(captured.all(r => r.evidence is None))
  assert_eq(captured[1].code, "metadata.restore_host_grants_required")
  assert_true(captured[1].signal is Failed)
  assert_true(captured[1].duration_seconds > 0.0)
  let broken = {
    ..context,
    sink: {
      ..context.sink,
      try_record: fn(_) raise { fail("audit sink failure") },
    },
  }
  assert_eq(broken.observe(Decode, fn() { 42 }), 42)
  assert_eq(context.observe(Decode, fn() { 42 }), 42)
  captured.clear()
  context.observe(Restore, fn() raise { raise @protocol.Invalid("Cancelled") }) catch {
    _ => ()
  }
  assert_true(captured[1].signal is Cancelled)
  assert_eq(captured[1].code, "metadata.restore_cancelled")
}

///|
test "forwarded admission notifications cannot acquire or revive a host session" {
  let host = Host::new(Mount::memory(Map([])))
  let count = Ref(0)
  let notifications = Ref(0)
  let capabilities = host.metadata_capabilities(
    {
      workspace_root: "",
      project_root: "one",
      project_name: "one",
      request: @config.Disabled,
    },
    fn(_) {
      count.val += 1
      {
        capabilities: {
          ..@linked_metadata.Capabilities::unavailable(),
          target_names_interpreter: true,
          restore_library: Some(fn(_) raise {
            raise @config.Invalid("test.restore")
          }),
          provider_observer: { notify: fn(_) { notifications.val += 1 }, },
        },
        dispose: fn() { () },
      }
    },
  )
  (capabilities.provider_observer.notify)(@linked_metadata.Started)
  assert_eq(count.val, 0)
  assert_eq(notifications.val, 0)
  host.metadata_sessions.begin()
  ignore(capabilities.restore_library.unwrap()("predicate")) catch {
    _ => ()
  }
  (capabilities.provider_observer.notify)(@linked_metadata.Started)
  assert_eq(count.val, 1)
  assert_eq(notifications.val, 1)
  assert_true(host.metadata_sessions.dispose(FinishExecution) is None)
  (capabilities.provider_observer.notify)(@linked_metadata.Succeeded)
  assert_eq(count.val, 1)
  assert_eq(notifications.val, 1)
}

///|
#cfg(any(target="js", target="native"))
test "default binary Ion and explicit formats retain audit records without semantic payloads" {
  let root = @platform.temporary()
  defer telemetry_remove(root)
  let disabled = TelemetrySession::local(root, None)
  assert_true(
    (disabled.metadata_audit_sink().try_record)(an_audit_record()) is Filtered,
  )
  disabled.flush()
  assert_eq(@platform.kind(root + "/.morphir"), 0)
  let session = TelemetrySession::local(
    root,
    None,
    enabled=true,
    kind="frontend",
  )
  let record = an_audit_record()
  assert_true((session.metadata_audit_sink().try_record)(record) is Accepted)
  let unknown = { ..record, evidence: None, }
  let selected = {
    ..record,
    evidence: record.evidence.map(e => {
      ..e,
      native_revision: None,
      service_verified: false,
      profile_verified: false,
    }),
  }
  assert_true((session.metadata_audit_sink().try_record)(unknown) is Accepted)
  assert_true((session.metadata_audit_sink().try_record)(selected) is Accepted)
  session.flush()
  let values = @ion_binary.read_binary(
    @platform.read_bytes(root + "/.morphir/logs/frontend.ionb"),
  )
  assert_eq(values.length(), 4)
  assert_true(values[0].has_annotations())
  assert_true(values[0].equals(record.to_ion()))
  assert_true(values[1].equals(unknown.to_ion()))
  assert_true(values[2].equals(selected.to_ion()))
  assert_true(session.audit_records.is_empty())
  for
    (format, file) in [
      ("ion-text", "outside.ion"),
      ("json-lines", "outside.jsonl"),
      ("text", "outside.log"),
    ] {
    let path = root + "/" + file
    let explicit = TelemetrySession::local(
      root + "/other",
      Some(path),
      enabled=true,
      format~,
    )
    ignore((explicit.metadata_audit_sink().try_record)(record))
    explicit.flush()
    let text = @platform.read(path)
    assert_true(text.contains("morphir-metadata-invocation-v1"))
    assert_true(text.contains("native_revision"))
    assert_false(text.contains("policy"))
  }
}

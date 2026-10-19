///|
test "bounded telemetry queue counts dropped records while aggregating all stage completions" {
  let session = TelemetrySession::{
    sequence: Ref(0),
    metrics: Map([]),
    dimensions: Map([]),
    metrics_overflow: 0,
    records: [],
    audit_records: [],
    local_root: None,
    path: Some("unused"),
    format: "ion-binary",
    record_traces: true,
    run_id: "test",
    next: 0,
    dropped: 0,
    closed: false,
  }
  // The default WasmGC test runner has no embedding ABI. Supply clocks for
  // these pure queue/metric tests instead of retaining the platform imports.
  let observer = session.observer_with_clocks(fn() { 1.0 }, fn() { 2.0 })
  assert_eq((observer.monotonic)(), 1.0)
  assert_eq((observer.wall)(), 2.0)
  let event : @observe.Observation = {
    context: {
      run_id: "test",
      span_id: "1",
      parent_id: "",
      trace_id: "11111111111111111111111111111111",
    },
    details: None,
    correlation: None,
    sequence: 1,
    stage: @observe.Invoke,
    signal: @observe.Succeeded,
    wall_seconds: 1.0,
    duration_seconds: 0.05,
  }
  for i = 0; i < 2050; i = i + 1 {
    ignore((observer.try_record)(event))
  }
  assert_eq(session.records.length(), 2048)
  assert_eq(session.dropped, 2)
  let (count, duration, buckets) = session.metrics["invoke"]
  assert_eq(count, 2050)
  assert_true(duration > 102.49 && duration < 102.51)
  assert_eq(buckets, [0, 0, 2050, 0, 0, 0, 0])
  session.closed = true
  assert_true((observer.try_record)(event) is Unavailable)
}

///|
test "metric descriptors bound cardinality and account for series overflow without call identities" {
  let session = TelemetrySession::{
    sequence: Ref(0),
    metrics: Map([]),
    dimensions: Map([]),
    metrics_overflow: 0,
    records: [],
    audit_records: [],
    local_root: None,
    path: Some("unused"),
    format: "ion-binary",
    record_traces: true,
    run_id: "test",
    next: 0,
    dropped: 0,
    closed: false,
  }
  let observer = session.observer_with_clocks(fn() { 1.0 }, fn() { 2.0 })
  let mut emitted = 0
  for
    stage in [
      @observe.Plan,
      Decode,
      Generate,
      Build,
      Invoke,
      Call,
      Evaluate,
      Compare,
      Cleanup,
      Execute,
      Legacy,
    ] {
    for target in ["js", "wasm-gc", "native", "llvm", "arbitrary-target"] {
      for signal in [@observe.Succeeded, Failed, Cancelled] {
        emitted += 1
        ignore(
          (observer.try_record)({
            context: {
              run_id: "private-run",
              span_id: "private-span",
              parent_id: "private-parent",
              trace_id: "11111111111111111111111111111111",
            },
            details: Some({ entry: "private-entry", code: "execution.ok", }),
            correlation: Some({
              target,
              lease_id: "private-lease",
              call_id: "private-call-" + emitted.to_string(),
              attempt_id: "private-attempt",
            }),
            sequence: emitted,
            stage,
            signal,
            wall_seconds: 1.0,
            duration_seconds: 0.01,
          }),
        )
      }
    }
  }
  assert_eq(session.dimensions.length(), 128)
  assert_eq(session.metrics_overflow, emitted - 128)
  let metrics = session.metrics().stringify()
  assert_false(metrics.contains("private-"))
  assert_false(metrics.contains("arbitrary-target"))
  assert_true(metrics.contains("other"))
  session.closed = true
}

///|
#cfg(any(target="js", target="native"))
test "process exporter preserves queued Ion timestamps and IDs with idempotent shutdown" {
  let root = @platform.temporary()
  defer telemetry_remove(root)
  let session = TelemetrySession::new(Some("unused"))
  let observer = session.observer()
  ignore(observer.scope().observe(@observe.Build, fn(_) { 42 }))
  let expected = @ion_binary.write_binary(
    session.records.map(r => r.to_ion()) + [session.metrics_ion()],
  )
  let output = root + "/received.ionb"
  let exporter = root + "/export.cjs"
  @platform.write(
    exporter, "const fs=require('fs'),data=[];process.stdin.on('data',b=>data.push(b));process.stdin.on('end',()=>setTimeout(()=>fs.writeFileSync(process.argv[2],Buffer.concat(data)),10));",
  )
  session.flush_to_process("node", telemetry_helper(), "node", [
    exporter, output,
  ])
  assert_eq(@platform.read_bytes(output), expected)
  assert_true(session.closed)
  assert_true(session.records.is_empty())
  assert_eq(session.dropped, 0)
  assert_eq(session.metrics["build"].0, 1)
  session.flush_to_process("node", telemetry_helper(), "unavailable", [])
  assert_eq(session.dropped, 0)
  assert_eq(@platform.read_bytes(output), expected)
}

///|
#cfg(any(target="js", target="native"))
test "default local logs create directories only at flush and explicit paths take precedence" {
  let root = @platform.temporary()
  defer telemetry_remove(root)
  let disabled = TelemetrySession::local(root, None)
  assert_true(disabled.path is None)
  disabled.flush()
  assert_eq(@platform.kind(root + "/.morphir"), 0)
  let session = TelemetrySession::local(
    root,
    None,
    enabled=true,
    kind="frontend",
  )
  assert_eq(session.path, Some(root + "/.morphir/logs/frontend.ionb"))
  assert_eq(@platform.kind(root + "/.morphir"), 0)
  ignore(session.observer().scope().observe(@observe.Frontend, fn(_) { 42 }))
  session.flush()
  let saved = @platform.read_bytes(session.path.unwrap())
  assert_true(saved.length() > 4)
  assert_eq(saved[:4].to_owned(), b"\xe0\x01\x00\xea")
  let explicit = root + "/explicit.jsonl"
  let overridden = TelemetrySession::local(
    root,
    Some(explicit),
    enabled=true,
    format="json-lines",
  )
  assert_eq(overridden.path, Some(explicit))
  assert_true(overridden.local_root is None)
  ignore(overridden.observer().scope().observe(@observe.Frontend, fn(_) { 43 }))
  overridden.flush()
  assert_true(@platform.read(explicit).contains("frontend"))
  assert_eq(@platform.read_bytes(session.path.unwrap()), saved)
}

///|
#cfg(any(target="js", target="native"))
test "failed default log directory does not change results" {
  let root = @platform.temporary()
  defer telemetry_remove(root)
  @platform.write(root + "/.morphir", "existing file")
  let session = TelemetrySession::local(root, None, enabled=true)
  let result = session.observer().scope().observe(@observe.Build, fn(_) { 42 })
  session.flush()
  assert_eq(result, 42)
  assert_eq(session.dropped, 2)
  assert_eq(@platform.read(root + "/.morphir"), "existing file")
}

///|
#cfg(any(target="js", target="native"))
test "failed hanging and cancelled async drains count undelivered records and preserve results" {
  let root = @platform.temporary()
  defer telemetry_remove(root)
  for mode in ["failure", "hang", "cancel"] {
    let marker = root + "/cancel-" + mode
    let exporter = root + "/" + mode + ".cjs"
    @platform.write(
      exporter,
      match mode {
        "failure" => "process.exitCode=1;process.stdin.resume()"
        "cancel" =>
          "process.stdin.resume();require('fs').writeFileSync(process.argv[2],'');setInterval(()=>{},1000)"
        _ => "process.stdin.resume();setInterval(()=>{},1000)"
      },
    )
    let session = TelemetrySession::new(Some("unused"))
    let observer = session.observer()
    let result = observer.scope().observe(@observe.Invoke, fn(_) { 42 })
    let start = @platform.monotonic_seconds()
    session.flush_to_process(
      "node",
      telemetry_helper(),
      "node",
      [exporter, marker],
      timeout=300,
      cancel_file=marker,
    )
    assert_true(@platform.monotonic_seconds() - start < 2.0)
    assert_eq(result, 42)
    assert_eq(session.dropped, 2)
    assert_true(session.records.is_empty())
    assert_eq(session.metrics["invoke"].0, 1)
    if mode == "cancel" {
      assert_eq(@platform.kind(marker), 1)
    }
    session.flush()
    session.flush_to_process("node", telemetry_helper(), "node", [exporter])
    assert_eq(session.dropped, 2)
  }
}

///|
#cfg(any(target="js", target="native"))
fn telemetry_helper() -> String raise {
  let mut cursor = @platform.cwd()
  for depth = 0; depth < 16; depth = depth + 1 {
    let path = cursor + "/apps/morphir/build-provider/telemetry.mjs"
    if @platform.kind(path) == 1 {
      return path
    }
    cursor = @workspace.parent(cursor)
  }
  raise @config.Invalid("fixture.telemetry_helper_missing")
}

///|
#cfg(any(target="js", target="native"))
fn telemetry_remove(path : String) -> Unit raise {
  match @platform.kind(path) {
    0 => ()
    2 => {
      for name in @platform.list(path) {
        telemetry_remove(path + "/" + name)
      }
      @platform.remove_dir(path)
    }
    _ => @platform.remove_file(path)
  }
}

///|
#cfg(any(target="js", target="native"))
test "trace retention never samples terminal metrics" {
  let session = TelemetrySession::new(Some("unused"), record_traces=false)
  let observer = session.observer()
  let result = observer.scope().observe(@observe.Build, fn(_) { 42 })
  assert_eq(result, 42)
  assert_true(session.records.is_empty())
  assert_eq(session.metrics["build"].0, 1)
  assert_eq(session.dropped, 0)
  session.closed = true
}

///|
#cfg(any(target="js", target="native"))
test "queue overflow and failed export account for every undelivered observation" {
  let session = TelemetrySession::new(Some("unused"))
  let observer = session.observer()
  for i = 0; i < 1025; i = i + 1 {
    ignore(observer.scope().observe(@observe.Build, fn(_) { i }))
  }
  assert_eq(session.records.length(), 2048)
  assert_eq(session.dropped, 2)
  assert_eq(session.metrics["build"].0, 1025)
  session.flush_to_process(
    "node",
    telemetry_helper(),
    "morphir-unavailable-exporter",
    [],
  )
  assert_eq(session.dropped, 2050)
  assert_true(session.records.is_empty())
  assert_eq(session.metrics["build"].0, 1025)
  session.flush()
  assert_eq(session.dropped, 2050)
}

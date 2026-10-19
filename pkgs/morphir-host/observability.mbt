///|
pub struct TelemetrySession {
  priv sequence : Ref[Int32]
  priv metrics : Map[String, (Int32, Double, Array[Int32])]
  priv dimensions : Map[String, (Int32, Double, Array[Int32])]
  priv mut metrics_overflow : Int32
  priv records : Array[@observe.Observation]
  priv audit_records : Array[MetadataAuditRecord]
  priv path : String?
  priv local_root : String?
  priv format : String
  priv record_traces : Bool
  priv run_id : String
  priv mut next : Int32
  priv mut dropped : Int32
  priv mut closed : Bool
}

///|
pub fn TelemetrySession::new(
  path : String?,
  format~ : String = "ion-binary",
  record_traces~ : Bool = true,
) -> TelemetrySession raise {
  if !["ion-binary", "ion-text", "json-lines", "text"].contains(format) {
    raise @config.Invalid("observability.unsupported_format")
  }
  if path == Some("@stderr") && !["text", "json-lines"].contains(format) {
    raise @config.Invalid("observability.stderr_requires_text")
  }
  // No I/O occurs until flush. Host clocks/IDs are only used for enabled sessions.
  let run_id = if path is Some(_) { @platform.observation_id() } else { "" }
  {
    sequence: Ref(0),
    metrics: Map([]),
    dimensions: Map([]),
    metrics_overflow: 0,
    records: [],
    audit_records: [],
    path,
    local_root: None,
    format,
    record_traces,
    run_id,
    next: 0,
    dropped: 0,
    closed: false,
  }
}

///|
/// Choose a default beneath .morphir/logs only when logging is enabled.
/// An explicit path keeps the existing sink contract, including @stderr.
/// Directory creation for defaults happens only in the bounded flush worker.
pub fn TelemetrySession::local(
  root : String,
  path : String?,
  enabled~ : Bool = false,
  kind~ : String = "execution",
  format~ : String = "ion-binary",
) -> TelemetrySession raise {
  if path is Some(_) || !enabled {
    return TelemetrySession::new(path, format~)
  }
  if !["frontend", "execution"].contains(kind) {
    raise @config.Invalid("observability.invalid_log_kind")
  }
  let extension = match format {
    "ion-text" => ".ion"
    "json-lines" => ".jsonl"
    "text" => ".log"
    _ => ".ionb"
  }
  let root = root.split("\\").map(StringView::to_owned).collect().join("/")
  let session = TelemetrySession::new(
    Some(root + "/.morphir/logs/" + kind + extension),
    format~,
  )
  { ..session, local_root: Some(root), }
}

///|
pub fn TelemetrySession::observer(self : TelemetrySession) -> @observe.Observer {
  self.observer_with_clocks(@platform.monotonic_seconds, @platform.wall_seconds)
}

///|
// Keep queue and metric behavior independent of the embedding host's clocks.
fn TelemetrySession::observer_with_clocks(
  self : TelemetrySession,
  monotonic : () -> Double,
  wall : () -> Double,
) -> @observe.Observer {
  if self.path is None || self.closed {
    return @observe.Observer::noop()
  }
  {
    enabled: fn() { self.path is Some(_) && !self.closed },
    try_record: fn(record) {
      if self.closed {
        self.dropped += 1
        return @observe.Unavailable
      }
      if record.context.run_id.length() > 256 ||
        record.context.span_id.length() > 64 ||
        record.context.parent_id.length() > 64 ||
        record.context.trace_id.length() > 64 ||
        record.duration_seconds < 0.0 ||
        record.duration_seconds.is_nan() ||
        record.duration_seconds.is_inf() ||
        record.wall_seconds.is_nan() ||
        record.wall_seconds.is_inf() ||
        (
          record.details is Some(d) &&
          (d.entry.length() > 1024 || d.code.length() > 128)
        ) ||
        (
          record.correlation is Some(c) &&
          (
            c.target.length() > 32 ||
            c.lease_id.length() > 128 ||
            c.call_id.length() > 128 ||
            c.attempt_id.length() > 32
          )
        ) {
        self.dropped += 1
        return @observe.Dropped
      }
      if record.signal is Succeeded ||
        record.signal is Failed ||
        record.signal is Cancelled {
        let key = record.stage.name()
        let (count, total, buckets) = self.metrics
          .get(key)
          .unwrap_or((0, 0.0, [0, 0, 0, 0, 0, 0, 0]))
        let bounds = [0.001, 0.01, 0.1, 1.0, 10.0, 60.0]
        let mut bucket = 6
        for i = 0; i < bounds.length(); i = i + 1 {
          if record.duration_seconds <= bounds[i] {
            bucket = i
            break
          }
        }
        buckets[bucket] += 1
        self.metrics[key] = (
          count + 1,
          total + record.duration_seconds,
          buckets,
        )
        let target = match record.correlation {
          Some(c) =>
            if ["js", "wasm-gc", "native", "llvm"].contains(c.target) {
              c.target
            } else {
              "other"
            }
          None => "none"
        }
        let provider = if record.correlation is Some(_) {
          "process"
        } else {
          "engine"
        }
        let outcome = match record.signal {
          Failed => "failed"
          Cancelled => "cancelled"
          _ =>
            if record.details is Some(d) && d.code.has_prefix("sdk.") {
              "model-error"
            } else {
              "succeeded"
            }
        }
        let descriptor = key + "|" + target + "|" + provider + "|" + outcome
        if !self.dimensions.contains(descriptor) &&
          self.dimensions.length() >= 128 {
          self.metrics_overflow += 1
        } else {
          let (count, sum, buckets) = self.dimensions
            .get(descriptor)
            .unwrap_or((0, 0.0, [0, 0, 0, 0, 0, 0, 0]))
          buckets[bucket] += 1
          self.dimensions[descriptor] = (
            count + 1,
            sum + record.duration_seconds,
            buckets,
          )
        }
      }
      // Local trace retention is independent of metric aggregation. Propagated
      // trace flags belong to the adapter; filtering here never samples metrics.
      if !self.record_traces {
        return @observe.Filtered
      }
      if self.records.length() + self.audit_records.length() >= 2048 {
        self.dropped += 1
        return @observe.Dropped
      }
      self.records.push(record)
      @observe.Accepted
    },
    monotonic,
    wall,
    next_id: fn() {
      self.next += 1
      let hex = self.next.to_string(radix=16)
      "0000000000000000"[:16 - hex.length()].to_owned() + hex
    },
    run_id: self.run_id,
    trace_id: @identity.sha256(@utf8.encode(self.run_id))[:32].to_owned(),
    sequence: self.sequence,
  }
}

///|
/// Typed compatibility adapter. Free-text event contents are excluded from logs.
pub fn TelemetrySession::event(self : TelemetrySession, event : Event) -> Unit {
  let stage = match event {
    Phase(_) => @observe.Legacy
    Diagnostic(_) => @observe.Execute
    Generated(_) => @observe.Generate
    Validated(_) => @observe.Build
    Published(_) => @observe.Execute
  }
  let o = self.observer()
  if (o.enabled)() {
    self.sequence.val += 1
    ignore(
      o.record({
        context: {
          run_id: self.run_id,
          trace_id: @identity.sha256(@utf8.encode(self.run_id))[:32].to_owned(),
          span_id: "",
          parent_id: "",
        },
        details: None,
        correlation: None,
        sequence: self.sequence.val,
        stage,
        signal: @observe.Notice,
        wall_seconds: @platform.wall_seconds(),
        duration_seconds: 0.0,
      }),
    )
  }
}

///|
/// Bounded local sink. Failures are reported directly on stderr, never recursively.
pub fn TelemetrySession::flush(self : TelemetrySession) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  guard self.path is Some(path) else { return }
  try {
    let bytes = match self.format {
      "ion-binary" =>
        @ion_binary.write_binary(
          self.records.map(r => r.to_ion()) +
          self.audit_records.map(r => r.to_ion()) +
          [self.metrics_ion()],
        )
      "ion-text" =>
        @utf8.encode(
          (self.records.map(r => @ion_text.write_ion(r.to_ion())) +
          self.audit_records.map(r => @ion_text.write_ion(r.to_ion()))).join(
            "\n",
          ) +
          "\n",
        )
      "json-lines" =>
        @utf8.encode(
          (self.records.map(r => r.to_json().stringify()) +
          self.audit_records.map(r => r.to_json().stringify())).join("\n") +
          "\n",
        )
      _ =>
        @utf8.encode(
          (self.records.map(r => r.stage.name() + " " + r.to_json().stringify()) +
          self.audit_records.map(r => {
            "metadata." + r.phase.name() + " " + r.to_json().stringify()
          })).join("\n") +
          "\n",
        )
    }
    // File I/O drains in a separate worker with its own allowance. Result work
    // and publication locks never wait on an unbounded filesystem write.
    if !@platform.flush_file(
        path,
        bytes,
        1000,
        root=self.local_root.unwrap_or(""),
      ) {
      self.dropped += self.records.length() + self.audit_records.length()
      @platform.stderr(
        "warning: observability sink unavailable or flush deadline\n",
      )
    }
    if self.dropped > 0 {
      @platform.stderr(
        "warning: observability dropped " +
        self.dropped.to_string() +
        " records\n",
      )
    }
  } catch {
    _ => {
      self.dropped += self.records.length() + self.audit_records.length()
      @platform.stderr("warning: observability sink unavailable\n")
    }
  }
  self.records.clear()
  self.audit_records.clear()
}

///|
pub fn TelemetrySession::metrics(self : TelemetrySession) -> Json {
  let names = self.metrics.keys().collect()
  names.sort()
  let descriptors = self.dimensions.keys().collect()
  descriptors.sort()
  {
    "profile": "morphir-metrics-v1",
    "unit": "seconds",
    "bounds": [0.001, 0.01, 0.1, 1.0, 10.0, 60.0],
    "series_limit": 128,
    "series_overflow": self.metrics_overflow,
    "dimensions": descriptors.map(key => {
      let fields = key.split("|").collect()
      let (count, total, buckets) = self.dimensions[key]
      (
        {
          "stage": fields[0].to_owned(),
          "target": fields[1].to_owned(),
          "provider": fields[2].to_owned(),
          "outcome": fields[3].to_owned(),
          "count": count,
          "duration_seconds_sum": total,
          "duration_seconds_buckets": buckets,
        } : Json)
    }),
    "dropped": self.dropped,
    "stages": names.map(name => {
      let (count, total, buckets) = self.metrics[name]
      (
        {
          "stage": name,
          "count": count,
          "duration_seconds_sum": total,
          "duration_seconds_buckets": buckets,
        } : Json)
    }),
  }
}

///|
fn TelemetrySession::metrics_ion(
  self : TelemetrySession,
) -> @ion.IonValue raise {
  receipt_ion_metrics(self.metrics())
}

///|
fn receipt_ion_metrics(value : Json) -> @ion.IonValue raise {
  match value {
    Null => @ion.IonValue::untyped_null()
    Number(n, ..) => @ion.IonValue::float(n)
    Array(a) => @ion.IonValue::list(a.map(receipt_ion_metrics))
    Object(f) => {
      let names = f.keys().collect()
      names.sort()
      @protocol.record(names.map(n => (n, receipt_ion_metrics(f[n]))))
    }
    _ => receipt_ion(value)
  }
}

///|
/// Drain a native Ion batch to an isolated async exporter through the shipped
/// Node worker. The exporter reads stdin; its process tree owns a separate flush
/// allowance. Call only after execution and outside publisher locks.
pub fn TelemetrySession::flush_to_process(
  self : TelemetrySession,
  node : String,
  helper : String,
  program : String,
  args : Array[String],
  timeout~ : Int32 = 1000,
  cancel_file~ : String = "",
  program_identity~ : String? = None,
  clear_otel_environment~ : Bool = false,
) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  guard self.path is Some(_) else { return }
  let mut directory : String? = None
  let mut delivered = false
  try {
    if timeout < 1 ||
      timeout > 5000 ||
      !@platform.process_supported() ||
      node == "" ||
      helper == "" ||
      program == "" ||
      node.length() > 4096 ||
      helper.length() > 4096 ||
      program.length() > 4096 ||
      args.length() > 128 ||
      args.any(a => a.length() > 4096) ||
      cancel_file.length() > 4096 {
      raise @config.Invalid("observability.exporter_unavailable")
    }
    let started = @platform.monotonic_seconds()
    let batch = @ion_binary.write_binary(
      self.records.map(r => r.to_ion()) +
      self.audit_records.map(r => r.to_ion()) +
      [self.metrics_ion()],
    )
    let root = @platform.temporary()
    directory = Some(root)
    let payload = root + "/observations.ionb"
    if !@platform.flush_file(payload, batch, timeout) {
      raise @config.Invalid("observability.flush_failed")
    }
    let remaining = timeout -
      ((@platform.monotonic_seconds() - started) * 1000.0).to_int()
    if remaining <= 0 {
      raise @config.Invalid("observability.flush_deadline")
    }
    let request = root + "/export.json"
    @platform.write(
      request,
      (
        {
          "profile": "morphir-telemetry-export-v1",
          "program": program,
          "args": args,
          "payload": payload,
          "timeout": remaining,
          "cancelFile": cancel_file,
          "programIdentity": program_identity
          .map(Json::string)
          .unwrap_or(Json::null()),
          "clearOtelEnvironment": clear_otel_environment,
        } : Json).stringify(),
    )
    let response = @platform.process(
      node,
      [helper, request],
      @platform.cwd(),
      "",
      remaining + 500,
    )
    delivered = build_field(response, "exitCode") == Json::number(0.0)
  } catch {
    _ => ()
  }
  if directory is Some(root) {
    dispose_build_tree(root) catch {
      _ => delivered = false
    }
  }
  if !delivered {
    self.dropped += self.records.length() + self.audit_records.length()
    @platform.stderr(
      "warning: observability exporter unavailable or flush deadline\n",
    )
  }
  self.records.clear()
  self.audit_records.clear()
}

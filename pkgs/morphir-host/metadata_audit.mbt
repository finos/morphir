///|
pub(all) enum MetadataAuditPhase {
  Acquire
  Probe
  Restore
  Decode
  Context
  Admission
  Cleanup
} derive(Eq, Debug)

///|
pub fn MetadataAuditPhase::name(self : MetadataAuditPhase) -> String {
  match self {
    Acquire => "acquire"
    Probe => "probe"
    Restore => "restore"
    Decode => "decode"
    Context => "context"
    Admission => "admission"
    Cleanup => "cleanup"
  }
}

///|
/// A selected digest is distinct from verification during this operation.
/// Native revision remains absent until the retained response is checked.
pub(all) struct MetadataAuditEvidence {
  service : String
  service_sha256 : String
  service_verified : Bool
  release : String
  native_revision : String?
  profile : String
  profile_version : String
  assurance : String
  profile_verified : Bool
}

///|
/// Audit evidence never grants authority and is excluded from semantic receipts.
pub(all) struct MetadataAuditRecord {
  run_id : String
  operation : String
  project : String
  phase : MetadataAuditPhase
  signal : @observe.Signal
  code : String
  evidence : MetadataAuditEvidence?
  wall_seconds : Double
  duration_seconds : Double
}

///|
pub fn MetadataAuditRecord::to_json(self : MetadataAuditRecord) -> Json {
  {
    "profile": "morphir-metadata-invocation-v1",
    "run_id": self.run_id,
    "operation": self.operation,
    "project": self.project,
    "phase": self.phase.name(),
    "outcome": match self.signal {
      Started => "started"
      Succeeded => "succeeded"
      Failed => "refused"
      Cancelled => "cancelled"
      Notice => "notice"
    },
    "code": self.code,
    "evidence": match self.evidence {
      None => Json::null()
      Some(e) =>
        {
          "service": e.service,
          "service_sha256": e.service_sha256,
          "service_verified": e.service_verified,
          "release": e.release,
          "native_revision": match e.native_revision {
            Some(revision) => Json::string(revision)
            None => Json::null()
          },
          "execution_profile": e.profile,
          "profile_version": e.profile_version,
          "assurance": e.assurance,
          "profile_verified": e.profile_verified,
        }
    },
    "wall_seconds": self.wall_seconds,
    "duration_seconds": self.duration_seconds,
  }
}

///|
pub fn MetadataAuditRecord::to_ion(
  self : MetadataAuditRecord,
) -> @ion.IonValue raise {
  receipt_ion_metrics(self.to_json()).with_annotation(
    @ion.SymbolToken::new("morphir_metadata_invocation_v1"),
  )
}

///|
/// Optional, bounded telemetry adapter. Failures never affect provider decisions.
pub(all) struct MetadataAuditSink {
  enabled : () -> Bool
  try_record : (MetadataAuditRecord) -> @observe.Delivery raise
  monotonic : () -> Double
  wall : () -> Double
  run_id : String
}

///|
pub fn MetadataAuditSink::noop() -> MetadataAuditSink {
  {
    enabled: fn() { false },
    try_record: fn(_) { @observe.Filtered },
    monotonic: fn() { 0.0 },
    wall: fn() { 0.0 },
    run_id: "",
  }
}

///|
/// Share the existing sink destination and bounded flush worker. Audit records
/// have their own profile and never become metric cardinality dimensions.
pub fn TelemetrySession::metadata_audit_sink(
  self : TelemetrySession,
) -> MetadataAuditSink {
  {
    enabled: fn() { self.path is Some(_) && !self.closed && self.record_traces },
    try_record: fn(record) {
      if self.closed {
        return @observe.Unavailable
      }
      if self.path is None || !self.record_traces {
        return @observe.Filtered
      }
      if !record.valid() ||
        self.audit_records.length() >= 256 ||
        self.audit_records.length() + self.records.length() >= 2048 {
        self.dropped += 1
        return @observe.Dropped
      }
      self.audit_records.push(record)
      @observe.Accepted
    },
    monotonic: @platform.monotonic_seconds,
    wall: @platform.wall_seconds,
    run_id: self.run_id,
  }
}

///|
priv struct MetadataAuditContext {
  sink : MetadataAuditSink
  operation : String
  project : String
  mut evidence : MetadataAuditEvidence?
}

///|
fn MetadataAuditContext::emit(
  self : MetadataAuditContext,
  phase : MetadataAuditPhase,
  signal : @observe.Signal,
  code : String,
  duration : Double,
) -> Unit {
  try {
    if (self.sink.enabled)() {
      ignore(
        (self.sink.try_record)({
          run_id: self.sink.run_id,
          operation: self.operation,
          project: self.project,
          phase,
          signal,
          code,
          evidence: self.evidence,
          wall_seconds: (self.sink.wall)(),
          duration_seconds: duration,
        }),
      )
    }
  } catch {
    _ => ()
  }
}

///|
fn MetadataAuditContext::clock(self : MetadataAuditContext) -> Double {
  try {
    if (self.sink.enabled)() {
      (self.sink.monotonic)()
    } else {
      0.0
    }
  } catch {
    _ => 0.0
  }
}

///|
fn MetadataAuditContext::provider_observer(
  self : MetadataAuditContext,
) -> @linked_metadata.ProviderObserver {
  let started = Ref(0.0)
  {
    notify: fn(signal) {
      match signal {
        Started => {
          started.val = self.clock()
          self.emit(Admission, @observe.Started, "", 0.0)
        }
        Succeeded =>
          self.emit(
            Admission,
            @observe.Succeeded,
            "",
            self.clock() - started.val,
          )
        Refused(code) =>
          self.emit(
            Admission,
            @observe.Failed,
            code,
            self.clock() - started.val,
          )
        Cancelled =>
          self.emit(
            Admission,
            @observe.Cancelled,
            "metadata.restore_cancelled",
            self.clock() - started.val,
          )
      }
    },
  }
}

///|
fn[T] MetadataAuditContext::observe(
  self : MetadataAuditContext,
  phase : MetadataAuditPhase,
  run : () -> T raise,
) -> T raise {
  let start = self.clock()
  self.emit(phase, @observe.Started, "", 0.0)
  let result = run() catch {
    error => {
      let message = error_message(error)
      let signal = if message.contains("Cancelled") {
        @observe.Cancelled
      } else {
        @observe.Failed
      }
      let code = match error {
        @linked_metadata.Invalid(code, _, _) => code
        _ => {
          let candidate = message
            .split(":")
            .collect()
            .get(0)
            .map(StringView::to_owned)
            .unwrap_or("")
          if candidate.has_prefix("metadata.restore_") {
            candidate
          } else if signal is Cancelled {
            "metadata.restore_cancelled"
          } else {
            "metadata.restore_process_failed"
          }
        }
      }
      self.emit(phase, signal, code, self.clock() - start)
      raise error
    }
  }
  self.emit(phase, @observe.Succeeded, "", self.clock() - start)
  result
}

///|
fn MetadataAuditRecord::valid(self : MetadataAuditRecord) -> Bool {
  fn digest(value : String) -> Bool {
    value.length() == 64 &&
    value.to_array().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
  }
  let evidence_valid = match self.evidence {
    None => true
    Some(e) => {
      let revision_valid = match e.native_revision {
        None => true
        Some(r) => digest(r)
      }
      e.service == @metadata_wire.SERVICE_ID &&
      digest(e.service_sha256) &&
      e.release.length() <= 4096 &&
      e.profile == "local-library-mvp" &&
      e.profile_version == "0.1.0-draft.1" &&
      e.assurance == "portable" &&
      revision_valid
    }
  }
  self.run_id.length() <= 256 &&
  self.operation.length() <= 128 &&
  digest(self.project) &&
  self.code.length() <= 128 &&
  self.code
  .to_array()
  .all(c => {
    (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '.' || c == '_'
  }) &&
  !(self.signal is Notice) &&
  self.duration_seconds >= 0.0 &&
  !self.duration_seconds.is_nan() &&
  !self.duration_seconds.is_inf() &&
  !self.wall_seconds.is_nan() &&
  !self.wall_seconds.is_inf() &&
  evidence_valid
}

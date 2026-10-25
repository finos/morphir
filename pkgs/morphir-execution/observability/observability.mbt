///|
pub(all) enum Stage {
  Plan
  Decode
  Frontend
  Parse
  ProfileCheck
  Resolve
  Lower
  Generate
  Build
  Invoke
  Call
  Evaluate
  Compare
  Cleanup
  Execute
  Legacy
} derive(Eq, Debug)

///|
pub fn Stage::name(self : Stage) -> String {
  match self {
    Plan => "plan"
    Decode => "decode"
    Frontend => "frontend"
    Parse => "parse"
    ProfileCheck => "profile-check"
    Resolve => "resolve"
    Lower => "lower"
    Generate => "generate"
    Build => "build"
    Invoke => "invoke"
    Call => "call"
    Evaluate => "evaluate"
    Compare => "compare"
    Cleanup => "cleanup"
    Execute => "execute"
    Legacy => "legacy"
  }
}

///|
pub(all) enum Signal {
  Started
  Succeeded
  Failed
  Cancelled
  Notice
} derive(Eq, Debug)

///|
pub(all) enum Delivery {
  Accepted
  Filtered
  Dropped
  Unavailable
} derive(Eq, Debug)

///|
pub(all) struct ObservationContext {
  run_id : String
  span_id : String
  parent_id : String
  trace_id : String
}

///|
/// Fixed fields exclude model values, paths, environment and unbounded labels.
pub(all) struct Details {
  entry : String
  code : String
}

///|
pub(all) struct Observation {
  details : Details?
  context : ObservationContext
  correlation : Correlation?
  sequence : Int32
  stage : Stage
  signal : Signal
  wall_seconds : Double
  duration_seconds : Double
}

///|
pub(all) struct Observer {
  enabled : () -> Bool
  try_record : (Observation) -> Delivery raise
  monotonic : () -> Double
  wall : () -> Double
  next_id : () -> String
  run_id : String
  trace_id : String
  sequence : Ref[Int32]
}

///|
pub fn Observer::noop() -> Observer {
  {
    enabled: fn() { false },
    try_record: fn(_) { Filtered },
    monotonic: fn() { 0.0 },
    wall: fn() { 0.0 },
    next_id: fn() { "" },
    run_id: "",
    trace_id: "",
    sequence: Ref(0),
  }
}

///|
pub struct Scope {
  priv observer : Observer
  priv context : ObservationContext
  priv sequence : Ref[Int32]
}

///|
pub fn Observer::scope(self : Observer) -> Scope {
  {
    observer: self,
    context: {
      run_id: self.run_id,
      trace_id: self.trace_id,
      span_id: "",
      parent_id: "",
    },
    sequence: self.sequence,
  }
}

///|
/// Sink errors are contained by record; exporter health stays outside this scope.
pub fn[T] Scope::observe(
  self : Scope,
  stage : Stage,
  body : (Scope) -> T raise,
  details~ : Details? = None,
  is_cancelled~ : (Error) -> Bool = fn(error) {
    error is @execution.Invalid("Cancelled")
  },
) -> T raise {
  let o = self.observer
  if !(o.enabled)() {
    return body(self)
  }
  let context = ObservationContext::{
    run_id: o.run_id,
    trace_id: o.trace_id,
    span_id: (o.next_id)(),
    parent_id: self.context.span_id,
  }
  let child = Scope::{ observer: o, context, sequence: self.sequence, }
  let start = (o.monotonic)()
  fn emit(signal : Signal, duration : Double) -> Unit {
    self.sequence.val += 1
    ignore(
      o.record({
        context,
        details: match signal {
          Failed | Cancelled =>
            Some({
              entry: details.map(d => d.entry).unwrap_or(""),
              code: if signal is Cancelled {
                "execution.cancelled"
              } else {
                "execution.stage_failed"
              },
            })
          _ => details
        },
        correlation: None,
        sequence: self.sequence.val,
        stage,
        signal,
        wall_seconds: (o.wall)(),
        duration_seconds: duration,
      }),
    )
  }
  emit(Started, 0.0)
  let mut terminal = Signal::Failed
  errdefer emit(terminal, (o.monotonic)() - start)
  let attempt = Ok(body(child)) catch { error => Err(error) }
  let result = match attempt {
    Ok(value) => value
    Err(error) => {
      if is_cancelled(error) {
        terminal = Cancelled
      }
      raise error
    }
  }
  emit(Succeeded, (o.monotonic)() - start)
  result
}

///|
pub fn Observation::to_ion(self : Observation) -> @ion.IonValue {
  @execution.record([
    ("profile", @ion.IonValue::string("morphir-observation-v1")),
    (
      "details",
      match self.details {
        Some(d) =>
          @execution.record([
            ("entry", @ion.IonValue::string(d.entry)),
            ("code", @ion.IonValue::string(d.code)),
          ])
        None => @ion.IonValue::untyped_null()
      },
    ),
    ("run_id", @ion.IonValue::string(self.context.run_id)),
    ("trace_id", @ion.IonValue::string(self.context.trace_id)),
    (
      "correlation",
      match self.correlation {
        Some(c) => c.to_ion()
        None => @ion.IonValue::new(@ion.Null(@ion.Null))
      },
    ),
    ("span_id", @ion.IonValue::string(self.context.span_id)),
    ("parent_id", @ion.IonValue::string(self.context.parent_id)),
    ("sequence", @ion.IonValue::int(self.sequence)),
    ("stage", @ion.IonValue::string(self.stage.name())),
    (
      "signal",
      @ion.IonValue::string(
        match self.signal {
          Started => "started"
          Succeeded => "succeeded"
          Failed => "failed"
          Cancelled => "cancelled"
          Notice => "notice"
        },
      ),
    ),
    ("wall_seconds", @ion.IonValue::float(self.wall_seconds)),
    ("duration_seconds", @ion.IonValue::float(self.duration_seconds)),
  ])
}

///|
pub fn Observation::to_json(self : Observation) -> Json {
  {
    "profile": "morphir-observation-v1",
    "details": match self.details {
      Some(d) => { "entry": d.entry, "code": d.code }
      None => Json::null()
    },
    "run_id": self.context.run_id,
    "trace_id": self.context.trace_id,
    "correlation": match self.correlation {
      Some(c) => c.to_json()
      None => Json::null()
    },
    "span_id": self.context.span_id,
    "parent_id": self.context.parent_id,
    "sequence": self.sequence,
    "stage": self.stage.name(),
    "signal": match self.signal {
      Started => "started"
      Succeeded => "succeeded"
      Failed => "failed"
      Cancelled => "cancelled"
      Notice => "notice"
    },
    "wall_seconds": self.wall_seconds,
    "duration_seconds": self.duration_seconds,
  }
}

///|
pub extend Stage with Eq::{equal, not_equal}

///|
pub extend Stage with @debug.Debug::{to_repr}

///|
pub extend Signal with Eq::{equal, not_equal}

///|
pub extend Signal with @debug.Debug::{to_repr}

///|
pub extend Delivery with Eq::{equal, not_equal}

///|
pub extend Delivery with @debug.Debug::{to_repr}

///|
pub(all) struct Correlation {
  target : String
  lease_id : String
  call_id : String
  attempt_id : String
}

///|
pub fn Correlation::to_json(self : Correlation) -> Json {
  {
    "target": self.target,
    "lease_id": self.lease_id,
    "call_id": self.call_id,
    "attempt_id": self.attempt_id,
  }
}

///|
pub fn Correlation::to_ion(self : Correlation) -> @ion.IonValue {
  @execution.record([
    ("target", @ion.IonValue::string(self.target)),
    ("lease_id", @ion.IonValue::string(self.lease_id)),
    ("call_id", @ion.IonValue::string(self.call_id)),
    ("attempt_id", @ion.IonValue::string(self.attempt_id)),
  ])
}

///|
/// W3C version 00 only. Baggage and tracestate are deliberately unsupported.
pub(all) struct TraceContext {
  trace_id : String
  parent_id : String
  flags : String
} derive(Eq)

///|
fn hex_id(s : String, size : Int32) -> Bool {
  s.length() == size &&
  s.to_array().all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) &&
  s.to_array().any(c => c != '0')
}

///|
pub fn TraceContext::parse(value : String) -> TraceContext raise {
  let parts = value.split("-").map(s => s.to_owned()).collect()
  if parts.length() != 4 ||
    parts[0] != "00" ||
    !hex_id(parts[1], 32) ||
    !hex_id(parts[2], 16) ||
    !["00", "01"].contains(parts[3]) {
    raise @execution.Invalid("observability.invalid_trace_context")
  }
  { trace_id: parts[1], parent_id: parts[2], flags: parts[3], }
}

///|
pub fn TraceContext::header(self : TraceContext) -> String raise {
  let value = "00-" + self.trace_id + "-" + self.parent_id + "-" + self.flags
  ignore(TraceContext::parse(value))
  value
}

///|
pub fn Scope::trace_context(self : Scope) -> TraceContext? raise {
  if !(self.observer.enabled)() {
    return None
  }
  let context = TraceContext::{
    trace_id: self.context.trace_id,
    parent_id: self.context.span_id,
    flags: "01",
  }
  ignore(context.header())
  Some(context)
}

///|
pub extend TraceContext with Eq::{equal, not_equal}

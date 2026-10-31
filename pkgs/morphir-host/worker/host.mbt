///|
/// Where the host runs. Native and Node hosts start process and WASM
/// workers on the machine they find at run time; a browser host starts WASM
/// workers only.
pub(all) enum HostPlatform {
  Native(Machine)
  Node(Machine)
  Browser
} derive(Eq, Debug)

///|
pub extend HostPlatform with Eq::{equal, not_equal}

///|
pub extend HostPlatform with @debug.Debug::{to_repr}

///|
/// The runtime kinds this host can start.
pub fn HostPlatform::runtimes(self : HostPlatform) -> Array[RuntimeKind] {
  match self {
    Native(_) | Node(_) => [Process, Wasm]
    Browser => [Wasm]
  }
}

///|
/// Refuses a runtime that this host cannot start, before anything starts.
pub fn HostPlatform::admit(
  self : HostPlatform,
  runtime : WorkerRuntime,
) -> Unit raise Refusal {
  let supported = self.runtimes()
  guard supported.contains(runtime.kind()) else {
    raise Refusal(
      code=RuntimeUnavailable,
      message="this host starts \{supported.map(kind => kind.to_string()).join(" and ")} workers, not \{runtime.kind()} workers",
    )
  }
  match (self, runtime) {
    (Native(machine) | Node(machine), Process(platform~, ..)) =>
      if machine.mismatch(platform) is Some(message) {
        raise Refusal(code=PlatformMismatch, message~)
      }
    _ => ()
  }
}

///|
/// Whether this host can start the runtime: its kind, and for a process
/// whether the machine runs its platform.
pub fn HostPlatform::supports(
  self : HostPlatform,
  runtime : WorkerRuntime,
) -> Bool {
  try self.admit(runtime) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
/// A cancellation source that the driver polls while it waits for a worker:
/// a Moon-Lander stop token, or any probe.
pub struct StopSignal {
  priv probe : () -> Bool
}

///|
pub fn StopSignal::new(probe : () -> Bool) -> StopSignal {
  { probe, }
}

///|
pub fn StopSignal::never() -> StopSignal {
  { probe: () => false, }
}

///|
/// The host stop token of a Moon-Lander application, for example the token
/// of the CLI's lifetime, which SIGINT triggers.
pub fn StopSignal::of_token(token : @hosting.StopToken) -> StopSignal {
  { probe: () => token.stop_requested(), }
}

///|
pub fn StopSignal::requested(self : StopSignal) -> Bool {
  (self.probe)()
}

///|
/// What a finished session reports: what it negotiated, the limits that
/// applied, the restricted Extism profile when it applied, how the worker
/// stopped and why the session ended early, if it did. The host never sends
/// `$/cancelRequest`; `to_json` states `wireCancellation: false`. Under
/// `limits`, `to_json` gives the byte limits that the host enforces, and
/// under `limits.negotiated` the depth and node limits that were negotiated.
/// The party that decodes the model enforces those two, not the host.
pub struct SessionReport {
  negotiated : Negotiated?
  limits : Limits
  extism : ExtismProfile?
  stop : WorkerStop?
  ending : Ending?
} derive(Eq, Debug)

///|
pub extend SessionReport with Eq::{equal, not_equal}

///|
pub extend SessionReport with @debug.Debug::{to_repr}

///|
pub fn SessionReport::new(
  limits : Limits,
  negotiated? : Negotiated,
  extism? : ExtismProfile,
  stop? : WorkerStop,
  ending? : Ending,
) -> SessionReport {
  { negotiated, limits, extism, stop, ending, }
}

///|
fn StopReason::name(self : StopReason) -> String {
  match self {
    GraceExpired => "grace-expired"
    Deadline => "deadline"
    Cancelled => "cancelled"
    Fault => "fault"
  }
}

///|
fn StopMethod::name(self : StopMethod) -> String {
  match self {
    ExitedAfterExit => "exited-after-exit"
    GroupSignal => "group-signal"
    JobTermination => "job-termination"
    TreeTermination => "tree-termination"
    ThreadTermination => "thread-termination"
  }
}

///|
fn WorkerStop::report(self : WorkerStop) -> Json {
  let fields : Map[String, Json] = match self.status {
    Exited(code~) => { "status": "exited", "code": code }
    Signalled(signal~) => { "status": "signalled", "signal": signal }
    Terminated(reason) => { "status": "terminated", "reason": reason.name() }
    Unconfirmed(reason) => { "status": "unconfirmed", "reason": reason.name() }
  }
  fields["stopMethod"] = Json::string(self.stop_method.name())
  fields["stderrTruncated"] = Json::boolean(self.stderr.truncated())
  Json::object(fields)
}

///|
fn Ending::report(self : Ending) -> Json {
  match self {
    Refused(code~, message~) =>
      { "class": "refused", "code": code.to_string(), "message": message }
    Failed(Host(code~, message~)) =>
      { "class": "failed", "code": code.to_string(), "message": message }
    Failed(Guest(code~, message~, ..)) =>
      { "class": "failed", "guestCode": code, "message": message }
    Deadline => { "class": "deadline" }
    Cancelled => { "class": "cancelled" }
  }
}

///|
/// The host enforces the frame limits and the model byte limits, and checks
/// the declared decoded length. It does not decode models, so the depth and
/// node limits are only negotiated.
fn Limits::report(self : Limits) -> Json {
  {
    "requestBytes": self.request_bytes,
    "responseBytes": self.response_bytes,
    "model": {
      "maxEncodedBytes": self.model.encoded_bytes,
      "maxDecodedBytes": self.model.decoded_bytes,
    },
    "negotiated": { "maxDepth": self.model.depth, "maxNodes": self.model.nodes },
  }
}

///|
pub extend SessionReport with ToJson::{to_json}

///|
pub impl ToJson for SessionReport with fn to_json(self) {
  let fields : Map[String, Json] = {
    "limits": self.limits.report(),
    "wireCancellation": false,
  }
  if self.negotiated is Some(negotiated) {
    fields["protocolVersion"] = Json::string(
      negotiated.offer.line().to_string(),
    )
    if negotiated.offer is Model(tuple) {
      fields["tuple"] = tuple.to_json()
    }
  }
  if self.extism is Some(profile) {
    fields["extismProfile"] = profile.to_json()
  }
  if self.stop is Some(stop) {
    fields["worker"] = stop.report()
  }
  if self.ending is Some(ending) {
    fields["ending"] = ending.report()
  }
  Json::object(fields)
}

///|
/// Why a probe or an activation did not give a result. The report says how
/// far the session went and how the worker stopped.
pub(all) suberror HostError {
  Ended(Ending, report~ : SessionReport)
} derive(Eq, Debug)

///|
pub extend HostError with Eq::{equal, not_equal}

///|
pub extend HostError with @debug.Debug::{to_repr}

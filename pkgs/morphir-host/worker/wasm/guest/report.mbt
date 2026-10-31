///|
/// The command name of the worker mode in its reports.
pub let worker_command : String = "extension worker"

///|
/// The most bytes of a message in one report event, a fault, a refusal or an
/// output, as text of a JSON string: an escaped control character counts 6
/// bytes. A longer message is cut and ends with `…`, so that a fault line
/// always fits whole in the host's 64 KiB stderr tail.
pub const EVENT_MESSAGE_BYTES : Int32 = 4096

///|
/// The most bytes of reported guest output, counted as for
/// `EVENT_MESSAGE_BYTES`, that the worker mode holds for one call: as much as
/// the host's stderr tail keeps.
pub const OUTPUT_TAIL_BYTES : Int32 = 65536

///|
/// The bytes of a character in a JSON string. Every control character is
/// counted as a `\u` escape, which is the most that it can take.
fn json_char_bytes(char : Char) -> Int32 {
  match char.to_int() {
    0x22 | 0x5c => 2
    code if code < 0x20 => 6
    code if code < 0x80 => 1
    code if code < 0x800 => 2
    code if code < 0x10000 => 3
    _ => 4
  }
}

///|
/// The text cut at a character boundary to at most `EVENT_MESSAGE_BYTES` as
/// JSON text, with `…` at the end, and whether it was cut.
fn cut(text : String) -> (String, Bool) {
  let mut total = 0
  for char in text {
    total += json_char_bytes(char)
  }
  guard total > EVENT_MESSAGE_BYTES else { return (text, false) }
  let budget = EVENT_MESSAGE_BYTES - 3
  let kept = StringBuilder()
  let mut bytes = 0
  for char in text {
    let size = json_char_bytes(char)
    if bytes + size > budget {
      break
    }
    bytes += size
    kept.write_char(char)
  }
  kept.write_string("…")
  (kept.to_string(), true)
}

///|
/// The text cut to at most `EVENT_MESSAGE_BYTES` as JSON text, with `…` at
/// the end when it was cut.
pub fn cut_message(text : String) -> String {
  cut(text).0
}

///|
/// One event of the worker mode's report on stderr. With `--json` each event
/// is one `morphir/command-event` line; the host reads the last `fault` or
/// `refused` event when the worker's stdout ends.
pub(all) enum WorkerEvent {
  /// The worker loaded the module and serves frames.
  Started(
    abi~ : @worker.WasmAbi,
    module_sha256~ : @worker.Sha256,
    build_identity~ : String,
    bounds~ : @worker.EnforcedBounds
  )
  /// The guest wrote or logged something.
  Output(GuestOutput)
  /// The worker dropped this many bytes of guest output in one call: the
  /// oldest outputs above `OUTPUT_TAIL_BYTES` and the cut ends of outputs.
  OutputDropped(bytes~ : Int64)
  /// The guest stopped serving for a fault.
  Fault(@worker.GuestFault)
  /// The worker refused to serve before any request.
  Refused(code~ : @worker.RefusalCode, message~ : String)
  /// The worker exits with this status.
  Exited(code~ : Int32)
} derive(Eq, Debug)

///|
pub extend WorkerEvent with Eq::{equal, not_equal}

///|
pub extend WorkerEvent with @debug.Debug::{to_repr}

///|
fn fault_kind(fault : @worker.GuestFault) -> (String, String?) {
  match fault {
    Trap(text) => ("trap", Some(text))
    MemoryLimit(text) => ("memory-limit", Some(text))
    CallDeadline => ("call-deadline", None)
    BudgetExhausted => ("budget-exhausted", None)
    Failure(text) => ("failure", Some(text))
  }
}

///|
fn fault_of(kind : String, message : String) -> @worker.GuestFault? {
  match kind {
    "trap" => Some(Trap(message))
    "memory-limit" => Some(MemoryLimit(message))
    "call-deadline" => Some(CallDeadline)
    "budget-exhausted" => Some(BudgetExhausted)
    "failure" => Some(Failure(message))
    _ => None
  }
}

///|
/// The refusal codes that a worker reports.
let refusal_codes : Array[@worker.RefusalCode] = [
  WorkerRuntimeMismatch,
  AbiUnsupported,
  AbiMismatch,
  WasmFeatureUnsupported,
  RequestLimit,
]

///|
/// The event as one `morphir/command-event` value with its sequence number.
pub fn WorkerEvent::to_json(self : WorkerEvent, sequence~ : Int32) -> Json {
  let fields : Map[String, Json] = {
    "profile": "morphir/command-event",
    "contractVersion": "0.1.0",
    "command": worker_command,
    "sequence": sequence,
  }
  match self {
    Started(abi~, module_sha256~, build_identity~, bounds~) => {
      fields["event"] = "started"
      fields["abi"] = Json(abi.to_string())
      fields["moduleSha256"] = Json(module_sha256.to_string())
      fields["buildIdentity"] = Json(build_identity)
      fields["bounds"] = Json(bounds)
    }
    Output(output) => {
      fields["event"] = "output"
      fields["output"] = Json(cut_message(output.to_string()))
    }
    OutputDropped(bytes~) => {
      fields["event"] = "output"
      fields["output"] = Json(dropped_text(bytes))
      fields["droppedBytes"] = Json::number(bytes.to_double())
    }
    Fault(fault) => {
      let (kind, message) = fault_kind(fault)
      let detail : Map[String, Json] = { "kind": Json(kind) }
      if message is Some(text) {
        detail["message"] = Json(cut_message(text))
      }
      fields["event"] = "fault"
      fields["fault"] = Json::object(detail)
    }
    Refused(code~, message~) => {
      fields["event"] = "refused"
      fields["error"] = {
        "code": code.to_string(),
        "message": cut_message(message),
      }
    }
    Exited(code~) => {
      fields["event"] = "exited"
      fields["exitCode"] = Json(code)
    }
  }
  Json::object(fields)
}

///|
fn dropped_text(bytes : Int64) -> String {
  "\{bytes} bytes of guest output were dropped"
}

///|
/// The event as one line of text, for the default report.
pub fn WorkerEvent::to_text(self : WorkerEvent) -> String {
  let prefix = "morphir \{worker_command}: "
  prefix +
  (match self {
    Started(abi~, module_sha256~, ..) =>
      "serving \{abi} module \{module_sha256}"
    Output(output) => cut_message(output.to_string())
    OutputDropped(bytes~) => dropped_text(bytes)
    Fault(fault) => {
      let (kind, message) = fault_kind(fault)
      "fault \{kind}" +
      message.map(text => ": \{cut_message(text)}").unwrap_or("")
    }
    Refused(code~, message~) => "refused \{code}: \{cut_message(message)}"
    Exited(code~) => "exit \{code}"
  })
}

///|
/// The channel error for the last `fault` or `refused` event in a worker's
/// stderr, or `None` when it has neither. Lines that are not report events,
/// such as a line cut at the start of a stderr tail, are skipped.
pub fn WorkerEvent::ending_in(stderr : Bytes) -> @worker.ChannelError? {
  let lines = @utf8.decode_lossy(stderr).split("\n").to_array()
  for index = lines.length() - 1; index >= 0; index = index - 1 {
    let event = @json.parse(lines[index]) catch { _ => continue }
    guard event
      is {
        "profile": "morphir/command-event",
        "command": String(command),
        "event": String(name),
        ..
      } &&
      command == worker_command else {
      continue
    }
    match (name, event) {
      ("fault", { "fault": { "kind": String(kind), .. } as detail, .. }) => {
        let message = match detail {
          { "message": String(text), .. } => text
          _ => ""
        }
        if fault_of(kind, message) is Some(fault) {
          return Some(GuestFailed(fault))
        }
      }
      (
        "refused",
        {
          "error": { "code": String(code), "message": String(message), .. },
          ..
        },
      ) =>
        for known in refusal_codes {
          if known.to_string() == code {
            return Some(Refused(code=known, message~))
          }
        }
      _ => ()
    }
  }
  None
}

///|
/// The text cut at a character boundary to at most `EVENT_MESSAGE_BYTES`
/// UTF-8 bytes.
fn bounded_text(text : String) -> String {
  let kept = StringBuilder()
  let mut bytes = 0
  for char in text {
    bytes += match char.to_int() {
      code if code < 0x80 => 1
      code if code < 0x800 => 2
      code if code < 0x10000 => 3
      _ => 4
    }
    if bytes > EVENT_MESSAGE_BYTES {
      return kept.to_string()
    }
    kept.write_char(char)
  }
  text
}

///|
fn bounded_bytes(bytes : Bytes) -> Bytes {
  guard bytes.length() > EVENT_MESSAGE_BYTES else { bytes }
  bytes[0:EVENT_MESSAGE_BYTES].to_owned()
}

///|
/// The output with each payload cut to at most `EVENT_MESSAGE_BYTES` bytes,
/// so that the tail keeps no more than the report shows. The report does not
/// change: it shows at most `EVENT_MESSAGE_BYTES` bytes of JSON text, and each
/// byte of payload gives at least one byte of JSON text.
fn bounded(output : GuestOutput) -> GuestOutput {
  match output {
    Stdout(bytes) => Stdout(bounded_bytes(bytes))
    Stderr(bytes) => Stderr(bounded_bytes(bytes))
    Log(level, text) => Log(level, bounded_text(text))
    MorphirLog(level~, text) =>
      MorphirLog(level=bounded_text(level), bounded_text(text))
    RefusedHttp(verb~, url~) =>
      RefusedHttp(verb=bounded_text(verb), url=bounded_text(url))
  }
}

///|
/// The guest output of one call that the worker mode reports when the call
/// ends: the newest outputs whose reported text is at most
/// `OUTPUT_TAIL_BYTES`, each cut to `EVENT_MESSAGE_BYTES`, and the number of
/// bytes that it dropped. Memory stays bounded whatever the guest writes.
pub struct OutputTail {
  /// Each output with its payloads cut to what the report shows, the bytes
  /// that its report takes as JSON text, and the UTF-8 bytes of its text that
  /// the report shows.
  priv items : @deque.Deque[(GuestOutput, Int32, Int32)]
  priv mut kept : Int32
  priv mut dropped : Int64
}

///|
pub fn OutputTail::new() -> OutputTail {
  { items: @deque.Deque([]), kept: 0, dropped: 0L, }
}

///|
/// Adds one output and drops the oldest outputs above the bound. The dropped
/// count is in UTF-8 bytes of the outputs' text.
pub fn OutputTail::push(self : OutputTail, output : GuestOutput) -> Unit {
  let text = output.to_string()
  let size = @utf8.encode(text).length()
  let (shown_text, was_cut) = cut(text)
  let shown = if was_cut {
    @utf8.encode(shown_text).length() - @utf8.encode("…").length()
  } else {
    size
  }
  let mut cost = 0
  for char in shown_text {
    cost += json_char_bytes(char)
  }
  self.dropped += (size - shown).to_int64()
  let kept = if was_cut { bounded(output) } else { output }
  self.items.push_back((kept, cost, shown))
  self.kept += cost
  while self.kept > OUTPUT_TAIL_BYTES {
    guard self.items.pop_front() is Some((_, oldest_cost, oldest_shown)) else {
      break
    }
    self.kept -= oldest_cost
    self.dropped += oldest_shown.to_int64()
  }
}

///|
/// The kept outputs, oldest first, and the dropped bytes. The tail is empty
/// afterwards.
pub fn OutputTail::drain(self : OutputTail) -> (Array[GuestOutput], Int64) {
  let items = self.items.iter().map(item => item.0).to_array()
  let dropped = self.dropped
  self.items.clear()
  self.kept = 0
  self.dropped = 0L
  (items, dropped)
}

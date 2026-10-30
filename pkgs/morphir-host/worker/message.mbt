///|
/// One whole MEP message and its size in bytes, as encoded or as read.
/// Framing belongs to the transport; the session core checks the size again.
/// A message is always a JSON object.
pub struct Message {
  priv body : Json
  priv bytes : Int32
} derive(Eq, Debug)

///|
pub extend Message with Eq::{equal, not_equal}

///|
pub extend Message with @debug.Debug::{to_repr}

///|
pub fn Message::new(body : Map[String, Json]) -> Message {
  let body = Json::object(body)
  { body, bytes: @utf8.encode(body.stringify()).length(), }
}

///|
/// Decodes one message body that a transport has read in full.
pub fn Message::parse(bytes : Bytes) -> Message raise ChannelError {
  let text = @utf8.decode(bytes) catch {
    _ => raise FrameInvalid("message is not UTF-8")
  }
  let body = @json.parse(text) catch {
    _ => raise FrameInvalid("message is not JSON")
  }
  guard body is Object(_) else {
    raise FrameInvalid("message is not a JSON object")
  }
  { body, bytes: bytes.length(), }
}

///|
pub fn Message::json(self : Message) -> Json {
  self.body
}

///|
pub fn Message::size(self : Message) -> Int32 {
  self.bytes
}

///|
pub fn Message::to_bytes(self : Message) -> Bytes {
  @utf8.encode(self.body.stringify())
}

///|
/// A transport fault. `WorkerClosed` is the end of the worker's stream;
/// `Stopped` is a call on a channel that the host has already closed or
/// aborted. `FrameLimit` is a frame that declared more bytes than the limit,
/// found before its body was read.
pub(all) suberror ChannelError {
  WorkerClosed
  FrameInvalid(String)
  FrameLimit(declared~ : Int64, limit~ : Int32)
  Stopped
} derive(Eq, Debug)

///|
pub extend ChannelError with Eq::{equal, not_equal}

///|
pub extend ChannelError with @debug.Debug::{to_repr}

///|
/// Why the host stops a worker without waiting for it.
pub(all) enum StopReason {
  GraceExpired
  Deadline
  Cancelled
  Fault
} derive(Eq, Debug)

///|
pub extend StopReason with Eq::{equal, not_equal}

///|
pub extend StopReason with @debug.Debug::{to_repr}

///|
/// How a worker ended. `Exited` and `Signalled` are ends the worker reached
/// itself; `Terminated` is a stop by the host; `Unconfirmed` means the host
/// could not confirm that the worker's process tree stopped.
pub(all) enum StopStatus {
  Exited(code~ : Int32)
  Signalled(signal~ : Int32)
  Terminated(StopReason)
  Unconfirmed(StopReason)
} derive(Eq, Debug)

///|
pub extend StopStatus with Eq::{equal, not_equal}

///|
pub extend StopStatus with @debug.Debug::{to_repr}

///|
/// How the host ended a worker. `ExitedAfterExit` means the worker ended on
/// its own and the host terminated nothing.
pub(all) enum StopMethod {
  ExitedAfterExit
  GroupSignal
  JobTermination
  TreeTermination
  ThreadTermination
} derive(Eq, Debug)

///|
pub extend StopMethod with Eq::{equal, not_equal}

///|
pub extend StopMethod with @debug.Debug::{to_repr}

///|
/// How a worker stopped, how the host stopped it and the final tail of its
/// stderr. Every session ends with one of these.
pub struct WorkerStop {
  status : StopStatus
  stop_method : StopMethod
  stderr : StderrTail
} derive(Eq, Debug)

///|
pub extend WorkerStop with Eq::{equal, not_equal}

///|
pub extend WorkerStop with @debug.Debug::{to_repr}

///|
pub fn WorkerStop::new(
  status : StopStatus,
  stop_method~ : StopMethod,
  stderr~ : StderrTail,
) -> WorkerStop {
  { status, stop_method, stderr, }
}

///|
/// The name of a WASM import, as a module reads it.
pub struct ImportName {
  module_name : String
  name : String
} derive(Eq, Debug)

///|
pub extend ImportName with Eq::{equal, not_equal}

///|
pub extend ImportName with @debug.Debug::{to_repr}

///|
pub fn ImportName::new(module_name : String, name : String) -> ImportName {
  { module_name, name, }
}

///|
pub impl Show for ImportName with fn output(self, logger) {
  logger.write_string(self.module_name)
  logger.write_char('.')
  logger.write_string(self.name)
}

///|
pub extend ImportName with Show::{to_string, output}

///|
/// Why the host could not read an artifact. `Unreadable` may carry an
/// operating-system message, for diagnostics only.
pub(all) enum ArtifactProblem {
  SymbolicLink
  NotRegularFile
  TooLarge
  Unreadable(detail~ : String?)
} derive(Eq, Debug)

///|
pub extend ArtifactProblem with Eq::{equal, not_equal}

///|
pub extend ArtifactProblem with @debug.Debug::{to_repr}

///|
/// A launcher could not start a worker.
pub(all) suberror LaunchError {
  PlatformMismatch(Platform)
  RuntimeUnavailable(supported~ : Array[RuntimeKind])
  DigestMismatch(expected~ : Sha256, actual~ : Sha256)
  ArtifactUnreadable(ArtifactProblem)
  AbiUnsupported(ImportName)
  AbiMismatch(declared~ : WasmAbi, classified~ : WasmAbi)
  WasmFeatureUnsupported(feature~ : String?)
  LaunchFailed(String)
} derive(Eq, Debug)

///|
pub extend LaunchError with Eq::{equal, not_equal}

///|
pub extend LaunchError with @debug.Debug::{to_repr}

///|
/// The level of an Extism log message.
pub(all) enum LogLevel {
  Trace
  Debug
  Info
  Warn
  Error
} derive(Eq, Debug)

///|
pub extend LogLevel with Eq::{equal, not_equal}

///|
pub extend LogLevel with @debug.Debug::{to_repr}

///|
pub impl Show for LogLevel with fn output(self, logger) {
  logger.write_string(
    match self {
      Trace => "trace"
      Debug => "debug"
      Info => "info"
      Warn => "warn"
      Error => "error"
    },
  )
}

///|
pub extend LogLevel with Show::{to_string, output}

///|
/// What a guest gave the host besides its responses. The host keeps it as
/// bounded diagnostics, never in the MEP response stream.
pub(all) enum GuestOutput {
  /// Bytes that the guest wrote to WASI stdout.
  Stdout(Bytes)
  /// Bytes that the guest wrote to WASI stderr.
  Stderr(Bytes)
  /// A message of an Extism `log_*` function.
  Log(LogLevel, String)
  /// A message of `morphir_log`, with the level as the guest named it.
  MorphirLog(level~ : String, String)
  /// An `http_request` that the host refused: the guest has no network.
  RefusedHttp(verb~ : String, url~ : String)
} derive(Eq, Debug)

///|
pub extend GuestOutput with Eq::{equal, not_equal}

///|
pub extend GuestOutput with @debug.Debug::{to_repr}

///|
fn lossy_text(bytes : Bytes) -> String {
  @utf8.decode_lossy(bytes)
}

///|
pub impl Show for GuestOutput with fn output(self, logger) {
  logger.write_string(
    match self {
      Stdout(bytes) => "stdout: \{lossy_text(bytes)}"
      Stderr(bytes) => "stderr: \{lossy_text(bytes)}"
      Log(level, text) => "log \{level}: \{text}"
      MorphirLog(level~, text) => "morphir_log \{level}: \{text}"
      RefusedHttp(verb~, url~) =>
        "refused http_request \{verb} \{url}: the guest has no network access"
    },
  )
}

///|
pub extend GuestOutput with Show::{to_string, output}

///|
/// What an Extism guest's host functions see: the root of its workspace, an
/// empty private directory, and the sink for its output.
pub struct GuestServices {
  workspace_root : String
  output : (GuestOutput) -> Unit
}

///|
pub fn GuestServices::new(
  workspace_root~ : String,
  output~ : (GuestOutput) -> Unit,
) -> GuestServices {
  { workspace_root, output, }
}

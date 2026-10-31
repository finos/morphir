///|
/// The WASI entry has no worker host: on wasm-gc `moonbitlang/async` has no
/// event loop, and on wasm the host's driver would import non-WASI functions.
pub struct WorkerHosting {}

///|
/// No worker host: extension commands refuse before they read a pin.
pub fn WorkerHosting::none() -> WorkerHosting {
  WorkerHosting::{ }
}

///|
/// `extension describe|compile|generate` refuse with
/// `extension.runtime_unavailable` and exit 2, in the report of the hosted
/// targets.
fn extension_command(cli : Cli, context : CommandContext) -> Int32 {
  // The WASI entry passes no launchers.
  ignore(context.workers)
  let message = "this CLI build has no worker host; use the native or npm CLI"
  let report : Json = {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": cli.command.replace(old=" ", new="."),
    "state": "failed",
    "exitCode": 2,
    "diagnostics": [],
    "error": { "code": "extension.runtime_unavailable", "message": message },
  }
  @platform.stderr("extension.runtime_unavailable: " + message + "\n")
  match context.mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("result", report)
    Human => ()
  }
  2
}

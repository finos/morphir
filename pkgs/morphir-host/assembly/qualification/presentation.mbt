///|
/// Keep the runtime prefix in one adapter; Node supplies two argv entries.
#cfg(target="js")
fn finite_argv() -> ArrayView[String] {
  match @env.args() {
    [_, _, .. rest] => rest
    _ => []
  }
}

///|
#cfg(not(target="js"))
fn finite_argv() -> ArrayView[String] {
  match @env.args() {
    [_, .. rest] => rest
    _ => []
  }
}

///|
fn finite_command() -> @argparse.Command {
  @argparse.Command(
    "morphir-host.assembly.qualification",
    about="Generate and verify the command fixture. Leading --json selects one compact morphir/command-result 0.1.0 object plus LF on stdout. Success has state, exitCode0, result and diagnostics; failure has error{code,message}, exitCode1 and no result. Existing JSON success schemas remain bare. --json --help returns help without effects; --json --self-test reports the completed fixture output. Default ignored arguments and failure presentation stay unchanged.",
    disable_help_flag=true,
    disable_help_subcommand=true,
    flags=[
      @argparse.FlagArg("json"),
      @argparse.FlagArg("help", short='h'),
      @argparse.FlagArg("self-test"),
    ],
  )
}

///|
fn finite_success(result : Json) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "morphir-host.assembly.qualification",
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": [],
  }
}

///|
/// Exit only after Node has flushed earlier println writes to stdout. Waiting
/// for this stream callback does not wait for stdin or unrelated event handles.
/// A broken or stalled destination retains status 1 with a five-second deadline.
#cfg(target="js")
extern "js" fn finite_complete_failure(exit : () -> Unit) -> Unit =
  #| function(exit) {
  #|   if (typeof process !== "undefined" && process.stdout &&
  #|       typeof process.stdout.write === "function") {
  #|     const timeout = setTimeout(exit, 5000);
  #|     const finish = () => { clearTimeout(timeout); exit(); };
  #|     process.stdout.once("error", finish);
  #|     process.stdout.write("", finish);
  #|   } else {
  #|     exit();
  #|   }
  #| }

///|
#cfg(not(target="js"))
fn finite_complete_failure(exit : () -> Unit) -> Unit {
  exit()
}

///|
fn finite_failure(error : Error) -> Unit {
  println(
    (
      {
        "profile": "morphir/command-result",
        "contractVersion": "0.1.0",
        "command": "morphir-host.assembly.qualification",
        "state": "failed",
        "exitCode": 1,
        "error": { "code": "command.failed", "message": error.to_string() },
        "diagnostics": [],
      } : Json).stringify(),
  )
  finite_complete_failure(fn() { @sys.exit(1) })
}

///|
fn[T] finite_refuse(message : String, json_mode~ : Bool) -> T raise {
  if json_mode {
    fail(message)
  } else {
    abort(message)
  }
}

///|
fn main raise {
  let argv = finite_argv()
  if argv is ["--json", ..] {
    try {
      let command = finite_command()
      let parsed = command.parse(argv~)
      if parsed.flags.get("help").unwrap_or(false) {
        println(finite_success({ "help": command.render_help() }).stringify())
      } else {
        let output = finite_run(json_mode=true)
        println(
          if parsed.flags.get("self-test").unwrap_or(false) {
            finite_success({ "passed": true, "output": output }).stringify()
          } else {
            output.stringify()
          },
        )
      }
    } catch {
      error => finite_failure(error)
    }
  } else {
    // Historically these fixture programs ignored argv. Keep that legacy path.
    println(finite_run().stringify())
  }
}

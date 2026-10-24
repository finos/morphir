///|
enum DocCommand {
  Generate
  Check
} derive(Eq)

///|
fn docs_command(json_mode~ : Bool = false) -> @argparse.Command {
  @argparse.Command(
    "schemedocs",
    about="Generate and check Scheme documentation examples",
    disable_help_flag=true,
    disable_help_subcommand=true,
    subcommand_required=!json_mode,
    flags=if json_mode {
      [
        @argparse.FlagArg("json", required=true),
        @argparse.FlagArg("help", short='h', global=true),
      ]
    } else {
      []
    },
    subcommands=[
      @argparse.Command("generate", disable_help_flag=true),
      @argparse.Command("check", disable_help_flag=true),
    ],
  )
}

///|
/// Keep the command boundary fixed and every following token literal. The
/// synthetic delimiter belongs to the adapter; user-supplied delimiters are data.
fn parse_docs_arguments(argv : ArrayView[String]) -> @argparse.Matches raise {
  let normalized = match argv {
    [command, .. data] => [command, "--", ..data]
    [] => []
  }
  docs_command().parse(argv=normalized, env=Map([]))
}

///|
fn docs_invocation(matches : @argparse.Matches) -> DocCommand {
  match matches.subcommand {
    Some(("generate", _)) => Generate
    Some(("check", _)) => Check
    _ => abort("schemedocs command selection invariant")
  }
}

///|
/// The entries of a directory on disk, each with whether it is a directory.
fn list_dir(dir : String) -> Array[(String, Bool)] raise {
  let entries = []
  for name in @fs.read_dir(dir) {
    entries.push((name, @fs.is_dir(dir + "/" + name)))
  }
  entries
}

///|
/// The plan for every chapter under `pkgs/morphir-scheme`.
fn current_plan() -> Plan raise {
  let files = find_files(scheme_root, list_dir) catch {
    e => raise DocError("\{scheme_root}: cannot list the chapters: \{e}")
  }
  plan(files, path => @fs.read_file_to_string(path))
}

///|
fn main {
  let argv = @env.args()[1:]
  match argv {
    ["--json", ..] => {
      json_main(argv)
      return
    }
    _ => ()
  }
  // This native filesystem tool owns the program-path prefix, as before.
  let matches = parse_docs_arguments(@env.args()[1:]) catch {
    _ => {
      println("usage: schemedocs generate | check")
      @sys.exit(2)
      return
    }
  }
  try {
    match docs_invocation(matches) {
      Generate => {
        let p = current_plan()
        for output in p.outputs {
          @fs.write_string_to_file(output.1, output.2)
          println("wrote \{output.1}")
        }
        for path in p.stale {
          @fs.remove_file(path)
          println("removed \{path}, which no chapter generates")
        }
      }
      Check => {
        let p = current_plan()
        let problems = []
        for output in p.outputs {
          let current = @fs.read_file_to_string(output.1) catch { _ => "" }
          if check_message(output.0, output.1, output.2, current) is Some(d) {
            problems.push(d)
          }
        }
        for path in p.stale {
          problems.push(stale_message(path))
        }
        if problems.is_empty() {
          println("scheme docs examples are current")
        } else {
          for p in problems {
            println(p)
          }
          println("schemedocs: run `mise run scheme-docs:generate`")
          @sys.exit(1)
        }
      }
    }
  } catch {
    DocError(message) => {
      println("schemedocs: \{message}")
      @sys.exit(1)
    }
    e => {
      println("schemedocs: \{e}")
      @sys.exit(1)
    }
  }
}

///|
fn json_command() -> @argparse.Command {
  docs_command(json_mode=true)
}

///|
fn parse_json_arguments(argv : ArrayView[String]) -> @argparse.Matches raise {
  let normalized = match argv {
    _ => argv.to_owned()
  }
  let parsed = json_command().parse(argv=normalized, env=Map([]))
  if parsed.subcommand is None && !parsed.flags.get("help").unwrap_or(false) {
    // Let the required-command grammar supply the syntax diagnostic.
    ignore(docs_command().parse(argv=[], env=Map([])))
  }
  parsed
}

///|
fn success(command : String, result : Json) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": command,
    "state": "succeeded",
    "exitCode": 0,
    "result": result,
    "diagnostics": [],
  }
}

///|
fn failure(
  command : String,
  exit_code : Int32,
  code : String,
  message : String,
  diagnostics~ : Array[Json] = [],
) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": command,
    "state": "failed",
    "exitCode": exit_code,
    "error": { "code": code, "message": message },
    "diagnostics": diagnostics,
  }
}

///|
// JSON owns stdout only on this path. UCRT text mode translates println's LF;
// _O_BINARY (0x8000) preserves the existing compact JSON bytes on Windows.
#cfg(all(target="native", platform="windows"))
extern "C" fn json_stdout_setmode(fd : Int32, mode : Int32) -> Int32 = "_setmode"

///|
#cfg(all(target="native", platform="windows"))
fn prepare_json_stdout() -> Bool {
  json_stdout_setmode(1, 0x8000) >= 0
}

///|
#cfg(not(all(target="native", platform="windows")))
fn prepare_json_stdout() -> Bool {
  true
}

///|
fn json_main(argv : ArrayView[String]) -> Unit {
  // Prepare before parse refusal, help, domain work or the first JSON write.
  // A failed mode change must not emit a success record or perform file writes.
  if !prepare_json_stdout() {
    @sys.exit(1)
    return
  }
  let matches = parse_json_arguments(argv) catch {
    e => {
      println(
        failure("morphir.schemedocs", 2, "syntax", e.to_string()).stringify(),
      )
      @sys.exit(2)
      return
    }
  }
  if matches.flags.get("help").unwrap_or(false) {
    println(
      success("morphir.schemedocs", { "help": json_command().render_help() }).stringify(),
    )
    return
  }
  let invocation = docs_invocation(matches)
  let command = match invocation {
    Generate => "morphir.schemedocs.generate"
    Check => "morphir.schemedocs.check"
  }
  try {
    let p = current_plan()
    match invocation {
      Generate => {
        for output in p.outputs {
          @fs.write_string_to_file(output.1, output.2)
        }
        for path in p.stale {
          @fs.remove_file(path)
        }
        println(
          success(command, {
            "writtenPaths": p.outputs.map(o => o.1),
            "removedPaths": p.stale,
          }).stringify(),
        )
      }
      Check => {
        let problems = []
        for output in p.outputs {
          let current = @fs.read_file_to_string(output.1) catch { _ => "" }
          if check_message(output.0, output.1, output.2, current) is Some(d) {
            problems.push(d)
          }
        }
        for path in p.stale {
          problems.push(stale_message(path))
        }
        if problems.is_empty() {
          println(
            success(command, {
              "checkedPaths": p.outputs.map(o => o.1),
              "passed": true,
            }).stringify(),
          )
        } else {
          let diagnostics : Array[Json] = problems.map(p => {
            "severity": "error",
            "message": p,
          })
          println(
            failure(
              command,
              1,
              "schemedocs.differences",
              "schemedocs: run `mise run scheme-docs:generate`",
              diagnostics~,
            ).stringify(),
          )
          @sys.exit(1)
        }
      }
    }
  } catch {
    DocError(message) => {
      println(failure(command, 1, "schemedocs.failed", message).stringify())
      @sys.exit(1)
    }
    e => {
      println(
        failure(command, 1, "schemedocs.failed", e.to_string()).stringify(),
      )
      @sys.exit(1)
    }
  }
}

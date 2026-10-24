///|
fn fixture_folder(arguments : ArrayView[String]) -> String raise {
  let command = @argparse.Command(
    "files-acceptance",
    disable_help_flag=true,
    disable_version_flag=true,
    disable_help_subcommand=true,
    positionals=[
      @argparse.PositionArg(
        "fixture-folder",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  )
  // This test host has always treated every operand literally, including -- and
  // --help. End option parsing before the caller's data; the library owns arity.
  let literal = ["--"]
  literal.append(arguments)
  command.parse(argv=literal, env=Map([])).values["fixture-folder"][0]
}

///|
/// Test host only: the process owner supplies the fixed picker result. Renderer
/// requests still contain only protocol frames, never a native pathname.
async fn run(arguments : ArrayView[String], structured : Bool) -> Unit {
  let folder = fixture_folder(arguments) catch {
    error =>
      if structured {
        raise error
      } else {
        abort("Usage: files-acceptance <fixture-folder>")
      }
  }
  let owner = @bridge.FileOwner::new(enabled=true)
  defer owner.close()
  if structured {
    event("ready", 1)
  }
  let pending : Array[Byte] = []
  while @stdio.stdin.read_some(max_len=65536) is Some(chunk) {
    for byte in chunk {
      if byte == b'\n' {
        let source = @utf8.decode(Bytes::from_array(pending), ignore_bom=false)
        let reply = owner.request(
          source,
          fn() raise {
            @session.Caller::admit("main", "app", Some("acceptance-page"))
          },
          async fn() { Some(folder) },
        )
        @stdio.stdout.write(reply + "\n")
        pending.clear()
      } else {
        pending.push(byte)
        if pending.length() > 1048576 {
          if structured {
            raise PresentationError("File frame exceeds 1 MiB")
          } else {
            abort("File frame exceeds 1 MiB")
          }
        }
      }
    }
  }
  if !pending.is_empty() {
    if structured {
      raise PresentationError("Incomplete file frame")
    } else {
      abort("Incomplete file frame")
    }
  }
}

///|
async fn main {
  match presentation(@env.args()[1:]) {
    JsonHelp => json_help()
    Legacy(raw) => run(raw, false)
    Structured(raw) => {
      event("startup", 0)
      run(raw, true) catch {
        error => {
          event("diagnostic", 2, error=Some(error), exit_code=1)
          event("terminal", 3, exit_code=1)
          @sys.exit(1)
        }
      }
      event("terminal", 2)
    }
  }
}

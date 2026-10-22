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
async fn main {
  let folder = fixture_folder(@env.args()[1:]) catch {
    _ => abort("Usage: files-acceptance <fixture-folder>")
  }
  let owner = @bridge.FileOwner::new(enabled=true)
  defer owner.close()
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
          abort("File frame exceeds 1 MiB")
        }
      }
    }
  }
  if !pending.is_empty() {
    abort("Incomplete file frame")
  }
}

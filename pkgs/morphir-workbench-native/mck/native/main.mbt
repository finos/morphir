///|
async fn run(structured : Bool) -> Unit {
  if structured {
    event("ready", 1)
  }
  let pending : Array[Byte] = []
  while @stdio.stdin.read_some(max_len=65536) is Some(chunk) {
    for byte in chunk {
      if byte == b'\n' {
        let line = @utf8.decode(Bytes::from_array(pending)[:], ignore_bom=false)
        guard @mck.handle_line(line) is Some(response) else { return }
        @stdio.stdout.write(response.stringify() + "\n")
        pending.clear()
      } else {
        pending.push(byte)
        if pending.length() > 2097152 {
          if structured {
            raise PresentationError(
              "native owner MCK: NDJSON line exceeds 2 MiB",
            )
          } else {
            abort("native owner MCK: NDJSON line exceeds 2 MiB")
          }
        }
      }
    }
  }
  if !pending.is_empty() {
    if structured {
      raise PresentationError("native owner MCK: incomplete NDJSON line")
    } else {
      abort("native owner MCK: incomplete NDJSON line")
    }
  }
}

///|
async fn main {
  match presentation(@env.args()[1:]) {
    JsonHelp => json_help()
    Legacy(_) => run(false)
    Structured(_) => {
      event("startup", 0)
      run(true) catch {
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

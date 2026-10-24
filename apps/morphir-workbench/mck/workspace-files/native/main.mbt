///|
async fn serve(events : Bool) -> Unit {
  let pending : Array[Byte] = []
  // Bound input before parsing. The MCK transport also bounds its output/input.
  while @stdio.stdin.read_some(max_len=65536) is Some(chunk) {
    for byte in chunk {
      if byte == b'\n' {
        let line = @utf8.decode(Bytes::from_array(pending)[:])
        guard @mck.handle_line(line) is Some(response) else { return }
        @stdio.stdout.write(response.stringify() + "\n")
        pending.clear()
      } else {
        pending.push(byte)
        if pending.length() > 2097152 {
          if events {
            raise PresentationFailure::Message(
              "workspace-files: NDJSON line exceeds 2 MiB",
            )
          } else {
            abort("workspace-files: NDJSON line exceeds 2 MiB")
          }
        }
      }
    }
  }
  if !pending.is_empty() {
    if events {
      raise PresentationFailure::Message(
        "workspace-files: incomplete NDJSON line",
      )
    } else {
      abort("workspace-files: incomplete NDJSON line")
    }
  }
}

///|
async fn main {
  let args = @env.args()
  let mode = presentation_mode(args[1:]) catch {
    error => {
      presentation_write(
        presentation_event(1, "failure", {
          "error": {
            "code": "argument_error",
            "message": Json(error.to_string()),
          },
          "exitCode": 2,
        }),
      )
      @sys.exit(2)
      return
    }
  }
  match mode {
    Human => serve(false)
    Help(text) => presentation_write(presentation_help(text))
    Events => {
      presentation_write(presentation_event(1, "startup", {}))
      presentation_write(presentation_event(2, "ready", {}))
      try {
        serve(true)
        presentation_write(presentation_event(3, "exit", { "exitCode": 0 }))
      } catch {
        error => {
          presentation_write(
            presentation_event(3, "failure", {
              "error": {
                "code": "transport_error",
                "message": Json(presentation_failure_message(error)),
              },
              "exitCode": 1,
            }),
          )
          presentation_write(presentation_event(4, "exit", { "exitCode": 1 }))
          @sys.exit(1)
        }
      }
    }
  }
}

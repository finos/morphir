///|
async fn serve_mep() -> Unit {
  let decoder = @mep.Decoder::new()
  let session = @mep.Session::new(frontend=Some(@frontend.provider()))
  while @stdio.stdin.read_some(max_len=65536) is Some(chunk) {
    for body in decoder.feed(chunk) {
      if session.receive(body) is Some(response) {
        @stdio.stdout.write(@mep.encode_frame(response.stringify()))
      }
      if session.exited() {
        return
      }
    }
  }
  decoder.finish()
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
  let events = match mode {
    Help(text) => {
      presentation_write(presentation_help(text))
      return
    }
    Events => true
    Human => {
      guard args.length() == 1 else {
        @stdio.stderr.write(
          "morphir-moonbit: this executable accepts MEP frames on stdin, without arguments\n",
        )
        @sys.exit(2)
        return
      }
      false
    }
  }
  if events {
    presentation_write(presentation_event(1, "startup", {}))
  }
  try {
    // There is no externally observable readiness handshake in MEP.
    serve_mep()
    if events {
      presentation_write(presentation_event(2, "exit", { "exitCode": 0 }))
    }
  } catch {
    error => {
      if events {
        presentation_write(
          presentation_event(2, "failure", {
            "error": {
              "code": "transport_error",
              "message": Json(
                match error {
                  @mep.InvalidFrame(message) => message
                  _ => "MEP stdio transport failed: " + error.to_string()
                },
              ),
            },
            "exitCode": 1,
          }),
        )
        presentation_write(presentation_event(3, "exit", { "exitCode": 1 }))
      } else {
        match error {
          @mep.InvalidFrame(message) =>
            @stdio.stderr.write("morphir-moonbit: " + message + "\n")
          _ =>
            @stdio.stderr.write("morphir-moonbit: MEP stdio transport failed\n")
        }
      }
      @sys.exit(1)
    }
  }
}

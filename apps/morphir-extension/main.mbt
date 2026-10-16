///|
async fn main {
  try {
    guard @env.args().length() == 1 else {
      @stdio.stderr.write(
        "morphir-moonbit: this executable accepts MEP frames on stdin, without arguments\n",
      )
      @sys.exit(2)
    }
    let decoder = @mep.Decoder::new()
    let session = @mep.Session::new()
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
  } catch {
    @mep.InvalidFrame(message) => {
      @stdio.stderr.write("morphir-moonbit: " + message + "\n")
      @sys.exit(1)
    }
    _ => {
      @stdio.stderr.write("morphir-moonbit: MEP stdio transport failed\n")
      @sys.exit(1)
    }
  }
}

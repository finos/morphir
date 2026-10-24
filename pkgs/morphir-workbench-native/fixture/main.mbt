///|
/// Fault selection is confined to this acceptance executable's filename.
async fn run(structured : Bool) -> Unit {
  let name = @env.args()[0]
  if name.contains("fault-hang") || name.contains("fault-memory") {
    @async.sleep(60000)
    return
  }
  if name.contains("fault-crash") {
    if structured {
      event("terminal", 1, exit_code=7)
    }
    @sys.exit(7)
  }
  if name.contains("fault-frame") {
    @stdio.stdout.write(b"\xff\xff\xff\xff")
    @async.sleep(60000)
    return
  }
  if name.contains("fault-stderr") {
    @stdio.stderr.write(Bytes::from_array(Array::make(70000, b'x')))
    @async.sleep(60000)
    return
  }
  if structured {
    event("ready", 1)
  }
  @native.worker()
  if name.contains("fault-after") {
    if structured {
      event("terminal", 2, exit_code=7)
    }
    @sys.exit(7)
  }
  if name.contains("fault-trailing") {
    @stdio.stdout.write(b"x")
    @async.sleep(60000)
  }
  if name.contains("fault-late-cancel") {
    @async.sleep(60000)
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

///|
/// Fault selection is confined to this acceptance executable's filename.
async fn main {
  let name = @env.args()[0]
  if name.contains("fault-hang") || name.contains("fault-memory") {
    @async.sleep(60000)
    return
  }
  if name.contains("fault-crash") {
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
  @native.worker()
  if name.contains("fault-after") {
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

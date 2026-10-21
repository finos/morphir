///|
/// Test host only: the process owner supplies the fixed picker result. Renderer
/// requests still contain only protocol frames, never a native pathname.
async fn main {
  let args = @env.args()
  guard args.length() == 2 else {
    abort("Usage: files-acceptance <fixture-folder>")
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
          async fn() { Some(args[1]) },
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

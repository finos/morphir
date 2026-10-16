///|
pub suberror Invalid {
  Invalid(String)
}

///|
extern "C" fn now() -> Double = "morphir_worker_now"

///|
extern "C" fn rss(pid : Int32) -> Double = "morphir_worker_rss"

///|
extern "C" fn pid() -> Int32 = "morphir_worker_pid"

///|
extern "C" fn qualified_platform() -> Int32 = "morphir_worker_platform"

///|
extern "C" fn desktop_platform() -> Int32 = "morphir_worker_desktop"

///|
pub fn desktop_supported() -> Bool {
  desktop_platform() == 1 && supported()
}

///|
pub fn supported() -> Bool {
  qualified_platform() == 1 && now() >= 0.0 && rss(pid()) > 0.0
}

///|
pub fn bridge_request(source : String) -> (String, String, String?) raise {
  guard source.length() <= 4194304 && @utf8.encode(source).length() <= 4194304 else {
    raise Invalid("workbench.native_frame_limit")
  }
  guard @wire.parse(source) is Object(fields) &&
    fields.length() == 3 &&
    fields.get("sessionId") is Some(String(id)) &&
    fields.get("path") is Some(String(path)) &&
    fields.get("body") is Some(body) else {
    raise Invalid("workbench.native_shape")
  }
  let body = match body {
    Null => None
    String(body) => {
      guard body.length() <= 1048576 && @utf8.encode(body).length() <= 1048576 else {
        raise Invalid("workbench.native_frame_limit")
      }
      Some(body)
    }
    _ => raise Invalid("workbench.native_shape")
  }
  (id, path, body)
}

///|
pub fn frame(source : String) -> Bytes raise {
  let body = @utf8.encode(source)
  let n = body.length()
  guard n > 0 && n <= 1048576 else {
    raise Invalid("workbench.worker_frame_limit")
  }
  let header = Bytes::from_array([
    ((n >> 24) & 255).to_byte(),
    ((n >> 16) & 255).to_byte(),
    ((n >> 8) & 255).to_byte(),
    (n & 255).to_byte(),
  ])
  header + body
}

///|
fn frame_length(header : Bytes) -> Int32 raise {
  guard header.length() == 4 && header[0] == b'\x00' else {
    raise Invalid("workbench.worker_frame_limit")
  }
  let n = (header[1].to_int() << 16) |
    (header[2].to_int() << 8) |
    header[3].to_int()
  guard n > 0 && n <= 1048576 else {
    raise Invalid("workbench.worker_frame_limit")
  }
  n
}

///|
/// This mode never starts CEF, reads a workspace, or executes generated code.
pub async fn worker() -> Unit {
  let n = frame_length(@stdio.stdin.read_exactly(4))
  let source = @utf8.decode(@stdio.stdin.read_exactly(n))
  guard @stdio.stdin.read_some(max_len=1) == None else {
    raise Invalid("workbench.worker_trailing_input")
  }
  let request = @jobs.decode(source)
  guard request is Object(fields) &&
    fields.get("operation") == Some(Json::string("evaluate")) &&
    fields.get("executionMode") == Some(Json::string("typed")) else {
    raise Invalid("workbench.worker_operation")
  }
  let reply = @pipeline.execute(request)
  guard reply is Object(fields) &&
    fields.get("terminalOutcomes") is Some(outcomes) else {
    raise Invalid("workbench.worker_outcomes")
  }
  @stdio.stdout.write(frame(outcomes.stringify()))
}

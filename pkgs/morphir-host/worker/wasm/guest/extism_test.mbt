///|
/// Loads an Extism guest whose host records every guest output.
fn load_extism(
  bytes : Bytes,
  call? : @guest.CallBounds,
) -> (&@guest.Guest, Array[@guest.GuestOutput]) {
  let outputs = []
  let services = @guest.GuestServices::new(workspace_root="/private/work", output=item => {
    outputs.push(item)
  })
  let guest = @guest.load(bytes, declared=ExtismKernelV1, call?, services~) catch {
    error => abort("the guest did not load: \{@debug.to_string(error)}")
  }
  (guest, outputs)
}

///|
fn request(id : Int32) -> Bytes {
  @utf8.encode(
    "{\"jsonrpc\":\"2.0\",\"id\":\{id},\"method\":\"morphir.extension.describe\"}",
  )
}

///|
test "Extism kernel adapter: one handle call per request on the same instance" {
  let (guest, _) = load_extism(@fixtures.extism_echo_guest())
  assert_eq(
    exchange(guest, request(1)),
    "response {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.extension.describe\"}",
  )
  assert_true(exchange(guest, request(2)).contains("\"id\":2"))
}

///|
test "Extism kernel adapter: initialized and exit are not delivered; exit ends the instance" {
  // A guest that traps on every call: a delivered notification would trap.
  let (guest, _) = load_extism(@fixtures.extism_trapping_guest())
  assert_eq(
    exchange(guest, b"{\"jsonrpc\":\"2.0\",\"method\":\"morphir.initialized\"}"),
    "notified",
  )
  assert_eq(
    exchange(guest, b"{\"jsonrpc\":\"2.0\",\"method\":\"morphir.exit\"}"),
    "exit",
  )
  assert_true(exchange(guest, request(3)).has_prefix("failure"))
}

///|
test "guest traps: the call fails with the trap and the instance is discarded" {
  let (guest, _) = load_extism(@fixtures.extism_trapping_guest())
  assert_true(exchange(guest, request(1)).has_prefix("trap"))
  assert_true(exchange(guest, request(2)).has_prefix("failure"))
}

///|
test "a call that sets an error fails the session with the error" {
  let (guest, _) = load_extism(@fixtures.extism_error_guest())
  let failed = exchange(guest, request(1))
  assert_true(failed.has_prefix("failure") && failed.contains("no parser"))
}

///|
test "IR cache between calls: stored in one call, read in the next, empty in a new session" {
  let (guest, _) = load_extism(@fixtures.extism_cache_guest())
  assert_eq(exchange(guest, request(1)), "response null")
  assert_eq(
    exchange(guest, request(2)),
    "response {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"morphir.extension.describe\"}",
  )
  let (fresh, _) = load_extism(@fixtures.extism_cache_guest())
  assert_eq(exchange(fresh, request(3)), "response null")
}

///|
test "module with Morphir host functions: workspace information and logs become diagnostics" {
  let (guest, outputs) = load_extism(@fixtures.extism_workspace_guest())
  let answer = exchange(guest, request(1))
  assert_eq(answer, "response {\"root\":\"/private/work\",\"output_dir\":\"\"}")
  let rendered = outputs.map(item => item.to_string())
  assert_true(rendered.contains("morphir_log info: guest says hello"))
  assert_true(rendered.contains("log info: extism log line"))
}

///|
test "guest requests HTTP: the call fails, nothing connects and the refusal is recorded" {
  let (guest, outputs) = load_extism(@fixtures.extism_http_guest())
  let failed = exchange(guest, request(1))
  assert_true(failed.has_prefix("failure") && failed.contains("http_request"))
  assert_true(
    outputs
    .iter()
    .any(item => item is RefusedHttp(verb="GET", url="https://example.com/")),
  )
}

///|
test "WASI sandbox: path_open returns an error code and fd_write becomes a diagnostic" {
  let (guest, outputs) = load_extism(@fixtures.extism_wasi_guest())
  let reply = guest.exchange(request(1))
  guard reply is Response(bytes) && bytes.length() == 1 else {
    fail("the WASI guest did not answer: \{@debug.to_string(reply)}")
  }
  // An errno, not success: no file was opened, and the session continues.
  assert_true(bytes[0] != b'\x00')
  assert_true(outputs.iter().any(item => item is Stdout(b"hello")))
  assert_false(@utf8.decode(bytes).contains("hello"))
}

///|
test "the Extism adapter states the engine's bounds" {
  let (guest, _) = load_extism(@fixtures.extism_echo_guest())
  ignore(guest)
  assert_eq(
    @guest.engine_bounds().memory_ceiling,
    @worker.Enforcement::Enforced,
  )
}

///|
test "get_log_level gives info by default" {
  let (guest, _) = load_extism(@fixtures.extism_log_level_guest())
  assert_eq(exchange(guest, request(1)), "response 2")
}

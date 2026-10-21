///|
test "connected envelopes correlate raw JSON RPC replies before admitting file data" {
  assert_eq(
    @files.decode_connected_reply(
      1, b"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"raw business frame\"}",
    ),
    ({ "ok": true, "value": "raw business frame" } : Json),
  )
  assert_eq(
    @files.decode_connected_reply(
      2, b"{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32603,\"message\":\"Unavailable\"}}",
    ),
    ({ "ok": false, "message": "Unavailable" } : Json),
  )
  for
    source in [
      b"{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":\"wrong call\"}", b"{\"jsonrpc\":\"2.0\",\"id\":1,\"id\":1,\"result\":\"duplicate\"}",
      b"{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{},\"extra\":true}", b"{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":1,\"message\":\"Failed\",\"extra\":true}}",
    ] {
    inventory_refused(fn() raise {
      ignore(@files.decode_connected_reply(1, source))
    })
  }
}

///|
/// Admit a complete connected RPC envelope against the sole pending call before
/// the file client admits the inner frame against its captured operation.
pub fn decode_connected_reply(id : Int32, bytes : Bytes) -> Json raise Invalid {
  if id < 1 || bytes.length() > CONNECTED_FRAME_LIMIT {
    raise Invalid("workspace_files.rpc_limit")
  }
  let value = @wire.parse_bounded(
    @utf8.decode(bytes, ignore_bom=false),
    max_depth=16,
    max_nodes=1024,
    max_string_units=CONNECTED_FRAME_LIMIT,
  ) catch {
    _ => raise Invalid("workspace_files.rpc_json")
  }
  guard value is Object(fields) &&
    fields.get("jsonrpc") == Some(Json::string("2.0")) &&
    fields.get("id") is Some(identifier) &&
    integer(identifier, 1, 2147483647) == id else {
    raise Invalid("workspace_files.rpc_id")
  }
  if fields.contains("result") {
    ignore(closed(value, ["jsonrpc", "id", "result"]))
    return { "ok": true, "value": fields["result"] }
  }
  ignore(closed(value, ["jsonrpc", "id", "error"]))
  let error = closed(fields["error"], ["code", "message"])
  ignore(integer(error["code"], -2147483648, 2147483647))
  { "ok": false, "message": text(error["message"], 2048) }
}

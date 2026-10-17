///|
fn Session::generate_model(self : Session, id : Json, params : Json) -> Json {
  guard self.models is Some(transport) && !transport.tuples.is_empty() else {
    return rpc_error(
      id, -32013, "Model transport is unavailable in this session",
    )
  }
  let retained = retain_input(params, transport) catch {
    Refused(code) =>
      return rpc_error(id, -32602, "Model admission refused: " + code)
    @wire.Invalid(code, _) =>
      return rpc_error(id, -32602, "Model admission refused: " + code)
    _ => return rpc_error(id, -32602, "Model admission refused: invalid_model")
  }
  let output = @generator.generate(
    retained.input,
    metadata_capabilities=self.metadata_capabilities,
  ) catch {
    @generator.Invalid(code, context, message) =>
      return result(id, generation_failure(code, context + ": " + message))
  }
  let response = generation_result(id, output, [
    {
      "path": if field(field(retained.model, "payload"), "codec") ==
        Json::string("ion-binary") {
        "mep/source-model.ionb"
      } else {
        "mep/source-model.json"
      },
      "content": @base64.encode(retained.bytes[:]),
      "binary": true,
    },
    {
      "path": "mep/source-envelope.json",
      "content": retained.model.stringify(),
      "binary": false,
    },
  ])
  if @utf8.encode(response.stringify()).length() > MAX_FRAME_BYTES {
    result(
      id,
      generation_failure(
        "mep.response_limit", "Generated artifacts and retained model exceed the MEP frame budget",
      ),
    )
  } else {
    response
  }
}

///|
pub(all) suberror Invalid {
  Invalid(String)
}

///|
fn closed(value : Json, names : Array[String]) -> Map[String, Json] raise {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    names.all(name => fields.contains(name)) else {
    raise Invalid("workbench.host_shape")
  }
  fields
}

///|
fn string(value : Json) -> String raise {
  guard value is String(text) else { raise Invalid("workbench.host_shape") }
  text
}

///|
fn version(fields : Map[String, Json]) -> Unit raise {
  if fields["contractVersion"] != Json::string("0.2.0-draft.1") {
    raise Invalid("workbench.host_version")
  }
}

///|
/// Used on raw external framing before any ordinary JSON decoding.
pub fn decode(source : String) -> Json raise {
  if source.length() > 1048576 || @utf8.encode(source).length() > 1048576 {
    raise Invalid("workbench.host_input_limit")
  }
  @wire.parse(source)
}

///|
pub fn decode_reply(source : String) -> Json {
  { "ok": true, "value": decode(source) } catch {
    error => failure(error)
  }
}

///|
/// The library lexer is flat and understands strings, comments and lobs. Check
/// structural depth before its recursive AST reader sees untrusted Ion input.
fn admit_ion_structure(source : String) -> Unit raise {
  if source.length() > 1048576 || @utf8.encode(source).length() > 1048576 {
    raise Invalid("workbench.host_input_limit")
  }
  let tokens = @ion_text.tokenize(source[:])
  if tokens.length() > 300000 {
    raise Invalid("workbench.host_input_limit")
  }
  let mut depth = 0
  for token in tokens {
    match token.kind() {
      ListStart | SexpStart | StructStart => {
        depth += 1
        if depth > 512 {
          raise Invalid("workbench.host_input_limit")
        }
      }
      ListEnd | SexpEnd | StructEnd => depth -= 1
      _ => ()
    }
  }
}

///|
fn command(source : String) -> Map[String, Json] raise {
  // Internal command wrapping may escape a full external frame once more.
  if source.length() > 4194304 || @utf8.encode(source).length() > 4194304 {
    raise Invalid("workbench.host_input_limit")
  }
  guard @wire.parse(source) is Object(fields) && fields.contains("op") else {
    raise Invalid("workbench.host_shape")
  }
  fields
}

///|
fn failure(error : Error) -> Json {
  let code = match error {
    Invalid(code) | @receipts.Invalid(code) | @owner.Invalid(code) => code
    @native_reply.Invalid(code) => code
    @protocol.Invalid(code) | @wire.Invalid(code, _) =>
      code.split(":").next().unwrap_or(code).to_owned()
    _ => "workbench.host_admission"
  }
  { "ok": false, "code": @outcomes.bounded(code, 128) }
}

///|
pub struct Host {
  priv owner : @owner.Session
}

///|
pub fn Host::new(offer : String) -> Host raise {
  { owner: @owner.Session::new(@receipts.Offer::from_json(decode(offer))), }
}

///|
/// Private host commands never become v1 JSON-RPC operations.
pub fn Host::handle(self : Host, source : String) -> Json {
  try {
    let fields = command(source)
    let op = string(fields["op"])
    let value = match op {
      "submit-scheme"
      | "submit-native-policy"
      | "submit-http-policy"
      | "plan-scheme"
      | "claim-scheme"
      | "replan-scheme" => self.scheme_command(op, fields)
      "submit" => {
        ignore(closed(Json::object(fields), ["op", "body"]))
        let body = closed(decode(string(fields["body"])), [
          "contractVersion", "model", "entry", "inputs",
        ])
        version(body)
        let inputs = closed(body["inputs"], ["format", "source"])
        let raw = string(inputs["source"])
        let arguments = match inputs["format"] {
          String("json") => decode(raw)
          String("ion-text") => {
            admit_ion_structure(raw)
            @arguments.ion_arguments(Json::null(), raw, true)
          }
          _ => raise Invalid("workbench.host_format")
        }
        let suite = @protocol.Suite::from_json({
          "profile": "morphir-invocations-v1",
          "calls": [
            {
              "id": "workbench",
              "entry": body["entry"],
              "arguments": arguments,
            },
          ],
        })
        let unit = @data.IRUnit::new(
          "workbench",
          @migration.to_current(@versioned.read(string(body["model"]))),
        )
        let receipt = self.owner.submit(unit, suite)
        (
          {
            "identity": receipt.identity().to_json(),
            "calls": ["workbench"],
            "receipt": receipt.to_json(),
          } : Json)
      }
      "query" | "cancel" | "release" => {
        ignore(closed(Json::object(fields), ["op", "body"]))
        let body = closed(decode(string(fields["body"])), [
          "contractVersion", "identity",
        ])
        version(body)
        let identity = @receipts.Identity::from_json(body["identity"])
        match op {
          "query" => self.owner.query(identity).to_json()
          "cancel" => self.owner.cancel(identity).to_json()
          _ => {
            self.owner.release(identity)
            ({ "released": true } : Json)
          }
        }
      }
      "claim" => {
        ignore(closed(Json::object(fields), ["op", "identity"]))
        let plan = self.owner.claim(
          @receipts.Identity::from_json(fields["identity"]),
        )
        let call = plan.suite.calls[0]
        (
          {
            "operation": "evaluate",
            "executionMode": "typed",
            "source": @codec.to_json(plan.unit.distribution).stringify(),
            "entry": call.entry,
            "arguments": call.arguments.map(@protocol.Value::to_json),
          } : Json)
      }
      "complete" => {
        ignore(closed(Json::object(fields), ["op", "identity", "outcomes"]))
        self.owner
        .complete(
          @receipts.Identity::from_json(fields["identity"]),
          @protocol.Outcomes::from_json(fields["outcomes"]),
        )
        .to_json()
      }
      _ => raise Invalid("workbench.host_operation")
    }
    { "ok": true, "value": value }
  } catch {
    error => failure(error)
  }
}

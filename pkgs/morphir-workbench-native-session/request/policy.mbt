///|
/// Exact native mappings. The selected mapping is retained by the page session.
pub(all) enum Contract {
  Executions
  CapabilityChecks
} derive(Eq)

///|
pub extend Contract with Eq::{equal, not_equal}

///|
pub fn Contract::version(self : Contract) -> String {
  match self {
    Executions => "0.2.0-draft.1"
    CapabilityChecks => "0.2.0-draft.2"
  }
}

///|
pub fn Contract::from_string(value : String) -> Contract raise Invalid {
  match value {
    "0.2.0-draft.1" => Executions
    "0.2.0-draft.2" => CapabilityChecks
    _ => raise Invalid("native.frame.shape")
  }
}

///|
pub fn Request::contract(self : Request) -> Contract {
  match self.value {
    Object(fields) =>
      match fields["contractVersion"] {
        String("0.2.0-draft.2") => CapabilityChecks
        _ => Executions
      }
    _ => abort("Admitted native request")
  }
}

///|
/// This validates the compatibility wire selection, not model capabilities.
fn checking_selection(value : Json) -> Unit raise Invalid {
  let fields = closed(value, ["profile", "contractVersion", "policy"])
  guard fields["profile"] == Json::string("morphir/workbench/admission") &&
    fields["contractVersion"] == Json::string("0.1.0-draft.1") &&
    [Json::string("strict"), Json::string("permissive")].contains(
      fields["policy"],
    ) else {
    raise Invalid("native.frame.shape")
  }
}

///|
/// New exact mapping. The frozen decoder remains closed to all policy fields.
pub fn decode_policy(bytes : Bytes) -> Request raise Invalid {
  guard bytes.length() <= 1048576 else { raise Invalid("native.frame.limit") }
  let source = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => raise Invalid("native.frame.utf8")
  }
  let value = @wire.parse_bounded(source) catch {
    @wire.Invalid("json_limit", _) => raise Invalid("native.frame.limit")
    _ => raise Invalid("native.frame.json")
  }
  guard value is Object(fields) &&
    fields.get("contractVersion") == Some(Json::string("0.2.0-draft.2")) else {
    raise Invalid("native.frame.shape")
  }
  if fields.get("operation") is Some(String(operation)) &&
    [
      "workspace.choose", "workspace.cancel-picker", "workspace.revoke", "workspace.open",
      "workspace.read", "workspace.release",
    ].contains(operation) &&
    bytes.length() > 4096 {
    raise Invalid("native.frame.limit")
  }
  // Project a separate copy through unchanged common framing and nested-source
  // checks. Never remove fields from the original admitted request.
  let common = @wire.parse_bounded(value.stringify()) catch {
    _ => raise Invalid("native.frame.limit")
  }
  guard common is Object(projected) else { abort("Native request object") }
  projected["contractVersion"] = Json::string("0.2.0-draft.1")
  if fields.get("operation") == Some(Json::string("execution.submit")) {
    guard fields.get("payload") is Some(Object(payload)) else {
      raise Invalid("native.frame.shape")
    }
    let names = [
      "contractVersion", "model", "entry", "inputs", "runtime", "providerId",
    ]
    if payload.contains("admission") {
      names.push("admission")
      checking_selection(payload["admission"])
    }
    ignore(closed(fields["payload"], names))
    guard payload["runtime"] == Json::string("scheme") else {
      raise Invalid("native.frame.shape")
    }
    let provider = text(payload["providerId"], 1, 128)
    guard provider.length() <= 128 else { raise Invalid("native.frame.shape") }
    guard projected["payload"] is Object(body) else { abort("Native payload") }
    body.remove("runtime") |> ignore
    body.remove("providerId") |> ignore
    body.remove("admission") |> ignore
  }
  ignore(decode(@utf8.encode(common.stringify())))
  { value, }
}

///|
/// Host dispatch selects an explicit mapping before effects or caller admission.
pub fn decode_current(bytes : Bytes) -> Request raise Invalid {
  guard bytes.length() <= 1048576 else { raise Invalid("native.frame.limit") }
  let source = @utf8.decode(bytes[:], ignore_bom=false) catch {
    _ => raise Invalid("native.frame.utf8")
  }
  let value = @wire.parse_bounded(source) catch {
    @wire.Invalid("json_limit", _) => raise Invalid("native.frame.limit")
    _ => raise Invalid("native.frame.json")
  }
  match value {
    Object(fields) if fields.get("contractVersion") ==
      Some(Json::string("0.2.0-draft.2")) => decode_policy(bytes)
    _ => decode(bytes)
  }
}

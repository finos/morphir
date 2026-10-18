///|
/// Scope of the qualified native checking-policy mapping, not runtime authority.
pub fn policy_offer() -> Json {
  {
    "profile": "morphir/workbench/admission",
    "contractVersion": "0.1.0-draft.1",
    "runtime": "scheme",
    "evaluator": "scheme-portable-v1/shared-sdk/bounded",
    "policies": ["strict", "permissive"],
  }
}

///|
fn policy_descriptor_value(
  value : Json,
  expected_session : String?,
) -> Json raise {
  guard value is Object(fields) &&
    fields.get("contractVersion") == Some(Json::string("0.2.0-draft.2")) else {
    raise Invalid("native.reply.shape")
  }
  let executions = fields.get("operations") == Some((["executions"] : Json)) ||
    fields.get("operations") == Some((["executions", "workspace"] : Json))
  ignore(
    closed(
      value,
      if executions {
        [
          "profile", "contractVersion", "sessionId", "operations", "offer", "capabilityChecks",
        ]
      } else {
        ["profile", "contractVersion", "sessionId", "operations"]
      },
    ),
  )
  if executions && fields["capabilityChecks"] != policy_offer() {
    raise Invalid("native.reply.shape")
  }
  let common = parse(@utf8.encode(value.stringify()))
  guard common is Object(projected) else { abort("Native descriptor object") }
  projected.remove("capabilityChecks") |> ignore
  projected["contractVersion"] = Json::string("0.2.0-draft.1")
  ignore(descriptor_value(common, expected_session))
  value
}

///|
pub fn descriptor_policy(
  bytes : Bytes,
  expected_session~ : String? = None,
) -> Json raise Invalid {
  policy_descriptor_value(parse(bytes), expected_session) catch {
    Invalid(code) => raise Invalid(code)
    _ => raise Invalid("native.reply.shape")
  }
}

///|
fn policy_selection(value : Json) -> Unit raise {
  let fields = closed(value, ["profile", "contractVersion", "policy"])
  guard fields["profile"] == Json::string("morphir/workbench/admission") &&
    fields["contractVersion"] == Json::string("0.1.0-draft.1") &&
    [Json::string("strict"), Json::string("permissive")].contains(
      fields["policy"],
    ) else {
    raise Invalid("native.reply.shape")
  }
}

///|
fn boundary_array(value : Json, limit : Int32) -> Array[Json] raise {
  guard value is Array(items) && items.length() <= limit else {
    raise Invalid("native.reply.shape")
  }
  items
}

///|
fn boundary_type(
  value : Json,
  depth : Int32,
  budget : Ref[Int32],
) -> Unit raise {
  budget.val -= 1
  guard depth <= 64 && budget.val >= 0 && value is Object(fields) else {
    raise Invalid("native.reply.shape")
  }
  match fields.get("type") {
    Some(
      String(
        "unit"
        | "bool"
        | "int"
        | "decimal"
        | "float64"
        | "text"
        | "character"
        | "function"
      )
    ) => ignore(closed(value, ["type"]))
    Some(String("list" | "maybe")) => {
      ignore(closed(value, ["type", "item"]))
      boundary_type(fields["item"], depth + 1, budget)
    }
    Some(String("tuple")) => {
      ignore(closed(value, ["type", "items"]))
      for item in boundary_array(fields["items"], 1024) {
        boundary_type(item, depth + 1, budget)
      }
    }
    Some(String("record")) => {
      ignore(closed(value, ["type", "fields"]))
      for item in boundary_array(fields["fields"], 1024) {
        let record_field = closed(item, ["name", "type"])
        ignore(text(record_field["name"], 1, 1024))
        boundary_type(record_field["type"], depth + 1, budget)
      }
    }
    Some(String("result")) => {
      ignore(closed(value, ["type", "ok", "err"]))
      boundary_type(fields["ok"], depth + 1, budget)
      boundary_type(fields["err"], depth + 1, budget)
    }
    Some(String("custom")) => {
      ignore(closed(value, ["type", "name"]))
      ignore(text(fields["name"], 1, 1024))
    }
    _ => raise Invalid("native.reply.shape")
  }
}

///|
fn policy_boundary(value : Json) -> Unit raise {
  let fields = closed(value, ["entries", "definitions"])
  let budget = Ref(10000)
  for item in boundary_array(fields["entries"], 1000) {
    let entry = closed(item, ["name", "inputs", "output"])
    ignore(text(entry["name"], 1, 1024))
    for input in boundary_array(entry["inputs"], 64) {
      boundary_type(input, 0, budget)
    }
    boundary_type(entry["output"], 0, budget)
  }
  for item in boundary_array(fields["definitions"], 256) {
    let definition = closed(item, ["name", "constructors"])
    ignore(text(definition["name"], 1, 1024))
    for item in boundary_array(definition["constructors"], 256) {
      let variant = closed(item, ["name", "inputs"])
      ignore(text(variant["name"], 1, 1024))
      for input in boundary_array(variant["inputs"], 64) {
        boundary_type(input, 0, budget)
      }
    }
  }
}

///|
fn policy_payload(
  operation : String,
  value : Json,
  expected_session : String?,
) -> Json raise {
  if operation == "session.open" || operation == "session.check" {
    return policy_descriptor_value(value, expected_session)
  }
  if operation != "execution.submit" {
    return payload(operation, value, expected_session)
  }
  let fields = closed(value, ["identity", "calls", "receipt", "plan"])
  let projection = closed(fields["plan"], [
    "profile", "contractVersion", "identity", "planId", "runtime", "evaluator", "admission",
    "boundary",
  ])
  guard projection["profile"] ==
    Json::string("morphir/workbench/execution-plan") &&
    projection["contractVersion"] == Json::string("0.2.0-draft.1") &&
    projection["runtime"] == Json::string("scheme") &&
    projection["evaluator"] ==
    Json::string("scheme-portable-v1/shared-sdk/bounded") else {
    raise Invalid("native.reply.shape")
  }
  ignore(@executions.Identity::from_json(projection["identity"]))
  guard projection["identity"] == fields["identity"] else {
    raise Invalid("native.reply.authority")
  }
  let plan_id = text(projection["planId"], 1, 128)
  guard plan_id.length() <= 128 else { raise Invalid("native.reply.shape") }
  policy_selection(projection["admission"])
  policy_boundary(projection["boundary"])
  ignore(
    payload(
      operation,
      {
        "identity": fields["identity"],
        "calls": fields["calls"],
        "receipt": fields["receipt"],
      },
      expected_session,
    ),
  )
  value
}

///|
/// Explicit mapping selection is mandatory because replies have no version field.
/// This never broadens the frozen default decoder.
pub fn decode_policy(
  bytes : Bytes,
  expected_operation : String,
  expected_session~ : String? = None,
) -> Reply raise Invalid {
  guard known(expected_operation) else {
    raise Invalid("native.reply.operation")
  }
  let value = parse(bytes)
  guard value is Object(fields) else { raise Invalid("native.reply.shape") }
  if fields.get("ok") != Some(Json::boolean(true)) {
    return decode(bytes, expected_operation, expected_session~)
  }
  ignore(closed(value, ["ok", "operation", "value"]))
  guard fields["operation"] == Json::string(expected_operation) else {
    raise Invalid("native.reply.operation")
  }
  if expected_operation == "workspace.choose" && bytes.length() > 524288 {
    raise Invalid("native.reply.limit")
  }
  fields["value"] = policy_payload(
    expected_operation,
    fields["value"],
    expected_session,
  ) catch {
    Invalid(code) => raise Invalid(code)
    _ => raise Invalid("native.reply.shape")
  }
  { envelope: value, effect: None, }
}

///|
pub fn success_policy(operation : String, value : Json) -> Bytes raise Invalid {
  let bytes = @utf8.encode(
    ({ "ok": true, "operation": operation, "value": value } : Json).stringify(),
  )
  ignore(decode_policy(bytes, operation))
  bytes
}

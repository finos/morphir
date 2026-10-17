///|
fn field_value(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn invalid_request(id : Json) -> Json {
  { "id": id, "status": "invalid", "code": "workbench.invalid_request" }
}

///|
fn closed(value : Json, names : Array[String]) -> Bool {
  value is Object(fields) &&
  fields.length() == names.length() &&
  fields.keys().all(name => names.contains(name))
}

///|
fn valid_id(value : Json) -> Bool {
  guard value is Number(number, ..) &&
    number >= 1 &&
    number <= 9007199254740991.0 &&
    number.floor() == number else {
    return false
  }
  ignore(@wire.integer_text(value)) catch {
    _ => return false
  }
  true
}

///|
/// Explicit offline witness only. Neither the historical MCK adapter nor a
/// browser/native/HTTP provider gains a capability-checking offer here.
pub fn handle_line(source : String) -> Json? {
  if @utf8.encode(source).length() > 2097152 {
    return Some(invalid_request(Json::null()))
  }
  let request = @wire.parse_bounded(source) catch {
    _ => return Some(invalid_request(Json::null()))
  }
  let id = field_value(request, "id")
  guard valid_id(id) else { return Some(invalid_request(id)) }
  if closed(request, ["id", "op"]) &&
    field_value(request, "op") == Json::string("exit") {
    return None
  }
  let capabilities = field_value(request, "op") == Json::string("capabilities")
  let fields = if capabilities {
    ["id", "op", "suite", "contractVersion"]
  } else {
    ["id", "op", "suite", "contractVersion", "format", "input"]
  }
  guard closed(request, fields) &&
    field_value(request, "suite") == Json::string("workbench") &&
    field_value(request, "contractVersion") == Json::string("0.1.0-draft.13") else {
    return Some(invalid_request(id))
  }
  if capabilities {
    return Some({
      "id": id,
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.13",
      "binding": "morphir-moonbit-capability-jobs",
      "language": "moonbit",
      "operations": ["run-capability-jobs"],
      "formats": ["json"],
    })
  }
  if field_value(request, "op") == Json::string("run-capability-jobs") &&
    field_value(request, "format") == Json::string("json") &&
    valid_input(field_value(request, "input")) {
    return Some({
      "id": id,
      "status": "ok",
      "value": observe(field_value(request, "input")),
    })
  }
  Some(invalid_request(id))
}

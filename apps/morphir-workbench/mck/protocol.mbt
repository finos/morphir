///|
fn invalid(id : Json, code : String) -> Json {
  { "id": id, "status": "invalid", "code": code }
}

///|
fn field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn valid_id(id : Json) -> Bool {
  id is Number(n, ..) && n >= 1 && n <= 9007199254740991.0 && n.floor() == n
}

///|
fn duplicate_members(value : @ion.IonValue) -> Bool {
  match value.kind() {
    Struct(fields) => {
      let seen = Map([])
      for item in fields {
        let name = item.name().text().unwrap_or("")
        if seen.contains(name) || duplicate_members(item.value()) {
          return true
        }
        seen[name] = true
      }
      false
    }
    List(items) => items.any(duplicate_members)
    _ => false
  }
}

///|
/// Core JSON validates grammar/depth. Ion retains member pairs so duplicates
/// cannot disappear during conversion to the core Json map. None means exit.
pub fn handle_line(source : String) -> Json? raise {
  let request = @json.parse(source)
  if duplicate_members(@text.read_ion(source[:])) {
    return Some(invalid(field(request, "id"), "workbench.invalid_request"))
  }
  if exit_requested(request) {
    None
  } else {
    Some(handle(request))
  }
}

///|
/// The shared MCK transport sends exit and expects EOF without a response.
pub fn exit_requested(request : Json) -> Bool {
  request is Object(fields) &&
  fields.length() == 2 &&
  valid_id(field(request, "id")) &&
  field(request, "op") == Json::string("exit")
}

///|
/// Implements the parent's exact draft codec and declaration observations.
/// These test claims do not advertise connected RPC or job execution.
pub fn handle(request : Json) -> Json {
  let id = field(request, "id")
  guard request is Object(fields) else {
    return invalid(id, "workbench.invalid_request")
  }
  guard valid_id(id) else { return invalid(id, "workbench.invalid_request") }
  let op = field(request, "op")
  let allowed = if op == Json::string("capabilities") {
    ["id", "op", "suite", "contractVersion"]
  } else {
    ["id", "op", "suite", "contractVersion", "format", "input"]
  }
  let version = field(request, "contractVersion")
  let draft6 = version == Json::string("0.1.0-draft.6")
  let draft2 = version == Json::string("0.1.0-draft.2")
  let draft3 = version == Json::string("0.1.0-draft.3")
  let draft5 = version == Json::string("0.1.0-draft.5")
  let draft4 = version == Json::string("0.1.0-draft.4") || draft5
  guard fields.length() == allowed.length() &&
    fields.keys().all(name => allowed.contains(name)) &&
    field(request, "suite") == Json::string("workbench") &&
    (
      version == Json::string("0.1.0-draft.1") ||
      draft2 ||
      draft3 ||
      draft4 ||
      draft6
    ) else {
    return invalid(id, "workbench.invalid_request")
  }
  if op == Json::string("capabilities") {
    return {
      "id": id,
      "suite": "workbench",
      "contractVersion": version,
      "binding": "morphir-moonbit",
      "language": "moonbit",
      "operations": if draft6 {
        ["reduce-job"]
      } else if draft5 {
        [
          "decode-value", "validate-value", "validate-invocations", "validate-output",
          "validate-outcomes",
        ]
      } else if draft4 {
        [
          "decode-value", "validate-value", "validate-invocations", "validate-output",
        ]
      } else if draft3 {
        ["decode-value", "validate-value", "validate-invocations"]
      } else if draft2 {
        ["decode-value", "validate-value"]
      } else {
        ["decode-value"]
      },
      "formats": if draft6 {
        ["json"]
      } else {
        ["json", "ion-text"]
      },
    }
  }
  guard (draft6 && op == Json::string("reduce-job")) ||
    (
      !draft6 &&
      (
        op == Json::string("decode-value") ||
        ((draft2 || draft3 || draft4) && op == Json::string("validate-value")) ||
        ((draft3 || draft4) && op == Json::string("validate-invocations")) ||
        (draft4 && op == Json::string("validate-output")) ||
        (draft5 && op == Json::string("validate-outcomes"))
      )
    ) else {
    return invalid(id, "workbench.invalid_request")
  }
  try {
    let input = field(request, "input")
    if (draft2 || draft3 || draft4 || draft6) &&
      @utf8.encode(input.stringify()).length() > 1024 * 1024 {
      return invalid(id, "workbench.input_limit")
    }
    let observation = if draft6 {
      reduce_job(input, field(request, "format"))
    } else if op == Json::string("validate-outcomes") {
      admit_outcomes(input, field(request, "format")).to_json()
    } else if op == Json::string("validate-invocations") {
      admit_invocations(input, field(request, "format")).to_json()
    } else {
      let value = if op == Json::string("validate-value") ||
        op == Json::string("validate-output") {
        admit_value(
          input,
          field(request, "format"),
          output=op == Json::string("validate-output"),
        )
      } else {
        decode_value(field(request, "format"), input)
      }
      value.to_json()
    }
    { "id": id, "status": "ok", "value": observation }
  } catch {
    @jobs.Invalid(code) => invalid(id, code)
    @execution.Invalid(code) => {
      // Legacy codec diagnostics append input paths/names after a colon.
      // The MCK observation carries only the bounded, stable rejection code.
      let stable = code.split(":").next().unwrap_or("workbench.codec_failure")
      invalid(id, stable.to_owned())
    }
    _ => invalid(id, "workbench.codec_failure")
  }
}

///|
fn decode_value(format : Json, input : Json) -> @execution.Value raise {
  match format {
    String("json") => @execution.Value::from_json(input)
    String("ion-text") => {
      guard input is String(source) else {
        raise @execution.Invalid("workbench.invalid_request")
      }
      let ion = @text.read_ion(source[:]) catch {
        _ => raise @execution.Invalid("workbench.invalid_ion")
      }
      @execution.Value::from_ion(ion)
    }
    _ => raise @execution.Invalid("workbench.invalid_request")
  }
}

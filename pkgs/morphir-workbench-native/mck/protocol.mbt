///|
fn field(value : Json, name : String) -> Json {
  guard value is Object(fields) && fields.get(name) is Some(value) else {
    abort("native owner MCK: missing fixture field")
  }
  value
}

///|
fn closed(value : Json, names : Array[String]) -> Map[String, Json] {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    names.all(name => fields.contains(name)) else {
    abort("native owner MCK: invalid fixture shape")
  }
  fields
}

///|
fn text(value : Json, maximum~ : Int32 = 128, token~ : Bool = false) -> String {
  guard value is String(value) &&
    value.iter().count() <= maximum &&
    (
      !token ||
      (
        !value.is_empty() &&
        value
        .iter()
        .all(c => {
          (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '_' ||
          c == '.' ||
          c == '-'
        })
      )
    ) else {
    abort("native owner MCK: invalid fixture text")
  }
  value
}

///|
fn array(value : Json, maximum : Int32) -> Array[Json] {
  guard value is Array(values) && values.length() <= maximum else {
    abort("native owner MCK: invalid fixture array")
  }
  values
}

///|
fn boolean(value : Json) -> Bool {
  match value {
    True => true
    False => false
    _ => abort("native owner MCK: invalid fixture boolean")
  }
}

///|
fn integer(value : Json, minimum : Int32, maximum : Int32) -> Int32 {
  guard value is Number(n, ..) &&
    n >= minimum.to_double() &&
    n <= maximum.to_double() &&
    @wire.is_integral_number(value) else {
    abort("native owner MCK: invalid fixture integer")
  }
  n.to_int()
}

///|
fn optional_text(value : Json, maximum~ : Int32 = 128) -> String? {
  if value == Json::null() {
    None
  } else {
    Some(text(value, maximum~))
  }
}

///|
/// Canonicalize structure only. Strings containing model, input and checkpoint
/// sources remain opaque, including their whitespace and identity-like text.
fn canonical(value : Json) -> String {
  let source = match value {
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort_by(String::lexical_compare)
      "{" +
      keys
      .map(key => Json::string(key).stringify() + ":" + canonical(fields[key]))
      .join(",") +
      "}"
    }
    Array(values) => "[" + values.map(canonical).join(",") + "]"
    _ => value.stringify()
  }
  guard @utf8.encode(source).length() <= 1048576 else {
    abort("native owner MCK: projection exceeds 1 MiB")
  }
  source
}

///|
fn caller(context : Json) -> @session.Caller raise {
  @session.Caller::admit(
    text(field(context, "window")),
    text(field(context, "origin")),
    optional_text(field(context, "page"), maximum=256),
  )
}

///|
pub async fn handle_line(source : String) -> Json? {
  guard @utf8.encode(source).length() <= 2097152 else {
    abort("native owner MCK: input line exceeds 2 MiB")
  }
  // The production literal parser rejects duplicate members before conversion.
  let request = @wire.parse(source)
  if field(request, "op") == Json::string("exit") {
    guard request is Object(fields) else { abort("native owner MCK: exit") }
    ignore(
      closed(request, if fields.contains("id") { ["id", "op"] } else { ["op"] }),
    )
    if fields.contains("id") {
      guard fields["id"] is Number(n, ..) &&
        n >= 1 &&
        n <= 9007199254740991.0 &&
        @wire.is_integral_number(fields["id"]) else {
        abort("native owner MCK: exit id")
      }
    }
    return None
  }
  let capability = field(request, "op") == Json::string("capabilities")
  ignore(
    closed(
      request,
      if capability {
        ["id", "op", "suite", "contractVersion"]
      } else {
        ["id", "op", "suite", "contractVersion", "format", "input"]
      },
    ),
  )
  let id = field(request, "id")
  guard id is Number(n, ..) &&
    n >= 1 &&
    n <= 9007199254740991.0 &&
    @wire.is_integral_number(id) &&
    field(request, "suite") == Json::string("workbench") &&
    field(request, "contractVersion") == Json::string("0.1.0-draft.10") else {
    abort("native owner MCK: invalid negotiation")
  }
  if capability {
    return Some({
      "id": id,
      "suite": "workbench",
      "contractVersion": "0.1.0-draft.10",
      "binding": "morphir-moonbit-native-owner",
      "language": "moonbit",
      "operations": ["run-native-owner"],
      "formats": ["json"],
    })
  }
  guard field(request, "op") == Json::string("run-native-owner") &&
    field(request, "format") == Json::string("json") else {
    abort("native owner MCK: unsupported operation")
  }
  let value = run_owner(field(request, "input"))
  Some({ "id": id, "status": "ok", "value": value })
}

///|
async fn run_owner(input : Json) -> Json {
  admit_input(input)
  let observation = Ref(Json::null())
  @async.with_task_group(async fn(group) {
    let runtime = Runtime::new(group, input)
    let jobs : ((String) -> @bridge.JobsService raise)? = if field(
        field(input, "services"),
        "jobs",
      ) ==
      Json::string("disabled") {
      None
    } else {
      Some(fn(session) raise { runtime.jobs(session) })
    }
    let workspace : (() -> @workspace.Service)? = if boolean(
        field(field(input, "services"), "workspace"),
      ) {
      Some(fn() { runtime.workspace() })
    } else {
      None
    }
    let owner = @bridge.Owner::with_services(group, { jobs, workspace, })
    observation.val = runtime.execute(owner)
  })
  observation.val
}

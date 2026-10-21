///|
/// Independent offline workspace-file witness. Historical workbench MCK draft
/// mappings and live native authority retain their own contracts.
pub const SUITE : String = "workbench-workspace-files"

///|
pub const VERSION : String = "0.1.0-draft.1"

///|
fn field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn closed(value : Json, keys : Array[String]) -> Bool {
  value is Object(fields) &&
  fields.length() == keys.length() &&
  keys.all(key => fields.contains(key))
}

///|
fn invalid(id : Json, code : String) -> Json {
  { "id": id, "status": "invalid", "code": code }
}

///|
fn source(value : Json) -> Bytes raise {
  guard closed(value, ["encoding", "source"]) &&
    field(value, "source") is String(text) else {
    raise @files.Invalid("workspace_files.fixture")
  }
  match field(value, "encoding") {
    String("utf8") => @utf8.encode(text)
    String("base64") => {
      let bytes = @base64.decode(text) catch {
        _ => raise @files.Invalid("workspace_files.fixture")
      }
      if @base64.encode(bytes[:]) != text {
        raise @files.Invalid("workspace_files.fixture")
      }
      bytes
    }
    _ => raise @files.Invalid("workspace_files.fixture")
  }
}

///|
fn observe(operation : String, input : Json) -> Json raise {
  match operation {
    "validate-request" => {
      let request = @files.decode_request(source(input))
      { "accepted": true, "operation": request.operation() }
    }
    "validate-reply" => {
      guard closed(input, ["request", "reply"]) else {
        raise @files.Invalid("workspace_files.fixture")
      }
      let request = @files.decode_request(source(field(input, "request")))
      ignore(@files.decode_reply(request, source(field(input, "reply"))))
      { "accepted": true, "operation": request.operation() }
    }
    "observe-file-edit" => {
      guard closed(input, ["baseline", "candidate", "directories"]) &&
        field(input, "directories") is Array(values) else {
        raise @files.Invalid("workspace_files.fixture")
      }
      let directories = values.map(value => {
        guard value is String(path) else {
          raise @files.Invalid("workspace_files.fixture")
        }
        path
      })
      let baseline = @files.Inventory::decode(source(field(input, "baseline")))
      let candidate = @files.Inventory::decode(
        source(field(input, "candidate")),
      )
      let change = baseline.difference(candidate, directories)
      {
        "writes": Json::object(
          change.writes.map(fn(_, bytes) {
            Json::string(@base64.encode(bytes[:]))
          }),
        ),
        "deletes": Json::array(change.deletes.map(Json::string)),
        "createDirectories": Json::array(
          change.create_directories.map(Json::string),
        ),
        "removeDirectories": Json::array(
          change.remove_directories.map(Json::string),
        ),
      }
    }
    _ => raise @files.Invalid("workspace_files.fixture")
  }
}

///|
pub fn handle_line(line : String) -> Json? {
  if @utf8.encode(line).length() > 2097152 {
    return Some(invalid(Json::null(), "workspace_files.fixture_limit"))
  }
  let request = @wire.parse_bounded(
    line,
    max_depth=16,
    max_nodes=32000,
    max_string_units=2097152,
  ) catch {
    _ => return Some(invalid(Json::null(), "workspace_files.fixture"))
  }
  let id = field(request, "id")
  guard id is Number(n, ..) &&
    n >= 1 &&
    n <= 9007199254740991.0 &&
    @wire.is_integral_number(id) else {
    return Some(invalid(id, "workspace_files.fixture"))
  }
  let operation = field(request, "op")
  if closed(request, ["id", "op"]) && operation == Json::string("exit") {
    return None
  }
  let capabilities = operation == Json::string("capabilities")
  guard closed(
      request,
      if capabilities {
        ["id", "op", "suite", "contractVersion"]
      } else {
        ["id", "op", "suite", "contractVersion", "format", "input"]
      },
    ) &&
    field(request, "suite") == Json::string(SUITE) &&
    field(request, "contractVersion") == Json::string(VERSION) else {
    return Some(invalid(id, "workspace_files.fixture"))
  }
  if capabilities {
    return Some({
      "id": id,
      "suite": SUITE,
      "contractVersion": VERSION,
      "binding": "morphir-moonbit-workspace-files",
      "language": "moonbit",
      "operations": ["validate-request", "validate-reply", "observe-file-edit"],
      "formats": ["json"],
    })
  }
  guard operation is String(operation) &&
    ["validate-request", "validate-reply", "observe-file-edit"].contains(
      operation,
    ) &&
    field(request, "format") == Json::string("json") else {
    return Some(invalid(id, "workspace_files.fixture"))
  }
  Some(
    {
      "id": id,
      "status": "ok",
      "value": observe(operation, field(request, "input")),
    } catch {
      @files.Invalid(code) => invalid(id, code)
      _ => invalid(id, "workspace_files.fixture")
    },
  )
}

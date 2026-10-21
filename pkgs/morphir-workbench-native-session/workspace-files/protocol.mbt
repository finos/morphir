///|
/// A separate page-bound file capability. Existing native execution and
/// read-only workspace contracts retain their exact versions and shapes.
pub const PROFILE : String = "morphir/workbench/workspace-files"

///|
pub const VERSION : String = "0.1.0-draft.1"

///|
pub const FRAME_LIMIT : Int32 = 1048576

///|
pub const CHUNK_LIMIT : Int32 = 196608

///|
pub const TRANSFER_LIMIT : Int32 = 25165824

///|
/// File frames are JSON strings inside connected JSON-RPC. Account for string
/// escaping and the separately bounded source/provider binding metadata.
pub const CONNECTED_FRAME_LIMIT : Int32 = 2162688

///|
pub(all) suberror Invalid {
  Invalid(String)
}

///|
pub struct SessionId(String) derive(Eq)

///|
pub struct GrantId(String) derive(Eq)

///|
pub extend SessionId with Eq::{equal, not_equal}

///|
pub extend GrantId with Eq::{equal, not_equal}

///|
fn valid_id(text : String) -> Bool {
  text.length() >= 1 &&
  text.length() <= 128 &&
  text
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-' ||
    c == '.'
  })
}

///|
pub fn SessionId::parse(text : String) -> SessionId raise Invalid {
  if !valid_id(text) {
    raise Invalid("workspace_files.id")
  }
  SessionId(text)
}

///|
pub fn GrantId::parse(text : String) -> GrantId raise Invalid {
  if !valid_id(text) {
    raise Invalid("workspace_files.id")
  }
  GrantId(text)
}

///|
pub fn SessionId::to_string(self : SessionId) -> String {
  let SessionId(text) = self
  text
}

///|
pub fn GrantId::to_string(self : GrantId) -> String {
  let GrantId(text) = self
  text
}

///|
pub(all) enum Command {
  CheckSession
  CloseSession
  ChooseWrite
  CancelPicker
  Snapshot(GrantId, Int32)
  Read(GrantId, Int32, Int32)
  BeginEdit(GrantId, Int32, Int32, Int32)
  Write(GrantId, Int32, Int32, Bytes)
  Commit(GrantId, Int32)
  Status(GrantId, Int32)
  Release(GrantId, Int32)
  Revoke(GrantId)
}

///|
pub enum Request {
  OpenSession
  Bound(SessionId, Command)
}

///|
pub fn Request::session_id(self : Request) -> SessionId? {
  match self {
    OpenSession => None
    Bound(id, _) => Some(id)
  }
}

///|
pub fn Request::command(self : Request) -> Command? {
  match self {
    OpenSession => None
    Bound(_, command) => Some(command)
  }
}

///|
pub fn Request::operation(self : Request) -> String {
  match self {
    OpenSession => "session.open"
    Bound(_, command) =>
      match command {
        CheckSession => "session.check"
        CloseSession => "session.close"
        ChooseWrite => "workspace.choose-write"
        CancelPicker => "workspace.cancel-picker"
        Snapshot(_, _) => "workspace.snapshot"
        Read(_, _, _) => "workspace.read"
        BeginEdit(_, _, _, _) => "workspace.begin-edit"
        Write(_, _, _, _) => "workspace.write"
        Commit(_, _) => "workspace.commit"
        Status(_, _) => "workspace.status"
        Release(_, _) => "workspace.release"
        Revoke(_) => "workspace.revoke"
      }
  }
}

///|
fn closed(
  value : Json,
  names : Array[String],
) -> Map[String, Json] raise Invalid {
  guard value is Object(fields) &&
    fields.length() == names.length() &&
    names.all(name => fields.contains(name)) else {
    raise Invalid("workspace_files.shape")
  }
  fields
}

///|
fn text(value : Json, limit : Int32) -> String raise Invalid {
  guard value is String(text) && text.length() <= limit else {
    raise Invalid("workspace_files.shape")
  }
  text
}

///|
fn integer(
  value : Json,
  minimum : Int32,
  maximum : Int32,
) -> Int32 raise Invalid {
  guard value is Number(n, ..) &&
    n >= minimum.to_double() &&
    n <= maximum.to_double() &&
    @wire.is_integral_number(value) else {
    raise Invalid("workspace_files.shape")
  }
  n.to_int()
}

///|
fn chunk(value : Json) -> Bytes raise Invalid {
  let encoded = text(value, CHUNK_LIMIT / 3 * 4)
  let bytes = @base64.decode(encoded) catch {
    _ => raise Invalid("workspace_files.shape")
  }
  if bytes.length() > CHUNK_LIMIT || @base64.encode(bytes[:]) != encoded {
    raise Invalid("workspace_files.shape")
  }
  bytes
}

///|
fn parse(bytes : Bytes) -> Json raise Invalid {
  if bytes.length() > FRAME_LIMIT {
    raise Invalid("workspace_files.limit")
  }
  let source = @utf8.decode(bytes, ignore_bom=false) catch {
    _ => raise Invalid("workspace_files.utf8")
  }
  @wire.parse_bounded(
    source,
    max_depth=16,
    max_nodes=1024,
    max_string_units=FRAME_LIMIT,
  ) catch {
    _ => raise Invalid("workspace_files.json")
  }
}

///|
pub fn decode_request(bytes : Bytes) -> Request raise Invalid {
  let value = parse(bytes)
  guard value is Object(fields) &&
    fields.get("profile") == Some(Json::string(PROFILE)) &&
    fields.get("contractVersion") == Some(Json::string(VERSION)) else {
    raise Invalid("workspace_files.profile")
  }
  let operation = text(fields.get("operation").unwrap_or(Json::null()), 64)
  if operation == "session.open" {
    ignore(closed(value, ["profile", "contractVersion", "operation"]))
    return OpenSession
  }
  let no_payload = [
    "session.check", "session.close", "workspace.choose-write", "workspace.cancel-picker",
  ].contains(operation)
  ignore(
    closed(
      value,
      if no_payload {
        ["profile", "contractVersion", "operation", "sessionId"]
      } else {
        ["profile", "contractVersion", "operation", "sessionId", "payload"]
      },
    ),
  )
  let session = SessionId::parse(text(fields["sessionId"], 128))
  if no_payload {
    return Bound(
      session,
      match operation {
        "session.check" => CheckSession
        "session.close" => CloseSession
        "workspace.choose-write" => ChooseWrite
        _ => CancelPicker
      },
    )
  }
  let payload = fields["payload"]
  let names = match operation {
    "workspace.snapshot"
    | "workspace.commit"
    | "workspace.status"
    | "workspace.release" => ["grantId", "sequence"]
    "workspace.read" => ["grantId", "sequence", "offset"]
    "workspace.begin-edit" => ["grantId", "sequence", "baseRevision", "size"]
    "workspace.write" => ["grantId", "sequence", "offset", "content"]
    "workspace.revoke" => ["grantId"]
    _ => raise Invalid("workspace_files.operation")
  }
  let fields = closed(payload, names)
  let grant = GrantId::parse(text(fields["grantId"], 128))
  if operation == "workspace.revoke" {
    return Bound(session, Revoke(grant))
  }
  let sequence = integer(fields["sequence"], 1, 2147483647)
  Bound(
    session,
    match operation {
      "workspace.snapshot" => Snapshot(grant, sequence)
      "workspace.read" =>
        Read(grant, sequence, integer(fields["offset"], 0, TRANSFER_LIMIT))
      "workspace.begin-edit" =>
        BeginEdit(
          grant,
          sequence,
          integer(fields["baseRevision"], 0, 2147483647),
          integer(fields["size"], 1, TRANSFER_LIMIT),
        )
      "workspace.write" => {
        let bytes = chunk(fields["content"])
        if bytes.is_empty() {
          raise Invalid("workspace_files.shape")
        }
        Write(
          grant,
          sequence,
          integer(fields["offset"], 0, TRANSFER_LIMIT - bytes.length()),
          bytes,
        )
      }
      "workspace.commit" => Commit(grant, sequence)
      "workspace.status" => Status(grant, sequence)
      _ => Release(grant, sequence)
    },
  )
}

///|
/// Descriptor claims support only; a successful explicit picker supplies the
/// grant used by file requests. No pathname is accepted from the renderer.
pub fn descriptor() -> Json {
  {
    "features": ["read", "write", "directories"],
    "limits": {
      "files": 2000,
      "contentBytes": 16777216,
      "frameBytes": FRAME_LIMIT,
      "chunkBytes": CHUNK_LIMIT,
      "transferBytes": TRANSFER_LIMIT,
      "grants": 8,
      "directories": 256,
      "pathDepth": 16,
    },
  }
}

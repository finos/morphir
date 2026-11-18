///|
#derive(Eq, Debug)
pub(all) enum ReadRequest {
  Inventory(
    request_id~ : String,
    selection~ : String,
    page_size~ : Int32,
    cursor~ : String?
  )
  Document(request_id~ : String, document_id~ : String)
}

///|
pub extend ReadRequest with Eq::{equal, not_equal}

///|
pub extend ReadRequest with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub struct ArtifactChunk {
  path : String
  offset : Int64
  decoded_byte_length : Int32
  sha256 : String
  content : String
  final_chunk : Bool
}

///|
pub extend ArtifactChunk with Eq::{equal, not_equal}

///|
pub extend ArtifactChunk with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum GenerationStep {
  Continue(
    session_id~ : String,
    round~ : Int32,
    requests~ : Array[ReadRequest],
    artifacts~ : Array[ArtifactChunk],
    diagnostics~ : Array[Json]
  )
  Complete(
    session_id~ : String,
    artifacts~ : Array[ArtifactChunk],
    diagnostics~ : Array[Json]
  )
  Failed(
    session_id~ : String,
    first_diagnostic~ : Json,
    other_diagnostics~ : Array[Json]
  )
}

///|
pub extend GenerationStep with Eq::{equal, not_equal}

///|
pub extend GenerationStep with @debug.Debug::{to_repr}

///|
pub fn ReadRequest::request_id(self : ReadRequest) -> String {
  match self {
    Inventory(request_id~, ..) | Document(request_id~, ..) => request_id
  }
}

///|
pub fn ReadRequest::from_json(
  value : Json,
) -> ReadRequest raise @wire.CodecError {
  let request_id = field_identity(value, "requestId")
  match field_text(value, "kind") {
    "inventory" => {
      forbid_fields(value, ["documentId"])
      let selection = field_identity(value, "selection")
      let page_size = field_integer(value, "pageSize", min=1L, max=2147483647L).to_int()
      let cursor = match @wire.optional(value, "cursor") {
        Some(_) => Some(field_identity(value, "cursor"))
        None => None
      }
      Inventory(request_id~, selection~, page_size~, cursor~)
    }
    "document" => {
      forbid_fields(value, ["selection", "pageSize", "cursor"])
      Document(request_id~, document_id=field_identity(value, "documentId"))
    }
    other => raise @wire.Invalid("model_access.invalid_request_kind", other)
  }
}

///|
pub fn ReadRequest::to_json(self : ReadRequest) -> Json {
  match self {
    Inventory(request_id~, selection~, page_size~, cursor~) => {
      let fields : Map[String, Json] = {
        "kind": "inventory",
        "requestId": request_id,
        "selection": selection,
        "pageSize": page_size,
      }
      if cursor is Some(cursor) {
        fields["cursor"] = Json::string(cursor)
      }
      Json::object(fields)
    }
    Document(request_id~, document_id~) =>
      { "kind": "document", "requestId": request_id, "documentId": document_id }
  }
}

///|
/// Reads the chunk's wire fields. The output stage verifies its decoded bytes,
/// digest, confined path and position before accepting the chunk.
pub fn ArtifactChunk::from_json(
  value : Json,
) -> ArtifactChunk raise @wire.CodecError {
  let sha256 = field_digest(value, "sha256")
  let final_chunk = match @wire.field(value, "end") {
    True => true
    False => false
    _ => raise @wire.Invalid("model_access.invalid_chunk", "end")
  }
  {
    path: field_identity(value, "path"),
    offset: field_integer(value, "offset", min=0L, max=9007199254740991L),
    decoded_byte_length: field_integer(
      value,
      "decodedByteLength",
      min=0L,
      max=2147483647L,
    ).to_int(),
    sha256,
    content: field_text(value, "content"),
    final_chunk,
  }
}

///|
pub fn ArtifactChunk::to_json(self : ArtifactChunk) -> Json {
  {
    "path": self.path,
    "offset": integer_json(self.offset),
    "decodedByteLength": self.decoded_byte_length,
    "sha256": self.sha256,
    "content": self.content,
    "end": self.final_chunk,
  }
}

///|
pub fn GenerationStep::session_id(self : GenerationStep) -> String {
  match self {
    Continue(session_id~, ..)
    | Complete(session_id~, ..)
    | Failed(session_id~, ..) => session_id
  }
}

///|
pub fn GenerationStep::diagnostics(self : GenerationStep) -> Array[Json] {
  match self {
    Continue(diagnostics~, ..) | Complete(diagnostics~, ..) => [..diagnostics]
    Failed(first_diagnostic~, other_diagnostics~, ..) =>
      [first_diagnostic, ..other_diagnostics]
  }
}

///|
fn validate_diagnostic_location(location : Json) -> Unit raise @wire.CodecError {
  ignore(field_text(location, "uri"))
  let range = @wire.field(location, "range")
  for endpoint in ["start", "end"] {
    let position = @wire.field(range, endpoint)
    for coordinate in ["line", "character"] {
      guard @wire.field(position, coordinate) is Number(value, ..) &&
        value >= 0.0 &&
        value <= 4294967295.0 &&
        value == value.floor() else {
        raise @wire.Invalid("model_access.invalid_diagnostic", coordinate)
      }
    }
  }
}

///|
/// Checks the result sum and its wire fields. The session validates ordering,
/// request ownership and resource limits against the active operation.
pub fn GenerationStep::from_json(
  value : Json,
) -> GenerationStep raise @wire.CodecError {
  let session_id = field_identity(value, "sessionId")
  let diagnostics = @wire.array(@wire.field(value, "diagnostics")).map(item => {
    guard ["error", "warning", "info", "hint"].contains(
      field_text(item, "severity"),
    ) else {
      raise @wire.Invalid("model_access.invalid_diagnostic", "severity")
    }
    ignore(field_text(item, "message"))
    if @wire.optional(item, "code") is Some(code) {
      ignore(@wire.string(code))
    }
    if @wire.optional(item, "location") is Some(location) {
      validate_diagnostic_location(location)
    }
    if @wire.optional(item, "related") is Some(related) {
      for entry in @wire.array(related) {
        validate_diagnostic_location(@wire.field(entry, "location"))
        ignore(field_text(entry, "message"))
      }
    }
    item
  })
  match field_text(value, "state") {
    "continue" => {
      let round = field_integer(value, "round", min=1L, max=2147483647L).to_int()
      let requests = @wire.array(@wire.field(value, "requests")).map(
        ReadRequest::from_json,
      )
      let artifacts = @wire.array(@wire.field(value, "artifacts")).map(
        ArtifactChunk::from_json,
      )
      Continue(session_id~, round~, requests~, artifacts~, diagnostics~)
    }
    "complete" => {
      forbid_fields(value, ["round", "requests"])
      let artifacts = @wire.array(@wire.field(value, "artifacts")).map(
        ArtifactChunk::from_json,
      )
      Complete(session_id~, artifacts~, diagnostics~)
    }
    "failed" => {
      forbid_fields(value, ["round", "requests", "artifacts"])
      guard diagnostics is [first_diagnostic, .. other_diagnostics] else {
        raise @wire.Invalid(
          "model_access.invalid_diagnostic", "failed requires a diagnostic",
        )
      }
      Failed(
        session_id~,
        first_diagnostic~,
        other_diagnostics=other_diagnostics.to_owned(),
      )
    }
    other => raise @wire.Invalid("model_access.invalid_step", other)
  }
}

///|
pub fn GenerationStep::to_json(self : GenerationStep) -> Json {
  match self {
    Continue(session_id~, round~, requests~, artifacts~, diagnostics~) =>
      {
        "state": "continue",
        "sessionId": session_id,
        "round": round,
        "requests": requests.map(ReadRequest::to_json),
        "artifacts": artifacts.map(ArtifactChunk::to_json),
        "diagnostics": diagnostics,
      }
    Complete(session_id~, artifacts~, diagnostics~) =>
      {
        "state": "complete",
        "sessionId": session_id,
        "artifacts": artifacts.map(ArtifactChunk::to_json),
        "diagnostics": diagnostics,
      }
    Failed(session_id~, first_diagnostic~, other_diagnostics~) =>
      {
        "state": "failed",
        "sessionId": session_id,
        "diagnostics": [first_diagnostic, ..other_diagnostics],
      }
  }
}

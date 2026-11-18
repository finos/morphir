///|
/// Identities for the selected snapshot. They carry no filesystem authority.
#derive(Eq, Debug)
pub struct Snapshot {
  snapshot_id : String
  model_id : String
  revision : String
  context_digest : String
  scope : String
}

///|
pub extend Snapshot with Eq::{equal, not_equal}

///|
pub extend Snapshot with @debug.Debug::{to_repr}

///|
fn Snapshot::from_json(value : Json) -> Snapshot raise @wire.CodecError {
  {
    snapshot_id: field_identity(value, "snapshotId"),
    model_id: field_identity(value, "modelId"),
    revision: field_identity(value, "revision"),
    context_digest: field_digest(value, "contextDigest"),
    scope: field_identity(value, "scope"),
  }
}

///|
fn Snapshot::to_json(self : Snapshot) -> Json {
  {
    "snapshotId": self.snapshot_id,
    "modelId": self.model_id,
    "revision": self.revision,
    "contextDigest": self.context_digest,
    "scope": self.scope,
  }
}

///|
#derive(Eq, Debug)
pub struct GuaranteeRequirement {
  guarantee : String
  scope : String
}

///|
pub extend GuaranteeRequirement with Eq::{equal, not_equal}

///|
pub extend GuaranteeRequirement with @debug.Debug::{to_repr}

///|
fn GuaranteeRequirement::from_json(
  value : Json,
) -> GuaranteeRequirement raise @wire.CodecError {
  {
    guarantee: field_identity(value, "guarantee"),
    scope: field_identity(value, "scope"),
  }
}

///|
fn GuaranteeRequirement::to_json(self : GuaranteeRequirement) -> Json {
  { "guarantee": self.guarantee, "scope": self.scope }
}

///|
#derive(Eq, Debug)
pub struct Start {
  session_id : String
  snapshot : Snapshot
  input : AccessTuple
  target : String
  options : Json
  required_guarantees : Array[GuaranteeRequirement]
  limits : Limits
}

///|
pub extend Start with Eq::{equal, not_equal}

///|
pub extend Start with @debug.Debug::{to_repr}

///|
pub fn Start::from_json(value : Json) -> Start raise @wire.CodecError {
  {
    session_id: field_identity(value, "sessionId"),
    snapshot: Snapshot::from_json(@wire.field(value, "snapshot")),
    input: AccessTuple::from_json(@wire.field(value, "input")),
    target: field_identity(value, "target"),
    options: @wire.field(value, "options"),
    required_guarantees: @wire.array(@wire.field(value, "requiredGuarantees")).map(item => {
        GuaranteeRequirement::from_json(item)
      },
    ),
    limits: Limits::from_json(@wire.field(value, "limits")),
  }
}

///|
pub fn Start::to_json(self : Start) -> Json {
  {
    "sessionId": self.session_id,
    "snapshot": self.snapshot.to_json(),
    "input": self.input.to_json(),
    "target": self.target,
    "options": self.options,
    "requiredGuarantees": self.required_guarantees.map(item => item.to_json()),
    "limits": self.limits.to_json(),
  }
}

///|
#derive(Eq, Debug)
pub(all) enum InventoryRole {
  Definition
  Specification
}

///|
pub extend InventoryRole with Eq::{equal, not_equal}

///|
pub extend InventoryRole with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub struct InventoryIdentity {
  document_id : String
  package_name : String
  module_path : String
  role : InventoryRole
}

///|
pub extend InventoryIdentity with Eq::{equal, not_equal}

///|
pub extend InventoryIdentity with @debug.Debug::{to_repr}

///|
fn InventoryIdentity::from_json(
  value : Json,
) -> InventoryIdentity raise @wire.CodecError {
  let role = match field_identity(value, "role") {
    "definition" => Definition
    "specification" => Specification
    other => raise @wire.Invalid("model_access.invalid_inventory_role", other)
  }
  {
    document_id: field_identity(value, "documentId"),
    package_name: field_identity(value, "packageName"),
    module_path: field_identity(value, "modulePath"),
    role,
  }
}

///|
fn InventoryIdentity::fields(self : InventoryIdentity) -> Map[String, Json] {
  {
    "documentId": Json::string(self.document_id),
    "packageName": Json::string(self.package_name),
    "modulePath": Json::string(self.module_path),
    "role": Json::string(
      match self.role {
        Definition => "definition"
        Specification => "specification"
      },
    ),
  }
}

///|
/// The entry tag determines whether the payload carries a name or a selection.
#derive(Eq, Debug)
pub enum InventoryEntry {
  Module(InventoryIdentity, member_selection~ : String?)
  Type(InventoryIdentity, name~ : String)
  Value(InventoryIdentity, name~ : String)
}

///|
pub extend InventoryEntry with Eq::{equal, not_equal}

///|
pub extend InventoryEntry with @debug.Debug::{to_repr}

///|
fn InventoryEntry::from_json(
  value : Json,
) -> InventoryEntry raise @wire.CodecError {
  let fields = @wire.object(value)
  guard fields.length() == 1 else {
    raise @wire.Invalid(
      "model_access.invalid_variant", "Inventory entry needs exactly one tag",
    )
  }
  match (fields.get("module"), fields.get("type"), fields.get("value")) {
    (Some(payload), _, _) => {
      forbid_fields(payload, ["name"])
      Module(
        InventoryIdentity::from_json(payload),
        member_selection=field_optional_identity(payload, "memberSelection"),
      )
    }
    (_, Some(payload), _) => {
      forbid_fields(payload, ["memberSelection"])
      Type(
        InventoryIdentity::from_json(payload),
        name=field_identity(payload, "name"),
      )
    }
    (_, _, Some(payload)) => {
      forbid_fields(payload, ["memberSelection"])
      Value(
        InventoryIdentity::from_json(payload),
        name=field_identity(payload, "name"),
      )
    }
    _ =>
      raise @wire.Invalid(
        "model_access.invalid_variant", "Unknown inventory tag",
      )
  }
}

///|
fn InventoryEntry::to_json(self : InventoryEntry) -> Json {
  let (tag, identity, name, selection) = match self {
    Module(identity, member_selection~) =>
      ("module", identity, None, member_selection)
    Type(identity, name~) => ("type", identity, Some(name), None)
    Value(identity, name~) => ("value", identity, Some(name), None)
  }
  let fields = identity.fields()
  if name is Some(text) {
    fields["name"] = Json::string(text)
  }
  if selection is Some(text) {
    fields["memberSelection"] = Json::string(text)
  }
  @wire.tag(tag, Json::object(fields))
}

///|
#derive(Eq, Debug)
pub struct InventoryDelivery {
  request_id : String
  snapshot_id : String
  entries : Array[InventoryEntry]
  next_cursor : String?
}

///|
pub extend InventoryDelivery with Eq::{equal, not_equal}

///|
pub extend InventoryDelivery with @debug.Debug::{to_repr}

///|
/// Carries the declared length, digest and encoded content. Byte budgets and
/// content integrity belong to the receiving exchange.
#derive(Eq, Debug)
pub struct DocumentDelivery {
  request_id : String
  snapshot_id : String
  document_id : String
  decoded_byte_length : Int32
  sha256 : String
  content : String
}

///|
pub extend DocumentDelivery with Eq::{equal, not_equal}

///|
pub extend DocumentDelivery with @debug.Debug::{to_repr}

///|
#derive(Eq, Debug)
pub enum Delivery {
  Inventory(InventoryDelivery)
  Document(DocumentDelivery)
}

///|
pub extend Delivery with Eq::{equal, not_equal}

///|
pub extend Delivery with @debug.Debug::{to_repr}

///|
pub fn Delivery::from_json(value : Json) -> Delivery raise @wire.CodecError {
  let request_id = field_identity(value, "requestId")
  let snapshot_id = field_identity(value, "snapshotId")
  match field_identity(value, "kind") {
    "inventory" => {
      forbid_fields(value, [
        "documentId", "decodedByteLength", "sha256", "content",
      ])
      Inventory({
        request_id,
        snapshot_id,
        entries: @wire.array(@wire.field(value, "entries")).map(item => {
          InventoryEntry::from_json(item)
        }),
        next_cursor: field_optional_identity(value, "nextCursor"),
      })
    }
    "document" => {
      forbid_fields(value, ["entries", "nextCursor"])
      Document({
        request_id,
        snapshot_id,
        document_id: field_identity(value, "documentId"),
        decoded_byte_length: field_int32(value, "decodedByteLength", 0L),
        sha256: field_digest(value, "sha256"),
        content: @wire.string(@wire.field(value, "content")),
      })
    }
    other => raise @wire.Invalid("model_access.invalid_variant", other)
  }
}

///|
pub fn Delivery::request_id(self : Delivery) -> String {
  match self {
    Inventory(page) => page.request_id
    Document(document) => document.request_id
  }
}

///|
pub fn Delivery::snapshot_id(self : Delivery) -> String {
  match self {
    Inventory(page) => page.snapshot_id
    Document(document) => document.snapshot_id
  }
}

///|
pub fn Delivery::document_id(self : Delivery) -> String? {
  match self {
    Inventory(_) => None
    Document(document) => Some(document.document_id)
  }
}

///|
pub fn Delivery::to_json(self : Delivery) -> Json {
  match self {
    Inventory(page) => {
      let fields : Map[String, Json] = {
        "requestId": Json::string(page.request_id),
        "kind": Json::string("inventory"),
        "snapshotId": Json::string(page.snapshot_id),
        "entries": Json::array(page.entries.map(entry => entry.to_json())),
      }
      if page.next_cursor is Some(cursor) {
        fields["nextCursor"] = Json::string(cursor)
      }
      Json::object(fields)
    }
    Document(document) =>
      {
        "requestId": document.request_id,
        "kind": "document",
        "snapshotId": document.snapshot_id,
        "documentId": document.document_id,
        "decodedByteLength": document.decoded_byte_length,
        "sha256": document.sha256,
        "content": document.content,
      }
  }
}

///|
#derive(Eq, Debug)
pub struct Advance {
  session_id : String
  round : Int32
  deliveries : Array[Delivery]
}

///|
pub extend Advance with Eq::{equal, not_equal}

///|
pub extend Advance with @debug.Debug::{to_repr}

///|
pub fn Advance::from_json(value : Json) -> Advance raise @wire.CodecError {
  {
    session_id: field_identity(value, "sessionId"),
    round: field_int32(value, "round", 1L),
    deliveries: @wire.array(@wire.field(value, "deliveries")).map(item => {
      Delivery::from_json(item)
    }),
  }
}

///|
pub fn Advance::to_json(self : Advance) -> Json {
  {
    "sessionId": self.session_id,
    "round": self.round,
    "deliveries": self.deliveries.map(delivery => delivery.to_json()),
  }
}

///|
#derive(Eq, Debug)
pub struct Cancel {
  session_id : String
}

///|
pub extend Cancel with Eq::{equal, not_equal}

///|
pub extend Cancel with @debug.Debug::{to_repr}

///|
pub fn Cancel::from_json(value : Json) -> Cancel raise @wire.CodecError {
  { session_id: field_identity(value, "sessionId"), }
}

///|
pub fn Cancel::to_json(self : Cancel) -> Json {
  { "sessionId": self.session_id }
}

///|
/// Failure at the native document-tree boundary.
pub(all) suberror TreeGenerationError {
  TreeSource(String)
  TreeOutput(String)
  TreeGuest(String)
  TreeUnsuccessful
  TreeWorker(Ending)
  TreeExpired
  TreeInterrupted
}

///|
pub struct TreeGeneration {
  session : SessionReport
  claims : Claims
  files : Array[Json]
  accounting : TreeGenerationAccounting
}

///|
/// Logical counters for reproducing admission and tiny fixture measurements.
/// These are not resident-memory measurements or a qualification receipt.
pub struct TreeGenerationAccounting {
  profile : TreeGenerationProfile
  source_documents : Int32
  source_entries : Int32
  source_bytes : Int64
  artifact_bytes : Int64
  output_paths : Int32
  deliveries : Int32
  retained_request_ids : Int32
  profile_minimum_deliveries : Int32
  metadata_bytes : Int32
  work_units : Int64
  work_limit : Int64
}

///|
fn tree_count_json(value : Int64) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
pub fn TreeGenerationAccounting::to_json(
  self : TreeGenerationAccounting,
) -> Json {
  {
    "profile": match self.profile {
      Standard => "standard"
      OrdersScaleA => "orders-scale-a"
      OrdersScaleB => "orders-scale-b"
    },
    "residentMemoryQualified": false,
    "sourceDocuments": self.source_documents,
    "sourceEntries": self.source_entries,
    "sourceBytes": tree_count_json(self.source_bytes),
    "artifactBytes": tree_count_json(self.artifact_bytes),
    "outputPaths": self.output_paths,
    "deliveries": self.deliveries,
    "retainedRequestIds": self.retained_request_ids,
    "profileMinimumDeliveries": self.profile_minimum_deliveries,
    "metadataBytes": self.metadata_bytes,
    "workUnits": tree_count_json(self.work_units),
    "provisionalWorkLimit": tree_count_json(self.work_limit),
  }
}

///|
priv struct TreeBudget {
  frame : Int32
  depth : Int32
  nodes : Int32
  document_count : Int32
  decoded : Int32
  encoded : Int32
  cache : Int32
  chunk : Int32
  file : Int64
  total : Int64
  disk : Int64
  work : Int64
}

///|
fn TreeBudget::from_limits(limits : @model_access.Limits) -> TreeBudget raise {
  // Aggregate limits retain the wire's Int64 range. Per-document and
  // per-exchange limits are Int32-bounded by the validated wire contract.
  let fields = limits.to_json()
  let get = key => {
    @string.parse_int64(
      @model_wire.integer_text(@model_wire.field(fields, key)),
    )
  }
  {
    frame: limits.frame_bytes().to_int(),
    depth: get("maxDepth").to_int(),
    nodes: get("maxNodes").to_int(),
    document_count: get("maxDocumentsPerBatch").to_int(),
    decoded: get("maxDecodedBytesPerExchange").to_int(),
    encoded: get("maxEncodedBytesPerExchange").to_int(),
    cache: get("maxHostCacheBytes").to_int(),
    chunk: get("maxArtifactChunkBytes").to_int(),
    file: get("maxArtifactBytes"),
    total: get("maxTotalArtifactBytes"),
    disk: get("maxSessionDiskBytes"),
    work: get("maxSessionWorkUnits"),
  }
}

///|
fn tree_support() -> @model_access.Support raise {
  let tuple : @model_access.AccessTuple = {
    ir: V4,
    codec: MorphirJson,
    encoding: Plain,
  }
  @model_access.Support::from_json({
    "tuples": [tuple.to_json()],
    "limits": {
      "maxFrameBytes": 1048576,
      "maxEncodedBytesPerExchange": 524288,
      "maxDecodedBytesPerExchange": 262144,
      "maxDocumentsPerBatch": 8,
      "maxDepth": 64,
      "maxNodes": 20000,
      "maxDiagnosticsPerExchange": 32,
      "maxOutstandingRequests": 16,
      "maxGuestStateBytes": 67108864,
      "maxHostCacheBytes": TREE_CACHE_BYTES,
      "maxArtifactChunkBytes": 65536,
      "maxArtifactBytes": 16777216,
      "maxTotalArtifactBytes": 67108864,
      "maxSessionDiskBytes": 134217728,
      "maxSessionWorkUnits": 65536,
      "maxRounds": 256,
      "maxCallMilliseconds": 5000,
      "maxSessionMilliseconds": 60000,
    },
  })
}

///|
priv enum TreePosition {
  Packages(Int32, @yaml.TreeCursor?)
  Members(@ir.Path, @ir.Path, @yaml.TreeCursor?)
}

///|
priv struct TreeView {
  tree : @yaml.BoundedTree
  capture : TreeCapture
  packages : Array[@ir.Path]
  id : String
  selections : Map[String, TreePosition]
  cursors : Map[String, (String, TreePosition)]
  documents : Map[String, @yaml.TreeArtifact]
  budget : TreeBudget
  check : () -> Unit raise
  mut issued : Int32
  mut request_ids : Int32
  mut deliveries : Int32
  mut cache : Int32
  work : Ref[Int64]
}

///|
fn TreeView::open(
  capture : TreeCapture,
  budget : TreeBudget,
  id : String,
  check : () -> Unit raise,
) -> TreeView raise {
  guard tree_budget_fits(0L, capture.bytes, budget.disk) &&
    capture.cache <= budget.cache &&
    tree_budget_fits(0L, capture.work, budget.work) else {
    raise TreeSource(
      "captured source exceeds negotiated disk, metadata, or work limit",
    )
  }
  let defaults = @yaml.Limits::default()
  let limits = {
    ..defaults,
    max_bytes: capture.admission.document_bytes,
    max_depth: budget.depth,
    max_nodes: budget.nodes,
    // Typed normalization charges string/key UTF-16 units as well as nodes.
    // Keep the wire node cap, with a separate finite allowance per 32 KiB
    // document for the Orders literal bodies and shorthand normalization.
    max_assembly_nodes: match capture.admission.profile {
      Standard => budget.nodes
      OrdersScaleA | OrdersScaleB => 4 * capture.admission.document_bytes
    },
  }
  let work = Ref(capture.work)
  let observe = () => charge_tree_work(work, budget.work, 1, check)
  let tree = @yaml.open_bounded_tree(
    capture.tree_source(check, observe~),
    limits~,
    split_members_only=true,
    observe~,
  )
  guard tree.format_version().to_release_string() == "4.0.0" &&
    capture.documents.contains("manifest.json") else {
    raise Refusal(
      code=TupleUnavailable,
      message="native document-tree generation supports plain JSON IR 4.0.0",
    )
  }
  let packages = [tree.package_name(), ..tree.dependency_packages().collect()]
  guard packages.length() <= TREE_ENTRIES else {
    raise TreeSource("the snapshot lists too many packages")
  }
  {
    tree,
    capture,
    packages,
    id,
    selections: Map([]),
    cursors: Map([]),
    documents: Map([]),
    budget,
    check,
    issued: 0,
    request_ids: 0,
    deliveries: 0,
    cache: capture.cache,
    work,
  }
}

///|
// Check before adding so aggregate counters cannot wrap at either width.
fn tree_budget_fits(used : Int64, extra : Int64, limit : Int64) -> Bool {
  used >= 0L && extra >= 0L && used <= limit && extra <= limit - used
}

///|
fn charge_tree_work(
  work : Ref[Int64],
  limit : Int64,
  units : Int64,
  check : () -> Unit raise,
) -> Unit raise {
  check()
  guard tree_budget_fits(work.val, units, limit) else {
    raise TreeSource("bounded generation work limit exceeded")
  }
  work.val += units
}

///|
fn TreeView::account(
  self : TreeView,
  work : Int64,
  cache~ : Int32 = 0,
) -> Unit raise {
  charge_tree_work(self.work, self.budget.work, work, self.check)
  guard cache <= self.budget.cache - self.cache else {
    raise TreeSource("bounded generation metadata limit exceeded")
  }
  self.cache += cache
}

///|
fn TreeView::token(self : TreeView, kind : String) -> String {
  self.issued += 1
  "\{self.id}-\{kind}-\{self.issued}"
}

///|
fn TreeView::allow_document(
  self : TreeView,
  id : String,
  artifact : @yaml.TreeArtifact,
) -> Unit raise {
  if !self.documents.contains(id) {
    self.account(1, cache=256 + 4 * id.length())
    self.documents[id] = artifact
  }
}

///|
fn tree_identity(
  package_name : @ir.Path,
  module_path : @ir.Path,
  document : String,
  role : @yaml.TreeRole,
) -> Map[String, Json] {
  {
    "packageName": package_name.to_canonical(),
    "modulePath": module_path.to_canonical(),
    "documentId": document,
    "role": match role {
      Definition => "definition"
      Specification => "specification"
    },
  }
}

///|
fn TreeView::inventory(
  self : TreeView,
  position : TreePosition,
  limit : Int32,
) -> (Array[Json], TreePosition?) raise {
  let entries : Array[Json] = []
  match position {
    Members(package_name, module_path, cursor) => {
      let page = self.tree.members(package_name, module_path, limit~, cursor?)
      for item in page.items {
        self.account(1)
        let tag = match item.kind {
          TypeMember => "type"
          ValueMember => "value"
        }
        self.allow_document(
          item.document,
          MemberArtifact(package_name, module_path, item.kind, item.name),
        )
        let identity = tree_identity(
          package_name,
          module_path,
          item.document,
          item.role,
        )
        identity["name"] = Json::string(item.name.to_canonical())
        entries.push(@model_wire.tag(tag, Json::object(identity)))
      }
      (
        entries,
        page.next.map(next => Members(package_name, module_path, Some(next))),
      )
    }
    Packages(first, cursor) => {
      let mut start = cursor
      for index in first..<self.packages.length() {
        self.account(1)
        let package_name = self.packages[index]
        let page = self.tree.modules(
          package_name,
          limit=limit - entries.length(),
          cursor?=start,
        )
        for module_info in page.items {
          let id = module_info.document
          self.account(1, cache=256 + 4 * id.length())
          self.allow_document(
            id,
            ModuleArtifact(package_name, module_info.path),
          )
          let selection = self.token("selection")
          self.selections[selection] = Members(
            package_name,
            module_info.path,
            None,
          )
          let identity = tree_identity(
            package_name,
            module_info.path,
            id,
            module_info.role,
          )
          identity["memberSelection"] = Json::string(selection)
          entries.push({ "module": Json::object(identity) })
        }
        if page.next is Some(next) {
          return (entries, Some(Packages(index, Some(next))))
        }
        if entries.length() == limit && index + 1 < self.packages.length() {
          return (entries, Some(Packages(index + 1, None)))
        }
        start = None
      }
      (entries, None)
    }
  }
}

///|
fn TreeView::inventory_delivery(
  self : TreeView,
  request_id : String,
  selection : String,
  page_size : Int32,
  cursor : String?,
) -> Json raise {
  guard page_size <= self.capture.admission.page_size else {
    raise TreeGuest("inventory page size exceeds the admission limit")
  }
  let position = match cursor {
    Some(token) => {
      guard self.cursors.get(token) is Some((owner, position)) &&
        owner == selection else {
        raise TreeGuest(
          "inventory cursor is stale or belongs to another selection",
        )
      }
      self.cursors.remove(token)
      position
    }
    None if selection == "root" => Packages(0, None)
    None => {
      guard self.selections.get(selection) is Some(position) else {
        raise TreeGuest("unknown inventory selection")
      }
      position
    }
  }
  let (entries, next) = self.inventory(position, page_size)
  let fields : Map[String, Json] = {
    "kind": "inventory",
    "requestId": request_id,
    "snapshotId": self.id,
    "entries": Json::array(entries),
  }
  if next is Some(position) {
    self.account(1, cache=256)
    let token = self.token("cursor")
    self.cursors[token] = (selection, position)
    fields["nextCursor"] = Json::string(token)
  }
  Json::object(fields)
}

///|
fn TreeView::deliver(
  self : TreeView,
  round : Int32,
  requests : Array[@model_access.ReadRequest],
) -> @model_access.Advance raise {
  let deliveries : Array[Json] = []
  let mut documents = 0
  let mut decoded = 0
  let mut encoded = 0
  let mut remaining_frame = self.budget.frame - 128 - self.id.length()
  for request in requests {
    self.account(1)
    guard request.request_id().length() <=
      self.capture.admission.request_id_units else {
      raise TreeGuest("request ID exceeds the admission limit")
    }
    let delivery : Json = match request {
      Inventory(request_id~, selection~, page_size~, cursor~) =>
        self.inventory_delivery(request_id, selection, page_size, cursor)
      Document(request_id~, document_id~) => {
        guard document_id.length() <= self.capture.admission.path_units else {
          raise TreeGuest("document ID exceeds the admission limit")
        }
        let physical = document_id + ".json"
        guard self.documents.get(document_id) is Some(artifact) &&
          self.capture.documents.get(physical) is Some(expected) else {
          raise TreeGuest(
            "document ID was not admitted by inventory: " + document_id,
          )
        }
        documents += 1
        decoded += expected.size
        encoded += (expected.size + 2) / 3 * 4
        guard documents <= self.budget.document_count &&
          decoded <= self.budget.decoded &&
          encoded <= self.budget.encoded else {
          raise TreeSource("document delivery exceeds negotiated batch limits")
        }
        self.account(1L + expected.size.to_int64() / 65536L)
        let (path, content) = self.tree.read_original_document(artifact)
        let bytes = @utf8.encode(content)
        guard path == physical &&
          bytes.length() == expected.size &&
          @identity.sha256(bytes) == expected.digest else {
          raise TreeSource(
            "document changed or has a different physical identity: " +
            document_id,
          )
        }
        {
          "kind": "document",
          "requestId": request_id,
          "snapshotId": self.id,
          "documentId": document_id,
          "decodedByteLength": expected.size,
          "sha256": expected.digest,
          "content": @base64.encode(bytes[:]),
        }
      }
    }
    remaining_frame -= @utf8.encode(delivery.stringify()).length() + 1
    guard remaining_frame >= 0 else {
      raise Refusal(
        code=RequestLimit,
        message="bounded deliveries exceed the agreed frame",
      )
    }
    deliveries.push(delivery)
    self.deliveries += 1
  }
  @model_access.Advance::from_json({
    "sessionId": self.id,
    "round": round,
    "deliveries": Json::array(deliveries),
  })
}

///|
fn tree_source_error(error : Error) -> Error {
  match error {
    TreeSource(_)
    | TreeGuest(_)
    | TreeExpired
    | TreeInterrupted
    | Refusal(..) => error
    @platform.Interrupted => TreeInterrupted
    @platform.IOError(message) => TreeSource(message)
    @model_wire.Invalid(code, detail) => TreeSource(code + ": " + detail)
    _ => TreeSource(error.to_string())
  }
}

///|
fn tree_output_error(error : Error) -> Error {
  match error {
    TreeOutput(_) | TreeExpired | TreeInterrupted => error
    @platform.Interrupted => TreeInterrupted
    @platform.IOError(message) => TreeOutput(message)
    _ => TreeOutput(error.to_string())
  }
}

///|
fn TreeView::retain_requests(
  self : TreeView,
  requests : Array[@model_access.ReadRequest],
) -> Unit raise {
  guard requests.length() <=
    self.capture.admission.request_limit - self.request_ids else {
    raise TreeGuest("retained request count exceeds the admission limit")
  }
  for request in requests {
    let id = request.request_id()
    guard id.length() <= self.capture.admission.request_id_units else {
      raise TreeGuest("request ID exceeds the admission limit")
    }
    // GenerationRun retains every unique ID for replay protection. Charge
    // its string, collection slots and overhead in the same cache as capture,
    // inventory, diagnostics and staging. One decoded frame is transient.
    self.account(0, cache=256 + 4 * id.length())
    self.request_ids += 1
  }
}

///|
fn TreeView::step(
  self : TreeView,
  answer : Outcome[GenerationReply],
  diagnostics : Array[Diagnostic],
) -> @model_access.GenerationStep raise {
  for diagnostic in answer.diagnostics {
    // Charge the response representation and overhead before retaining it
    // across rounds. The per-exchange count has already been admitted.
    let retained = 256 +
      2 * @utf8.encode(diagnostic.to_json().stringify()).length()
    guard retained <= self.budget.cache - self.cache else {
      raise TreeGuest("retained diagnostics exceed the negotiated host cache")
    }
    self.account(1, cache=retained)
    diagnostics.push(diagnostic)
  }
  match answer.class {
    Completed(Stepped(step)) => {
      if step is Continue(requests~, ..) {
        self.retain_requests(requests)
      }
      step
    }
    Cancelled => raise TreeInterrupted
    Deadline => raise TreeExpired
    Refused(code~, message~) => raise Refusal(code~, message~)
    Failed(fault) => raise TreeWorker(Failed(fault))
    _ => raise TreeGuest("bounded generation ended without a generation step")
  }
}

///|
fn base64_sextet(character : Char) -> Int32 {
  if character >= 'A' && character <= 'Z' {
    character.to_int() - 'A'.to_int()
  } else if character >= 'a' && character <= 'z' {
    character.to_int() - 'a'.to_int() + 26
  } else if character >= '0' && character <= '9' {
    character.to_int() - '0'.to_int() + 52
  } else {
    match character {
      '+' => 62
      '/' => 63
      _ => -1
    }
  }
}

///|
/// Canonical base64 is ASCII. Count its implied bytes, including the unused
/// bits in the padded final sextet, without allocating a decoded buffer.
fn canonical_base64_decoded_size(
  content : String,
) -> Int32 raise TreeGenerationError {
  let invalid = TreeGuest("artifact chunk content is not canonical base64")
  let length = content.length()
  guard length % 4 == 0 else { raise invalid }
  let mut padding = 0
  let mut last = 0
  for character in content.iter() {
    if character == '=' {
      padding += 1
      guard padding <= 2 else { raise invalid }
    } else {
      guard padding == 0 else { raise invalid }
      last = base64_sextet(character)
      guard last >= 0 else { raise invalid }
    }
  }
  guard (padding != 2 || last % 16 == 0) && (padding != 1 || last % 4 == 0) else {
    raise invalid
  }
  length / 4 * 3 - padding
}

///|
/// Admit the whole response before decoding or staging any individual chunk.
fn TreeBudget::check_artifact_batch(
  self : TreeBudget,
  artifacts : Array[@model_access.ArtifactChunk],
) -> Unit raise TreeGenerationError {
  let mut encoded = self.encoded
  let mut decoded = self.decoded
  for chunk in artifacts {
    let encoded_size = chunk.content.length()
    guard encoded_size <= encoded else {
      raise TreeGuest(
        "artifact batch exceeds the negotiated encoded byte limit",
      )
    }
    let decoded_size = canonical_base64_decoded_size(chunk.content)
    guard decoded_size <= decoded else {
      raise TreeGuest(
        "artifact batch exceeds the negotiated decoded byte limit",
      )
    }
    guard chunk.decoded_byte_length == decoded_size else {
      raise TreeGuest(
        "artifact chunk declared decoded length does not match canonical base64",
      )
    }
    encoded -= encoded_size
    decoded -= decoded_size
  }
}

///|
async fn TreeView::generate(
  self : TreeView,
  session : Session,
  stage : TreeStage,
  access : @model_access.Support,
  target : String,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let start = @model_access.Start::from_json({
    "sessionId": self.id,
    "snapshot": {
      "snapshotId": self.id,
      "modelId": self.tree.package_name().to_canonical(),
      "revision": self.capture.revision,
      "contextDigest": self.capture.context_digest,
      "scope": self.id,
    },
    "input": access.tuples()[0].to_json(),
    "target": target,
    "options": Json::empty_object(),
    "requiredGuarantees": [],
    "limits": access.limits.to_json(),
  })
  let mut step = self.step(session.start_generation(start), diagnostics)
  while true {
    self.account(1)
    let artifacts = match step {
      Continue(artifacts~, ..) | Complete(artifacts~, ..) => artifacts
      Failed(..) => raise TreeUnsuccessful
    }
    self.budget.check_artifact_batch(artifacts)
    for chunk in artifacts {
      self.account(1L + chunk.decoded_byte_length.to_int64() / 65536L)
      let metadata = stage.metadata
      stage.write(chunk, self.budget, self.capture.bytes) catch {
        error => raise tree_output_error(error)
      }
      guard stage.metadata - metadata <= self.budget.cache - self.cache else {
        raise TreeOutput("stage metadata exceeds the negotiated cache limit")
      }
      self.account(0, cache=stage.metadata - metadata)
    }
    match step {
      Continue(round~, requests~, ..) => {
        let delivery = self.deliver(round, requests) catch {
          error => raise tree_source_error(error)
        }
        step = self.step(session.advance_generation(delivery), diagnostics)
      }
      _ => return
    }
  }
}

///|
/// Generates from an explicit native document-tree root. The private buffered
/// source lives on disk, while the worker sees only bounded MEP deliveries.
/// A completed and stopped worker is required before the stage can publish.
pub async fn Host::generate_tree(
  self : Host,
  spec : WorkerSpec,
  expected? : Claims,
  input~ : TreeGenerationInput,
  output~ : String,
  target~ : String,
  requested_ir~ : IrVersionName?,
  deadline~ : Deadline,
  stop~ : StopSignal,
  diagnostics~ : Array[Diagnostic],
  profile~ : TreeGenerationProfile = Standard,
) -> TreeGeneration {
  let scale = profile != Standard
  if scale &&
    !(spec.runtime is Wasm(abi=Some(ExtismKernelV1)) &&
    input is CompileResult(_) &&
    target == "text") {
    raise Refusal(
      code=RuntimeUnavailable,
      message="Orders qualification requires recorded Extism plain v4 text generation",
    )
  }
  let admitted = if scale {
    true
  } else {
    match (spec.runtime, input, expected) {
      (Process(..), _, Some(_)) => true
      (Wasm(abi=Some(ExtismKernelV1)), CompileResult(_), None) => true
      _ => false
    }
  }
  guard self.platform is Native(_) &&
    admitted &&
    ["macos", "linux"].contains(@platform.system_type()) else {
    raise Refusal(
      code=RuntimeUnavailable,
      message="bounded tree generation needs a native process or a pinned Extism WASM worker with a compile result",
    )
  }
  if requested_ir is Some(version) &&
    !["4", "4.0.0"].contains(version.to_string()) {
    raise Refusal(
      code=TupleUnavailable,
      message="native document-tree generation supports plain JSON IR 4.0.0",
    )
  }
  let admission = profile.admission()
  let support = admission.support
  let bounded_host = { ..self, limits: profile.channel_limits(self.limits), }
  let offer = match expected {
    None => Offer::Bounded(support)
    Some(claims) =>
      match BoundedGenerateChoice::select(claims, support, target) {
        Access(offer) => offer
        _ =>
          raise Refusal(
            code=TupleUnavailable,
            message="a document tree requires the bounded generation tuple",
          )
      }
  }
  if scale {
    guard offer is Bounded(offered) && offered.limits == support.limits else {
      raise Refusal(
        code=RequestLimit,
        message="recorded claims narrow the Orders qualification offer",
      )
    }
  }
  let expires = Ref(@async.now() + deadline.ms().to_int64())
  fn remaining() -> Deadline raise {
    if stop.requested() {
      raise TreeInterrupted
    }
    let ms = expires.val - @async.now()
    guard ms > 0L else { raise TreeExpired }
    profile.deadline(milliseconds=ms.to_int())
  }
  let check = () => ignore(remaining())
  let nonce = @platform.observation_id()
  let source = input.open(check) catch {
    error => raise tree_source_error(error)
  }
  defer (source.release)()
  let stage = TreeStage::open(
    output,
    nonce,
    source=source.protected_directory,
    admission~,
    diagnostics~,
  ) catch {
    error => raise tree_output_error(error)
  }
  defer stage.dispose(diagnostics~)
  let snapshot_name = ".morphir-source-" + nonce
  let snapshot = open_tree_scratch(
    stage.parent,
    snapshot_name,
    "source snapshot",
    diagnostics,
  ) catch {
    error => raise tree_output_error(error)
  }
  let snapshot_released = Ref(false)
  defer {
    if !snapshot_released.val {
      stage.parent.discard(snapshot, snapshot_name, entries=admission.entries) catch {
        error => tree_cleanup_unconfirmed(diagnostics, "source snapshot", error)
      }
    }
    snapshot.close()
  }
  let capture = capture_tree(
    source.reopen,
    source.directory,
    snapshot,
    stage.parent.stamp(),
    check,
    admission~,
  ) catch {
    error => raise tree_source_error(error)
  }
  // Keep the producer's lease through lazy delivery and worker settlement.
  // The outer defer releases it after any snapshot and stage cleanup.
  let accounting : Ref[TreeGenerationAccounting?] = Ref(None)
  let (outcome, report) = bounded_host.with_session_claims(
    spec,
    expected,
    offer,
    remaining(),
    stop,
    async fn(session) {
      let completed = try {
        guard session.negotiated() is Some({ model_access: Some(access), .. }) else {
          raise Refusal(
            code=AgreementMismatch,
            message="worker supplied no live bounded agreement",
          )
        }
        guard session.conversation.expected is Some(claims) &&
          (
            expected is Some(_) ||
            BoundedGenerateChoice::select(claims, support, target) is Access(_)
          ) else {
          raise Refusal(
            code=CapabilityUnavailable,
            message="the initialized worker does not claim the bounded generation target",
          )
        }
        if scale && access.limits != support.limits {
          raise Refusal(
            code=RequestLimit,
            message="worker narrowed the Orders qualification offer",
          )
        }
        expires.val = @cmp.minimum(
          expires.val,
          @async.now() + access.limits.session_milliseconds().to_int64(),
        )
        let budget = TreeBudget::from_limits(access.limits)
        let view = TreeView::open(capture, budget, nonce, check) catch {
          Refusal(..) as error => raise error
          error => raise tree_source_error(error)
        }
        view.generate(session, stage, access, target, diagnostics)
        // Reserve the directory scan and the streaming verification pass.
        view.account(stage.verification_work())
        accounting.val = Some({
          profile: capture.admission.profile,
          profile_minimum_deliveries: capture.admission.deliveries,
          source_documents: capture.documents.length(),
          source_entries: capture.entries,
          source_bytes: capture.bytes,
          artifact_bytes: stage.bytes,
          output_paths: stage.paths.length(),
          deliveries: view.deliveries,
          retained_request_ids: view.request_ids,
          metadata_bytes: view.cache,
          work_units: view.work.val,
          work_limit: budget.work,
        })
        Ok(claims)
      } catch {
        error => Err(error)
      }
      // Closing an unfinished bounded session uses the worker's typed cancel
      // exchange before shutdown, or terminates the process on a stop/deadline.
      (
        completed,
        session.close_before(
          Some(expires.val),
          require_clean_exit=spec.runtime is Wasm(..),
        ),
      )
    },
  )
  let claims = match outcome {
    Err(TreeWorker(ending)) => raise Ended(ending, report~)
    Err(error) => raise error
    Ok(claims) => claims
  }
  if report.ending is Some(ending) {
    raise Ended(ending, report~)
  }
  guard report.stop is Some(stopped) && !(stopped.status is Unconfirmed(_)) else {
    raise TreeOutput("the host could not confirm that the worker tree stopped")
  }
  stage.parent.discard(snapshot, snapshot_name, entries=admission.entries) catch {
    error => raise tree_output_error(error)
  }
  snapshot_released.val = true
  let files = stage.publish_checked(check) catch {
    error => raise tree_output_error(error)
  }
  { session: report, claims, files, accounting: accounting.val.unwrap(), }
}

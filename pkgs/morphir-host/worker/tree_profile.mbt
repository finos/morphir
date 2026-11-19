///|
/// Explicit qualification admission. These profiles bound logical accounting;
/// they do not claim resident-memory or production-scale qualification.
#derive(Eq, Debug)
pub(all) enum TreeGenerationProfile {
  Standard
  OrdersScaleA
  OrdersScaleB
}

///|
pub extend TreeGenerationProfile with Eq::{equal, not_equal}

///|
pub extend TreeGenerationProfile with @debug.Debug::{to_repr}

///|
/// Normal deadline construction keeps its existing ceiling. Scale horizons
/// are provisional: one/two hours, pending measured A/B throughput. They allow
/// 25 ms per nominal delivery plus 4 source and 2 artifact I/O passes at 10 MiB/s,
/// with startup/cleanup margin. They are not measured completion guarantees.
pub fn TreeGenerationProfile::deadline(
  self : TreeGenerationProfile,
  milliseconds? : Int32,
) -> Deadline raise ValueError {
  let (default_ms, maximum) = match self {
    Standard => (60000, max_deadline_ms)
    OrdersScaleA => (3600000, 3600000)
    OrdersScaleB => (7200000, 7200000)
  }
  let ms = milliseconds.unwrap_or(default_ms)
  guard ms > 0 && ms <= maximum else { raise InvalidDeadline(ms) }
  { ms, }
}

///|
#cfg(target="native")
priv struct TreeAdmission {
  profile : TreeGenerationProfile
  document_bytes : Int32
  documents : Int32
  entries : Int32
  source_bytes : Int64
  cache_bytes : Int32
  output_paths : Int32
  path_units : Int32
  request_id_units : Int32
  page_size : Int32
  deliveries : Int32
  request_limit : Int32
  support : @model_access.Support
}

///|
#cfg(target="native")
fn TreeGenerationProfile::admission(
  self : TreeGenerationProfile,
) -> TreeAdmission raise {
  if self is Standard {
    return {
      profile: self,
      document_bytes: TREE_DOCUMENT_BYTES,
      documents: TREE_ENTRIES,
      entries: TREE_ENTRIES,
      source_bytes: TREE_SNAPSHOT_BYTES,
      cache_bytes: TREE_CACHE_BYTES,
      output_paths: 1024,
      path_units: 1024,
      request_id_units: 256,
      page_size: 128,
      deliveries: 0,
      request_limit: 4096,
      support: tree_support(),
    }
  }
  let (
    documents,
    entries,
    source_bytes,
    artifact_bytes,
    output_paths,
    deliveries,
    cache,
  ) = match self {
    OrdersScaleA =>
      (68611, 69643, 1086620931L, 1090585600L, 1025, 78913, 268435456)
    OrdersScaleB =>
      (137219, 139275, 2173241603L, 2181171200L, 2049, 157825, 536870912)
    Standard => abort("handled above")
  }
  // Derived from the actual charged capture, lookup, inventory and stage
  // verification loops for the pinned recipe/guest. Root search uses a
  // conservative binary-search bound; wall time remains unqualified.
  let work = OrdersScaleWork::for_modules(output_paths - 1).total()
  let defaults = tree_support()
  let fields = @model_wire.object(defaults.limits.to_json())
  // The landed guest charges input document plus emitted chunk together
  // within one exchange: 16560 + 16385 decoded, 43928 base64 bytes.
  // Documents themselves retain the independent 32 KiB capture limit.
  for
    (name, value) in [
      ("maxFrameBytes", 65536L),
      ("maxEncodedBytesPerExchange", 65536L),
      ("maxDecodedBytesPerExchange", 65536L),
      ("maxDocumentsPerBatch", 1L),
      ("maxNodes", 1024L),
      ("maxDiagnosticsPerExchange", 1L),
      ("maxOutstandingRequests", 1L),
      ("maxGuestStateBytes", 1048576L),
      ("maxHostCacheBytes", cache.to_int64()),
      ("maxArtifactChunkBytes", 32768L),
      ("maxArtifactBytes", 1065025L),
      ("maxTotalArtifactBytes", artifact_bytes),
      ("maxSessionDiskBytes", source_bytes + artifact_bytes),
      ("maxSessionWorkUnits", work),
      ("maxRounds", 2L * deliveries.to_int64()),
      ("maxCallMilliseconds", 1000L),
      ("maxSessionMilliseconds", self.deadline().ms().to_int64()),
    ] {
    fields[name] = Json::number(value.to_double(), repr=value.to_string())
  }
  {
    profile: self,
    document_bytes: 32768,
    documents,
    entries,
    source_bytes,
    cache_bytes: cache,
    output_paths,
    path_units: 256,
    request_id_units: 64,
    page_size: 16,
    deliveries,
    request_limit: 2 * deliveries,
    support: @model_access.Support::from_json({
      "tuples": Json::array(defaults.tuples().map(tuple => tuple.to_json())),
      "limits": Json::object(fields),
    }),
  }
}

///|
#cfg(target="native")
fn TreeGenerationProfile::channel_limits(
  self : TreeGenerationProfile,
  host : Limits,
) -> Limits raise Refusal {
  if self is Standard {
    return host
  }
  guard host.request_bytes >= 65536 && host.response_bytes >= 65536 else {
    raise Refusal(
      code=RequestLimit,
      message="Orders qualification needs 64 KiB channels",
    )
  }
  {
    ..host,
    request_bytes: 65536,
    response_bytes: 65536,
    model: {
      encoded_bytes: 43692,
      decoded_bytes: 32768,
      depth: 64,
      nodes: 1024,
    },
  }
}

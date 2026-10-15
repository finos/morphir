///|
/// Frozen correlation and identities expected by this host operation.
pub(all) struct Expected {
  invocation : String
  project_scope : String
  release : String
  policy_sha256 : String
  lock_sha256 : String
}

///|
/// Encode an effect-free one-shot capability probe.
pub fn capabilities_request(
  invocation : String,
  project_scope : String,
) -> Bytes raise {
  if invocation.length() > MAX_REQUEST_BYTES ||
    project_scope.length() > MAX_REQUEST_BYTES {
    raise Invalid("metadata.restore_request_limit")
  }
  let bytes = @binary.write_binary_value(
    record([
      ("invocation", @ion.IonValue::string(invocation)),
      ("projectScope", @ion.IonValue::string(project_scope)),
    ]).with_annotation(
      @ion.SymbolToken::new("morphir_provider_capabilities_request_v1"),
    ),
  )
  if bytes.length() > MAX_REQUEST_BYTES {
    raise Invalid("metadata.restore_request_limit")
  }
  bytes
}

///|
/// Encode granted roots and immutable policy/lock snapshots as binary Ion blobs.
/// Caller must qualify the selected service and grant these paths independently.
pub fn snapshot_request(
  expected : Expected,
  policy : Bytes,
  lock : Bytes,
  registry : String,
  state : String,
  output : String,
) -> Bytes raise {
  if @identity.sha256(policy) != expected.policy_sha256 ||
    @identity.sha256(lock) != expected.lock_sha256 {
    raise Invalid("metadata.restore_request_identity_mismatch")
  }
  let bytes = @binary.write_binary_value(
    record([
      ("invocation", @ion.IonValue::string(expected.invocation)),
      ("projectScope", @ion.IonValue::string(expected.project_scope)),
      ("release", @ion.IonValue::string(expected.release)),
      ("assurance", @ion.IonValue::string("portable")),
      ("registry", @ion.IonValue::string(registry)),
      ("state", @ion.IonValue::string(state)),
      ("output", @ion.IonValue::string(output)),
      ("policy", @ion.IonValue::blob(policy)),
      ("lock", @ion.IonValue::blob(lock)),
    ]).with_annotation(
      @ion.SymbolToken::new("morphir_provider_snapshot_request_v1"),
    ),
  )
  if bytes.length() > MAX_REQUEST_BYTES {
    raise Invalid("metadata.restore_request_limit")
  }
  bytes
}

///|
fn correlate(
  values : Map[String, @ion.IonValue],
  invocation : String,
  project_scope : String,
) -> Unit raise {
  if text(required(values, "invocation")) != invocation ||
    text(required(values, "projectScope")) != project_scope ||
    text(required(values, "service")) != SERVICE_ID ||
    text(required(values, "profile")) != "local-library-mvp" ||
    text(required(values, "profileVersion")) != "0.1.0-draft.1" ||
    text(required(values, "codec")) != "v4.1-document-metadata-to-v4.0/1" {
    invalid("Correlation, service or execution profile mismatch")
  }
}

///|
/// Check this exact protocol revision. A response is not executable attestation.
pub fn admit_capabilities(
  bytes : Bytes,
  invocation : String,
  project_scope : String,
) -> Unit raise {
  let values = frame(bytes, "morphir_provider_capabilities_response_v1", [
    "invocation", "projectScope", "service", "profile", "profileVersion", "codec",
    "maxRequestBytes", "maxResponseBytes", "maxLibraries", "maxContexts", "maxTotalContexts",
  ])
  correlate(values, invocation, project_scope)
  for
    (key, expected) in [
      ("maxRequestBytes", MAX_REQUEST_BYTES),
      ("maxResponseBytes", MAX_RESPONSE_BYTES),
      ("maxLibraries", 128),
      ("maxContexts", 256),
      ("maxTotalContexts", 1024),
    ] {
    let value = required(values, key)
    if value.has_annotations() || !value.equals(@ion.IonValue::int(expected)) {
      invalid("Unsupported framing limit")
    }
  }
}

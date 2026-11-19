///|
fn history_start(rounds~ : Int32 = 16) -> Start raise @wire.CodecError {
  let body =
    #|{"sessionId":"orders-generation","snapshot":{"snapshotId":"orders-snapshot","modelId":"acme/orders","revision":"orders-r1","contextDigest":"1111111111111111111111111111111111111111111111111111111111111111","scope":"orders-generation-view"},"input":{"protocolVersion":"0.2.0-draft.2","accessVersion":"0.1.0-draft.1","operation":"morphir.backend.generateModel","irVersion":"4.0.0","profile":"morphir-ir","codec":"morphir-json","layout":"document-tree","contextualEncoding":"plain"},"target":"text","options":{},"requiredGuarantees":[],"limits":{"maxFrameBytes":32768,"maxEncodedBytesPerExchange":8192,"maxDecodedBytesPerExchange":6144,"maxDocumentsPerBatch":8,"maxDepth":64,"maxNodes":256,"maxDiagnosticsPerExchange":16,"maxOutstandingRequests":8,"maxGuestStateBytes":1048576,"maxHostCacheBytes":1048576,"maxArtifactChunkBytes":4096,"maxArtifactBytes":4294967296,"maxTotalArtifactBytes":4294967296,"maxSessionDiskBytes":8589934592,"maxSessionWorkUnits":4096,"maxRounds":16,"maxCallMilliseconds":500,"maxSessionMilliseconds":2500}}
  let value = @wire.parse(body)
  @wire.object(@wire.field(value, "limits"))["maxRounds"] = Json::number(
    rounds.to_double(),
  )
  Start::from_json(value)
}

///|
fn history_requests(
  ids : Array[String],
) -> Array[ReadRequest] raise @wire.CodecError {
  ids.map(id => {
    ReadRequest::from_json({
      "kind": "document",
      "requestId": id,
      "documentId": "manifest",
    })
  })
}

///|
fn history_step(round : Int32, requests : Array[ReadRequest]) -> GenerationStep {
  Continue(session_id="orders-generation", round~, requests~, artifacts=[], diagnostics=[])
}

///|
fn history_advance(
  round : Int32,
  ids : Array[String],
  bad_last~ : Bool = false,
) -> Advance raise @wire.CodecError {
  Advance::from_json({
    "sessionId": "orders-generation",
    "round": round,
    "deliveries": Json::array(
      ids.mapi((index, id) => {
        "kind": "document",
        "requestId": id,
        "snapshotId": "orders-snapshot",
        "documentId": "manifest",
        "decodedByteLength": 0,
        "content": "",
        "sha256": if bad_last && index == ids.length() - 1 {
          "0".repeat(64)
        } else {
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        },
      }),
    ),
  })
}

///|
test "request history rolls back new IDs before a late duplicate in the batch" {
  let initial = GenerationRun::new(history_start())
  let first = initial
    .accept_step(history_step(1, history_requests(["old"])))
    .unwrap()
  for ids in [["fresh", "old"], ["fresh", "fresh"]] {
    let refused = try {
      ignore(first.accept_step(history_step(2, history_requests(ids))))
      false
    } catch {
      @wire.Invalid(code, _) => code == "model_access.duplicate_request"
    }
    assert_true(refused)
    assert_eq(first.round, 1)
    assert_eq(first.request_ids.length(), 1)
    assert_false(first.request_ids.contains("fresh"))
  }
  let retry = first
    .accept_step(history_step(2, history_requests(["fresh", "next"])))
    .unwrap()
  assert_eq(retry.request_ids.length(), 3)
  assert_true(retry.request_ids.contains("old"))
  assert_true(retry.request_ids.contains("fresh"))
  assert_eq(initial.request_ids.length(), 0)
  assert_eq(first.request_ids.length(), 1)
  // Successful derivation also leaves an earlier immutable run unchanged.
  let branch = first
    .accept_step(history_step(2, history_requests(["fresh"])))
    .unwrap()
  assert_eq(branch.request_ids.length(), 2)
  assert_false(branch.request_ids.contains("next"))
}

///|
test "request history owns the admitted batch despite caller array mutation" {
  let initial = GenerationRun::new(history_start())
  let requests = history_requests(["first", "second"])
  let run = initial.accept_step(history_step(1, requests)).unwrap()
  requests[0] = history_requests(["mutated"])[0]
  requests.push(history_requests(["extra"])[0])
  assert_eq(run.requests.length(), 2)
  assert_true(run.accepts(history_advance(1, ["first", "second"])))
  assert_false(run.accepts(history_advance(1, ["mutated", "second"])))
  assert_true(run.request_ids.contains("first"))
  assert_false(run.request_ids.contains("mutated"))
  assert_false(run.request_ids.contains("extra"))
}

///|
test "invalid later document delivery preserves the entire pending advance" {
  let run = GenerationRun::new(history_start())
    .accept_step(history_step(1, history_requests(["one", "two"])))
    .unwrap()
  assert_false(run.accepts(history_advance(1, ["one", "two"], bad_last=true)))
  assert_eq(run.round, 1)
  assert_eq(run.request_ids.length(), 2)
  assert_eq(run.requests.map(request => request.request_id()), ["one", "two"])
  assert_true(run.accepts(history_advance(1, ["one", "two"])))
  let stale = try {
    ignore(run.accept_step(history_step(1, history_requests(["late"]))))
    false
  } catch {
    @wire.Invalid(code, _) => code == "model_access.invalid_round"
  }
  assert_true(stale)
  assert_false(run.request_ids.contains("late"))
  assert_eq(run.request_ids.length(), 2)
}

///|
test "request history retains early IDs across many bounded batches" {
  let initial = GenerationRun::new(history_start(rounds=1025))
  let mut current = initial
  for round in 1..<1025 {
    current = current
      .accept_step(history_step(round, history_requests([round.to_string()])))
      .unwrap()
  }
  assert_eq(current.request_ids.length(), 1024)
  assert_eq(initial.request_ids.length(), 0)
  let refused = try {
    ignore(
      current.accept_step(history_step(1025, history_requests(["new", "1"]))),
    )
    false
  } catch {
    @wire.Invalid(code, _) => code == "model_access.duplicate_request"
  }
  assert_true(refused)
  assert_false(current.request_ids.contains("new"))
  assert_true(current.request_ids.contains("1"))
  assert_true(current.request_ids.contains("1024"))
}

///|
fn request_test_start() -> Json raise @wire.CodecError {
  let body =
    #|{"sessionId":"orders-generation","snapshot":{"snapshotId":"orders-snapshot","modelId":"acme/orders","revision":"orders-r1","contextDigest":"1111111111111111111111111111111111111111111111111111111111111111","scope":"orders-generation-view"},"input":{"protocolVersion":"0.2.0-draft.2","accessVersion":"0.1.0-draft.1","operation":"morphir.backend.generateModel","irVersion":"4.0.0","profile":"morphir-ir","codec":"morphir-json","layout":"document-tree","contextualEncoding":"plain"},"target":"text","options":{},"requiredGuarantees":[],"limits":{"maxFrameBytes":32768,"maxEncodedBytesPerExchange":8192,"maxDecodedBytesPerExchange":6144,"maxDocumentsPerBatch":8,"maxDepth":64,"maxNodes":256,"maxDiagnosticsPerExchange":16,"maxOutstandingRequests":8,"maxGuestStateBytes":1048576,"maxHostCacheBytes":1048576,"maxArtifactChunkBytes":4096,"maxArtifactBytes":4294967296,"maxTotalArtifactBytes":4294967296,"maxSessionDiskBytes":8589934592,"maxSessionWorkUnits":4096,"maxRounds":16,"maxCallMilliseconds":500,"maxSessionMilliseconds":2500}}
  @wire.parse(body)
}

///|
test "bounded start and cancel round-trip named wire fields" {
  let value = request_test_start()
  let start = @model_access.Start::from_json(value)
  assert_eq(start.session_id, "orders-generation")
  assert_eq(start.snapshot.snapshot_id, "orders-snapshot")
  assert_eq(start.target, "text")
  assert_eq(start.to_json(), value)
  let cancel : Json = { "sessionId": "orders-generation" }
  assert_eq(@model_access.Cancel::from_json(cancel).to_json(), cancel)
}

///|
test "bounded advances preserve typed inventory and document deliveries in order" {
  let value : Json = {
    "sessionId": "orders-generation",
    "round": 2,
    "deliveries": [
      {
        "kind": "inventory",
        "requestId": "members",
        "snapshotId": "orders-snapshot",
        "entries": [
          {
            "module": {
              "documentId": "pkg/acme/orders/domain/module",
              "packageName": "acme/orders",
              "modulePath": "domain",
              "role": "definition",
              "memberSelection": "orders-domain-members",
            },
          },
          {
            "type": {
              "documentId": "pkg/acme/orders/domain/order.type",
              "packageName": "acme/orders",
              "modulePath": "domain",
              "role": "definition",
              "name": "order",
            },
          },
          {
            "value": {
              "documentId": "pkg/acme/orders/domain/order.value",
              "packageName": "acme/orders",
              "modulePath": "domain",
              "role": "specification",
              "name": "order",
            },
          },
        ],
        "nextCursor": "domain-page-two",
      },
      {
        "kind": "document",
        "requestId": "manifest",
        "snapshotId": "orders-snapshot",
        "documentId": "manifest",
        "decodedByteLength": 0,
        "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "content": "",
      },
    ],
  }
  let advance = @model_access.Advance::from_json(value)
  assert_eq(advance.round, 2)
  assert_eq(advance.deliveries[0].request_id(), "members")
  assert_eq(advance.deliveries[0].document_id(), None)
  assert_eq(advance.deliveries[1].request_id(), "manifest")
  assert_eq(advance.deliveries[1].snapshot_id(), "orders-snapshot")
  assert_eq(advance.deliveries[1].document_id(), Some("manifest"))
  assert_eq(advance.to_json(), value)
}

///|
test "bounded start and cancel refuse missing or invalid identity fields" {
  let missing_guarantees = request_test_start()
  @wire.object(missing_guarantees).remove("requiredGuarantees")
  let invalid_digest = request_test_start()
  @wire.object(@wire.field(invalid_digest, "snapshot"))["contextDigest"] = "AA"
  let invalid_tuple = request_test_start()
  @wire.object(@wire.field(invalid_tuple, "input"))["irVersion"] = "4"
  for value in [missing_guarantees, invalid_digest, invalid_tuple] {
    let rejected = try {
      ignore(@model_access.Start::from_json(value))
      false
    } catch {
      @wire.Invalid(_, _) => true
    }
    assert_true(rejected)
  }
  let rejected = try {
    ignore(@model_access.Cancel::from_json({ "sessionId": "" }))
    false
  } catch {
    @wire.Invalid(_, _) => true
  }
  assert_true(rejected)
}

///|
test "bounded advances refuse fractional, zero, and oversized rounds" {
  for round in ["1.0", "1e0", "0", "2147483648"] {
    let value = @wire.parse(
      "{\"sessionId\":\"orders-generation\",\"round\":\{round},\"deliveries\":[]}",
    )
    let rejected = try {
      ignore(@model_access.Advance::from_json(value))
      false
    } catch {
      @wire.Invalid(_, _) => true
    }
    assert_true(rejected)
  }
}

///|
test "bounded inventory rejects empty, mixed and mislabelled tagged entries" {
  let module_identity : Json = {
    "documentId": "pkg/acme/orders/domain/module",
    "packageName": "acme/orders",
    "modulePath": "domain",
    "role": "definition",
  }
  let module_with_name = @wire.object(module_identity).copy()
  module_with_name["name"] = "order"
  let named_with_selection = module_with_name.copy()
  named_with_selection["memberSelection"] = "members"
  let wrong_role = @wire.object(module_identity).copy()
  wrong_role["role"] = "implementation"
  for
    entry in [
      {},
      { "module": module_identity, "type": Json::object(module_with_name) },
      { "module": Json::object(module_with_name) },
      { "type": module_identity },
      { "value": Json::object(named_with_selection) },
      { "module": Json::object(wrong_role) },
    ] {
    let delivery : Json = {
      "requestId": "members",
      "kind": "inventory",
      "snapshotId": "orders-snapshot",
      "entries": [entry],
    }
    let rejected = try {
      ignore(@model_access.Delivery::from_json(delivery))
      false
    } catch {
      @wire.Invalid(_, _) => true
    }
    assert_true(rejected)
  }
}

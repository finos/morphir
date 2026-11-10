///|
test "host limits default to the specified bounds" {
  let limits = @worker.Limits::host()
  assert_eq(limits.request_bytes, 6 * 1024 * 1024)
  assert_eq(limits.response_bytes, 16 * 1024 * 1024)
  assert_eq(limits.model.decoded_bytes, 4 * 1024 * 1024)
  assert_eq(limits.model.encoded_bytes, 5592408)
  assert_eq(limits.model.depth, 128)
  assert_eq(limits.model.nodes, 100000)
}

///|
test "limits must be positive" {
  let model = @worker.ModelLimits::new(
    encoded_bytes=10,
    decoded_bytes=8,
    depth=4,
    nodes=16,
  )
  assert_eq(model.nodes, 16)
  guard (Ok(
      @worker.ModelLimits::new(
        encoded_bytes=10,
        decoded_bytes=0,
        depth=4,
        nodes=16,
      ),
    ) catch {
      e => Err(e)
    })
    is Err(InvalidLimit(_)) else {
    fail("accepted a zero limit")
  }
  guard (Ok(@worker.Limits::new(request_bytes=-1, response_bytes=1, model~)) catch {
      e => Err(e)
    })
    is Err(InvalidLimit(_)) else {
    fail("accepted a negative limit")
  }
}

///|
test "failure codes use the documented names" {
  let table : Array[(@worker.FailureCode, String)] = [
    (IncompleteSession, "extension.incomplete_session"),
    (FrameInvalid, "extension.frame_invalid"),
    (UnexpectedResponse, "extension.unexpected_response"),
    (ResponseLimit, "extension.response_limit"),
    (RequestLimit, "extension.request_limit"),
    (ProtocolUnavailable, "extension.protocol_unavailable"),
    (TupleUnavailable, "extension.tuple_unavailable"),
    (AgreementMismatch, "extension.agreement_mismatch"),
    (DescribeFailed, "extension.describe_failed"),
    (ClaimsMismatch, "extension.claims_mismatch"),
    (CapabilityUnavailable, "extension.capability_unavailable"),
    (PlatformMismatch, "extension.platform_mismatch"),
    (RuntimeUnavailable, "extension.runtime_unavailable"),
    (DigestMismatch, "extension.digest_mismatch"),
    (AbiUnsupported, "extension.abi_unsupported"),
    (AbiMismatch, "extension.abi_mismatch"),
    (WasmFeatureUnsupported, "extension.wasm_feature_unsupported"),
    (MemoryLimit, "extension.memory_limit"),
    (GuestTrap, "extension.guest_trap"),
    (TreeTerminationFailed, "execution.tree_termination_failed"),
    (BudgetExhausted, "extension.budget_exhausted"),
    (WorkerRuntimeMismatch, "extension.worker_runtime_mismatch"),
  ]
  assert_eq(table.length(), 22)
  for row in table {
    let (code, text) = row
    assert_eq(code.to_string(), text)
  }
}

///|
test "refusal and fault codes each map to one failure code" {
  let refusals : Array[@worker.RefusalCode] = [
    RequestLimit,
    ProtocolUnavailable,
    TupleUnavailable,
    AgreementMismatch,
    ClaimsMismatch,
    CapabilityUnavailable,
    PlatformMismatch,
    RuntimeUnavailable,
    DigestMismatch,
    AbiUnsupported,
    AbiMismatch,
    WasmFeatureUnsupported,
    WorkerRuntimeMismatch,
  ]
  let faults : Array[@worker.FaultCode] = [
    IncompleteSession,
    FrameInvalid,
    UnexpectedResponse,
    ResponseLimit,
    DescribeFailed,
    MemoryLimit,
    GuestTrap,
    TreeTerminationFailed,
    BudgetExhausted,
  ]
  let codes = refusals.map(code => code.code().to_string())
  codes.push_iter(faults.iter().map(code => code.code().to_string()))
  let unique = codes.copy()
  unique.sort()
  unique.dedup()
  // Together the two sets cover all 22 codes, and no code is in both.
  assert_eq(unique.length(), 22)
  assert_eq(codes.length(), 22)
  assert_eq(
    @worker.RefusalCode::ClaimsMismatch.to_string(),
    "extension.claims_mismatch",
  )
  assert_eq(@worker.FaultCode::GuestTrap.to_string(), "extension.guest_trap")
}

///|
test "the stderr tail keeps the last 64 KiB and says when it dropped bytes" {
  let head = Bytes::make(10, b'a')
  let tail = Bytes::make(65536, b'b')
  let kept = @worker.StderrTail::of(head + tail)
  assert_eq(kept.bytes().length(), 65536)
  assert_true(kept.bytes() == tail)
  assert_true(kept.truncated())
  assert_false(@worker.StderrTail::of(tail).truncated())
  assert_eq(@worker.StderrTail::empty().bytes().length(), 0)
  assert_false(@worker.StderrTail::empty().truncated())
}

///|
test "every outcome class keeps diagnostics and the stderr tail" {
  let diagnostics = [
    @worker.Diagnostic::decode({
      "code": "E1",
      "severity": "error",
      "message": "x",
    }),
  ]
  let stderr = @worker.StderrTail::of(b"warning")
  let classes : Array[@worker.OutcomeClass[String]] = [
    Completed("model"),
    Unsuccessful,
    Failed(
      Guest(code=-32600, message="bad request", data=Some({ "field": "id" })),
    ),
    Failed(Host(code=UnexpectedResponse, message="ID 4 answered request 3")),
    Refused(code=ClaimsMismatch, message="version drift"),
    Deadline,
    Cancelled,
  ]
  for class in classes {
    let outcome = @worker.Outcome::new(class, diagnostics~, stderr~)
    assert_eq(outcome.class, class)
    assert_eq(outcome.diagnostics, diagnostics)
    assert_true(outcome.stderr.bytes() == b"warning")
  }
  guard classes[2] is Failed(Guest(data=Some(data), ..)) else {
    fail("lost the JSON-RPC data")
  }
  assert_eq(data, { "field": "id" })
}

///|
test "session report: the host enforces the byte limits; depth and nodes are negotiated" {
  let report = @worker.SessionReport::new(@worker.Limits::host())
  json_inspect(report.to_json(), content={
    "limits": {
      "requestBytes": 6291456,
      "responseBytes": 16777216,
      "model": { "maxEncodedBytes": 5592408, "maxDecodedBytes": 4194304 },
      "negotiated": { "maxDepth": 128, "maxNodes": 100000 },
    },
    "wireCancellation": false,
  })
}

///|
test "call instructions: Limits::new accepts 1 to 9007199254740991 and refuses 0, -1 and 9007199254740992" {
  let model = @worker.Limits::host().model
  let make = (count : Int64) => {
    @worker.Limits::new(
      request_bytes=1,
      response_bytes=1,
      model~,
      call_instructions=count,
    ).call_instructions.count
  }
  assert_eq(@worker.max_call_instructions, 9007199254740991L)
  assert_eq(make(1L), 1L)
  assert_eq(make(2147483648L), 2147483648L)
  assert_eq(make(5000000000L), 5000000000L)
  assert_eq(make(9007199254740991L), 9007199254740991L)
  for count in [0L, -1L, 9007199254740992L] {
    guard (Ok(make(count)) catch { e => Err(e) }) is Err(InvalidLimit(_)) else {
      fail("accepted call_instructions=\{count}")
    }
  }
}

///|
test "a message records the size of its encoded JSON" {
  let message = @worker.Message::new({ "id": 1, "text": "é" })
  assert_eq(message.size(), message.to_bytes().length())
  assert_eq(@worker.Message::parse(message.to_bytes()).json(), message.json())
}

///|
test "a message body must be a UTF-8 JSON object" {
  for bytes in [b"{", b"\xff\xfe", b"[1]", b"\"text\"", b"null"] {
    guard (Ok(@worker.Message::parse(bytes)) catch { e => Err(e) })
      is Err(FrameInvalid(_)) else {
      fail("accepted a message that is not a JSON object")
    }
  }
}

///|
test "a stop names how the worker ended and keeps its stderr" {
  let stop = @worker.WorkerStop::new(
    Signalled(signal=9),
    stop_method=GroupSignal,
    stderr=@worker.StderrTail::of(b"killed"),
  )
  assert_eq(stop.status, Signalled(signal=9))
  assert_eq(stop.stop_method, GroupSignal)
  assert_true(stop.stderr.bytes() == b"killed")
  assert_true(stop.status != Exited(code=9))
}

///|
test "launch errors carry typed details" {
  let expected = @worker.Sha256::of(b"a")
  let actual = @worker.Sha256::of(b"b")
  let errors : Array[@worker.LaunchError] = [
    DigestMismatch(expected~, actual~),
    ArtifactUnreadable(SymbolicLink),
    ArtifactUnreadable(Unreadable(detail=Some("permission denied"))),
    AbiUnsupported(
      @worker.ImportName::new("wasi_snapshot_preview1", "fd_write"),
    ),
    AbiMismatch(declared=ExtismKernelV1, classified=MorphirBytesV1),
    WasmFeatureUnsupported(feature=None),
    RuntimeUnavailable(supported=[Wasm]),
  ]
  assert_eq(errors.length(), 7)
  assert_eq(
    @worker.ImportName::new("extism:host/env", "var_get").to_string(),
    "extism:host/env.var_get",
  )
}

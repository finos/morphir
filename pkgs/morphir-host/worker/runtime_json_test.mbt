///|
fn runtime_error(value : Json) -> @worker.ValueError? {
  try @worker.WorkerRuntime::from_json(value) catch {
    error => Some(error)
  } noraise {
    _ => None
  }
}

///|
test "worker specification: a pin decodes into a typed specification" {
  let pin : Json = {
    "contractVersion": "0.2.0",
    "artifact": {
      "path": "/work/python/morphir-python-binding-0.4.2.wasm",
      "sha256": digest,
    },
    "runtime": { "kind": "wasm", "abi": "extism-kernel-v1" },
    "origin": "finos/morphir-python extension/python/v0.4.2",
  }
  let spec = @worker.WorkerSpec::from_json(pin, Posix)
  assert_eq(spec.runtime, Wasm(abi=Some(ExtismKernelV1)))
  assert_eq(spec.artifact.sha256.to_string(), digest)
  guard spec.artifact.source is File(path) else { fail("not a file") }
  assert_eq(path.to_string(), "/work/python/morphir-python-binding-0.4.2.wasm")
  assert_eq(
    @worker.WorkerRuntime::from_json({ "kind": "wasm" }),
    Wasm(abi=None),
  )
}

///|
test "worker specification: a process runtime keeps its arguments unchanged" {
  let runtime : Json = {
    "kind": "process",
    "platform": "x86_64-unknown-linux-musl",
    "args": ["--serve", "", "--", "a b"],
  }
  let decoded = @worker.WorkerRuntime::from_json(runtime)
  assert_eq(
    decoded,
    Process(platform=X86_64UnknownLinuxMusl, args=["--serve", "", "--", "a b"]),
  )
  // The catalog writes the same form back.
  assert_eq(decoded.to_json(), runtime)
  assert_eq(@worker.WorkerRuntime::Wasm(abi=Some(MorphirBytesV1)).to_json(), {
    "kind": "wasm",
    "abi": "morphir-bytes-v1",
  })
}

///|
test "worker specification: mixed runtimes are refused" {
  let cases : Array[Json] = [
    {
      "kind": "process",
      "platform": "aarch64-apple-darwin",
      "args": [],
      "abi": "extism-kernel-v1",
    },
    { "kind": "wasm", "platform": "aarch64-apple-darwin" },
    { "kind": "wasm", "args": [] },
  ]
  for mixed in cases {
    guard runtime_error(mixed) is Some(InvalidRuntime(_)) else {
      fail("accepted a runtime with members of both kinds")
    }
  }
}

///|
test "worker specification: malformed runtimes are refused" {
  let cases : Array[Json] = [
    { "kind": "process", "platform": "aarch64-apple-darwin" },
    { "kind": "process", "args": [] },
    { "kind": "process", "platform": "aarch64-apple-darwin", "args": [1] },
    { "kind": "native" },
    { "platform": "aarch64-apple-darwin" },
    "wasm",
  ]
  for value in cases {
    guard runtime_error(value) is Some(InvalidRuntime(_)) else {
      fail("accepted a malformed runtime")
    }
  }
  // Only the eight target triples name a platform.
  guard runtime_error({ "kind": "process", "platform": "linux-x64", "args": [] })
    is Some(UnknownPlatform("linux-x64")) else {
    fail("accepted an unknown platform")
  }
  guard runtime_error({ "kind": "wasm", "abi": "wasi-p1" })
    is Some(UnknownWasmAbi(_)) else {
    fail("accepted an unknown ABI")
  }
}

///|
test "worker specification: an artifact without a digest is refused" {
  let spec : Json = {
    "artifact": { "path": "/opt/morphir/elm" },
    "runtime": { "kind": "wasm" },
  }
  let refused = try @worker.WorkerSpec::from_json(spec, Posix) catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  guard refused is Some(InvalidArtifact(_)) else {
    fail("accepted an artifact without a digest")
  }
  // A Windows host reads Windows paths.
  let windows = @worker.WorkerSpec::from_json(
    {
      "artifact": { "path": "C:\\morphir\\elm.exe", "sha256": digest },
      "runtime": {
        "kind": "process",
        "platform": "x86_64-pc-windows-msvc",
        "args": [],
      },
    },
    Windows,
  )
  assert_eq(windows.runtime.kind(), Process)
}

///|
test "worker specification: an artifact with another member is refused" {
  let artifact : Json = { "path": "/stage/elm", "sha256": digest, "url": "x" }
  let refused = try @worker.ArtifactRef::from_json(artifact, Posix) catch {
    error => Some(error)
  } noraise {
    _ => None
  }
  guard refused is Some(InvalidArtifact(_)) else {
    fail("accepted an artifact with an unknown member")
  }
}

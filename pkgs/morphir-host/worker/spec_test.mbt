///|
let digest : String = "6ed5e96fa9c7f7dcaa179efc88e517307463cfeddc5e2eeae854f0395e7a4ec6"

///|
test "a SHA-256 digest is 64 lowercase hexadecimal digits" {
  assert_eq(@worker.Sha256::parse(digest).to_string(), digest)
  for
    text in [
      "",
      "6ed5",
      digest + "0",
      digest.to_upper(),
      "g" + digest[1:].to_owned(),
    ] {
    guard (Ok(@worker.Sha256::parse(text)) catch { e => Err(e) })
      is Err(InvalidSha256(_)) else {
      fail("accepted digest \{text}")
    }
  }
}

///|
test "a SHA-256 digest can be computed from bytes" {
  assert_eq(
    @worker.Sha256::of(b"abc").to_string(),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "an artifact path must be absolute in the host's path style" {
  for text in ["/opt/morphir/extension", "/"] {
    assert_eq(@worker.ArtifactPath::parse(text, Posix).to_string(), text)
  }
  for
    text in [
      "C:\\morphir\\extension.exe", "c:/morphir/extension.exe", "\\\\server\\share\\extension.wasm",
    ] {
    assert_eq(@worker.ArtifactPath::parse(text, Windows).to_string(), text)
  }
  let refused : Array[(String, @worker.PathStyle)] = [
    ("", Posix),
    ("extension.wasm", Posix),
    ("./extension", Posix),
    ("C:\\morphir\\extension.exe", Posix),
    ("/opt/\u0000x", Posix),
    ("", Windows),
    ("C:extension", Windows),
    ("\\morphir\\extension.exe", Windows),
    ("\\\\", Windows),
    ("\\\\\\share", Windows),
    ("/opt/morphir/extension", Windows),
  ]
  for case in refused {
    let (text, style) = case
    guard (Ok(@worker.ArtifactPath::parse(text, style)) catch { e => Err(e) })
      is Err(InvalidArtifactPath(_)) else {
      fail("accepted path \{text}")
    }
  }
}

///|
test "platforms are the eight release target triples" {
  let triples = [
    "aarch64-apple-darwin", "x86_64-apple-darwin", "aarch64-unknown-linux-gnu", "x86_64-unknown-linux-gnu",
    "aarch64-unknown-linux-musl", "x86_64-unknown-linux-musl", "aarch64-pc-windows-msvc",
    "x86_64-pc-windows-msvc",
  ]
  for triple in triples {
    assert_eq(@worker.Platform::parse(triple).to_string(), triple)
  }
  assert_eq(@worker.Platform::X86_64UnknownLinuxMusl.path_style(), Posix)
  assert_eq(@worker.Platform::Aarch64PcWindowsMsvc.path_style(), Windows)
  for text in ["linux-x64", "darwin-arm64", "x86_64-unknown-linux", ""] {
    guard (Ok(@worker.Platform::parse(text)) catch { e => Err(e) })
      is Err(UnknownPlatform(_)) else {
      fail("accepted platform \{text}")
    }
  }
}

///|
test "WASM ABIs are a closed set" {
  assert_eq(
    @worker.WasmAbi::parse("extism-kernel-v1"),
    @worker.WasmAbi::ExtismKernelV1,
  )
  assert_eq(@worker.WasmAbi::MorphirBytesV1.to_string(), "morphir-bytes-v1")
  guard (Ok(@worker.WasmAbi::parse("wasi-p1")) catch { e => Err(e) })
    is Err(UnknownWasmAbi(_)) else {
    fail("accepted an unknown ABI")
  }
}

///|
test "a worker specification names a digest and exactly one runtime" {
  let artifact = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse("/opt/morphir/elm", Posix)),
    @worker.Sha256::parse(digest),
  )
  let args = ["serve", "", "--"]
  let spec = @worker.WorkerSpec::new(
    artifact,
    Process(platform=X86_64UnknownLinuxGnu, args~),
  )
  // The specification keeps its own copy of the arguments.
  args.push("--later")
  assert_eq(spec.artifact.sha256.to_string(), digest)
  guard spec.runtime is Process(platform~, args~) else { fail("not a process") }
  assert_eq(platform, X86_64UnknownLinuxGnu)
  // Arguments are opaque: delimiters and empty values stay as recorded.
  assert_eq(args, ["serve", "", "--"])
  assert_eq(spec.runtime.kind(), Process)
  let bytes = @worker.WorkerSpec::new(
    @worker.ArtifactRef::new(Memory(b"\x00asm"), @worker.Sha256::of(b"\x00asm")),
    Wasm(abi=None),
  )
  assert_true(bytes.runtime is Wasm(abi=None))
  assert_eq(bytes.runtime.kind(), Wasm)
  assert_eq(@worker.RuntimeKind::Wasm.to_string(), "wasm")
}

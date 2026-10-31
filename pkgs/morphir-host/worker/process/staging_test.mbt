///|
fn file_artifact(path : String, bytes : Bytes) -> @worker.ArtifactRef raise {
  @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse(path, Posix)),
    @worker.Sha256::of(bytes),
  )
}

///|
test "verified bytes keep the digest of the bytes that were read" {
  let artifact = file_artifact("/opt/ext/bin/worker", b"#!/bin/sh\n")
  let verified = @process.VerifiedArtifact::check(b"#!/bin/sh\n", artifact)
  assert_eq(verified.digest(), @worker.Sha256::of(b"#!/bin/sh\n"))
  assert_eq(verified.bytes(), b"#!/bin/sh\n")
  assert_eq(verified.file_name(), "worker")
}

///|
test "a digest mismatch refuses the bytes that were read" {
  let artifact = file_artifact("/opt/ext/bin/worker", b"verified")
  let refused = try {
    ignore(@process.VerifiedArtifact::check(b"replaced", artifact))
    None
  } catch {
    error => Some(error)
  }
  assert_eq(
    refused,
    Some(
      @worker.DigestMismatch(
        expected=@worker.Sha256::of(b"verified"),
        actual=@worker.Sha256::of(b"replaced"),
      ),
    ),
  )
}

///|
test "bytes above the artifact limit are refused before hashing" {
  let artifact = file_artifact("/opt/ext/bin/worker", b"")
  assert_eq(
    @process.check_artifact_size(@process.ARTIFACT_LIMIT_BYTES.to_int64() + 1L),
    Some(@worker.TooLarge),
  )
  assert_eq(
    @process.check_artifact_size(@process.ARTIFACT_LIMIT_BYTES.to_int64()),
    None,
  )
  let verified = @process.VerifiedArtifact::check(b"", artifact)
  assert_eq(verified.bytes().length(), 0)
}

///|
test "the private copy keeps the artifact's file name" {
  let windows = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse("C:\\ext\\worker.exe", Windows)),
    @worker.Sha256::of(b"MZ"),
  )
  assert_eq(
    @process.VerifiedArtifact::check(b"MZ", windows).file_name(),
    "worker.exe",
  )
  let memory = @worker.ArtifactRef::new(
    Memory(b"\x00asm"),
    @worker.Sha256::of(b"\x00asm"),
  )
  assert_eq(
    @process.VerifiedArtifact::check(b"\x00asm", memory).file_name(),
    "artifact",
  )
  let dots = file_artifact("/opt/ext/..", b"x")
  assert_eq(
    @process.VerifiedArtifact::check(b"x", dots).file_name(),
    "artifact",
  )
}

///|
test "a staged artifact names its private copy and working directory" {
  let artifact = file_artifact("/opt/ext/bin/worker", b"bytes")
  let staged = @process.VerifiedArtifact::check(b"bytes", artifact).staged(
    directory="/tmp/morphir-worker-1",
    executable="/tmp/morphir-worker-1/bin/worker",
    working_directory="/tmp/morphir-worker-1/work",
  )
  assert_eq(staged.directory(), "/tmp/morphir-worker-1")
  assert_eq(staged.executable(), "/tmp/morphir-worker-1/bin/worker")
  assert_eq(staged.working_directory(), "/tmp/morphir-worker-1/work")
  assert_eq(staged.digest(), @worker.Sha256::of(b"bytes"))
}

///|
test "the staging layout keeps the copy in bin, apart from work" {
  let artifact = file_artifact("/opt/ext/bin/work", b"bytes")
  let staged = @process.VerifiedArtifact::check(b"bytes", artifact).stage_in(
    directory="/tmp/morphir-worker-1",
    style=Posix,
  )
  assert_eq(staged.directory(), "/tmp/morphir-worker-1")
  assert_eq(staged.executable(), "/tmp/morphir-worker-1/bin/work")
  assert_eq(staged.working_directory(), "/tmp/morphir-worker-1/work")
  let windows = @worker.ArtifactRef::new(
    File(@worker.ArtifactPath::parse("C:\\ext\\worker.exe", Windows)),
    @worker.Sha256::of(b"MZ"),
  )
  let staged = @process.VerifiedArtifact::check(b"MZ", windows).stage_in(
    directory="C:\\Temp\\morphir-worker-1\\",
    style=Windows,
  )
  assert_eq(staged.executable(), "C:\\Temp\\morphir-worker-1\\bin\\worker.exe")
  assert_eq(staged.working_directory(), "C:\\Temp\\morphir-worker-1\\work")
  assert_eq(staged.directory(), "C:\\Temp\\morphir-worker-1")
}

///|
test "a Windows copy of an artifact without an extension is named .exe" {
  let artifact = file_artifact("/opt/ext/bin/worker", b"MZ")
  let verified = @process.VerifiedArtifact::check(b"MZ", artifact)
  assert_eq(verified.copy_name(Windows), "worker.exe")
  assert_eq(verified.copy_name(Posix), "worker")
  assert_eq(
    verified
    .stage_in(directory="C:\\Temp\\morphir-worker-1", style=Windows)
    .executable(),
    "C:\\Temp\\morphir-worker-1\\bin\\worker.exe",
  )
  assert_eq(
    verified
    .stage_in(directory="/tmp/morphir-worker-1", style=Posix)
    .executable(),
    "/tmp/morphir-worker-1/bin/worker",
  )
  // A name with an extension keeps it, whatever the extension is.
  for name in ["worker.exe", "worker.EXE", "worker.cmd", "my.worker.com"] {
    let named = file_artifact("/opt/ext/bin/\{name}", b"MZ")
    assert_eq(
      @process.VerifiedArtifact::check(b"MZ", named).copy_name(Windows),
      name,
    )
  }
  // A dot that only starts the name or ends it is not an extension.
  for name in [".worker", "worker."] {
    let named = file_artifact("/opt/ext/bin/\{name}", b"MZ")
    assert_eq(
      @process.VerifiedArtifact::check(b"MZ", named).copy_name(Windows),
      "\{name}.exe",
    )
  }
  let memory = @worker.ArtifactRef::new(
    Memory(b"MZ"),
    @worker.Sha256::of(b"MZ"),
  )
  assert_eq(
    @process.VerifiedArtifact::check(b"MZ", memory).copy_name(Windows),
    "artifact.exe",
  )
}

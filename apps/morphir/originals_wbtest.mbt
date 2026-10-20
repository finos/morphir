///|
#cfg(any(target="js", target="native"))
test "originals publication honors a marker or deadline after helper release" {
  if @platform.system_type() == "windows" {
    return
  }
  for reason in ["cancel", "timeout"] {
    let scratch = @platform.temporary()
    let owner = @platform.temporary()
    defer @platform.remove_dir(owner)
    let marker = owner + "/cancel"
    if reason == "cancel" {
      @platform.write(marker, "late cancellation")
    }
    let output = ".dev/originals-publication-" +
      @identity.sha256(@utf8.encode(scratch))
    let capture : Json = {
      "sha256": "fixture",
      "fileCount": 0,
      "directoryCount": 0,
      "sourceByteLength": 0,
      "sourceFormatVersion": { "status": "not-reported" },
    }
    @platform.write(
      scratch + "/inventory.json",
      ({ "capture": capture, "entries": [] } : Json).stringify(),
    )
    let report : Json = {
      "profile": "morphir/cli/originals-command",
      "contractVersion": "0.1.0",
      "operation": "originals",
      "observation": "verified",
      "cleanup": { "kind": "released" },
      "inventorySha256": "fixture",
      "fileCount": 0,
      "directoryCount": 0,
      "sourceByteLength": 0,
    }
    let code = originals_finish(report.stringify(), 0, scratch, output, JSON, {
      deadline: if reason == "timeout" {
        0.0
      } else {
        @platform.monotonic_seconds() + 60.0
      },
      cancel_file: if reason == "cancel" {
        marker
      } else {
        ""
      },
    })
    assert_eq(code, if reason == "cancel" { 130 } else { 1 })
    assert_eq(@platform.kind(output), 0)
    assert_eq(@platform.kind(scratch), 0)
    if reason == "cancel" {
      @platform.remove_file(marker)
    }
  }
}

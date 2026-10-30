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
    let observed : Array[String] = []
    let code = originals_finish(
      report.stringify(),
      0,
      scratch,
      output,
      JSON,
      {
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
      },
      Some({
        commit: (_, _) => observed.push("unexpected commit"),
        cleanup: (path, returned) => {
          assert_eq(path, scratch) catch {
            _ => abort("wrong cleanup path")
          }
          observed.push(if returned { "cleaned" } else { "failed cleanup" })
        },
      }),
    )
    assert_eq(code, if reason == "cancel" { 130 } else { 1 })
    assert_eq(@platform.kind(output), 0)
    assert_eq(@platform.kind(scratch), 0)
    assert_eq(observed, ["cleaned"])
    if reason == "cancel" {
      @platform.remove_file(marker)
    }
  }
}

///|
#cfg(any(target="js", target="native"))
test "originals observations follow actual destination commit and scratch cleanup outcomes" {
  if @platform.system_type() == "windows" {
    return
  }
  for cleanup_failure in [false, true] {
    let owner = @platform.temporary()
    let scratch = @platform.temporary()
    let output = ".dev/originals-observed-" +
      @identity.sha256(@utf8.encode(owner))
    let destination = output + "/originals"
    let bytes = @utf8.encode("# exact original\r\nformatVersion: 4\r\n")
    let digest = @identity.sha256(bytes)
    let capture : Json = {
      "sha256": "fixture",
      "fileCount": 1,
      "directoryCount": 0,
      "sourceByteLength": bytes.length(),
      "sourceFormatVersion": { "status": "not-reported" },
    }
    @platform.mkdir(scratch + "/part-0")
    @platform.write_bytes(scratch + "/part-0/file-0", bytes)
    @platform.write(scratch + "/cleanup-count", "1")
    @platform.write(
      scratch + "/inventory.json",
      (
        {
          "capture": capture,
          "entries": [
            {
              "kind": "file",
              "path": "model.yaml",
              "byteLength": bytes.length(),
              "sha256": digest,
            },
          ],
        } : Json).stringify(),
    )
    let report : Json = {
      "profile": "morphir/cli/originals-command",
      "contractVersion": "0.1.0",
      "operation": "originals",
      "observation": "verified",
      "cleanup": { "kind": "released" },
      "inventorySha256": "fixture",
      "fileCount": 1,
      "directoryCount": 0,
      "sourceByteLength": bytes.length(),
    }
    let observed : Array[(String, Bool, Int32, Int32)] = []
    let code = originals_finish(
      report.stringify(),
      0,
      scratch,
      output,
      JSON,
      { deadline: @platform.monotonic_seconds() + 60.0, cancel_file: "", },
      Some({
        commit: (path, returned) => {
          observed.push(
            (
              path,
              returned,
              @platform.kind(destination + "/model.yaml") catch {
                _ => -1
              },
              @platform.kind(scratch) catch {
                _ => -1
              },
            ),
          )
          if cleanup_failure {
            @platform.write(scratch + "/cleanup-count", "invalid") catch {
              _ => abort("fixture write failed")
            }
          }
        },
        cleanup: (path, returned) => {
          observed.push(
            (
              path,
              returned,
              @platform.kind(destination + "/model.yaml") catch {
                _ => -1
              },
              @platform.kind(scratch) catch {
                _ => -1
              },
            ),
          )
        },
      }),
    )
    assert_eq(code, if cleanup_failure { 1 } else { 0 })
    assert_eq(observed, [
      (destination, true, 1, 2),
      (scratch, !cleanup_failure, 1, if cleanup_failure { 2 } else { 0 }),
    ])
    assert_eq(@platform.read_input(destination + "/model.yaml", 1024), bytes)
    if cleanup_failure {
      @platform.remove_file(scratch + "/part-0/file-0")
      @platform.remove_dir(scratch + "/part-0")
      @platform.remove_file(scratch + "/cleanup-count")
      @platform.remove_file(scratch + "/inventory.json")
      @platform.remove_dir(scratch)
    }
    @platform.remove_file(destination + "/model.yaml")
    @platform.remove_dir(destination)
    @platform.remove_dir(output)
    @platform.remove_dir(owner)
  }
}

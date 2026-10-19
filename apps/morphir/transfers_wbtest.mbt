///|
#cfg(any(target="js", target="native"))
test "transfer refuses a complete inventory with one corrupt file before publication" {
  let scratch = @platform.temporary()
  defer transfer_cleanup(scratch)
  @platform.write_bytes(scratch + "/file-0", b"first")
  @platform.write_bytes(scratch + "/file-1", b"corrupt")
  let output = ".transfer-test-" + scratch.split("/").last().unwrap().to_owned()
  let inventory : Json = {
    "observation": "verified",
    "cleanup": { "kind": "released", "generationId": "captured-generation" },
    "files": [
      {
        "path": "one.bin",
        "byteLength": 5,
        "sha256": @identity.sha256(b"first"),
      },
      {
        "path": "two.bin",
        "byteLength": 7,
        "sha256": @identity.sha256(b"correct"),
      },
    ],
  }
  let refused = try {
    ignore(transfer_publish(inventory, scratch, output))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  assert_eq(@platform.kind(output), 0)
}

///|
#cfg(any(target="js", target="native"))
test "transfer requires confirmed release before opening publication" {
  let scratch = @platform.temporary()
  defer transfer_cleanup(scratch)
  let output = ".transfer-test-" + scratch.split("/").last().unwrap().to_owned()
  let inventory : Json = {
    "observation": "verified",
    "cleanup": { "kind": "connection-closed" },
    "files": [],
  }
  let refused = try {
    ignore(transfer_publish(inventory, scratch, output))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  assert_eq(@platform.kind(output), 0)
}

///|
#cfg(any(target="js", target="native"))
test "transfer publishes verified NUL and empty bytes and refuses replacement" {
  let scratch = @platform.temporary()
  defer transfer_cleanup(scratch)
  @platform.write_bytes(scratch + "/file-0", b"\x00\xffA")
  @platform.write_bytes(scratch + "/file-1", b"")
  let output = ".transfer-test-" + scratch.split("/").last().unwrap().to_owned()
  defer @platform.remove_dir(output)
  let destination = output + "/artifacts"
  defer @platform.remove_dir(destination)
  defer @platform.remove_file(destination + "/binary.dat")
  defer @platform.remove_file(destination + "/empty.dat")
  let inventory : Json = {
    "observation": "verified",
    "cleanup": { "kind": "released", "generationId": "captured-generation" },
    "files": [
      {
        "path": "binary.dat",
        "byteLength": 3,
        "sha256": @identity.sha256(b"\x00\xffA"),
      },
      { "path": "empty.dat", "byteLength": 0, "sha256": @identity.sha256(b"") },
    ],
  }
  let report = transfer_publish(inventory, scratch, output)
  assert_true(
    report
    is { "publication": String("cli"), "observation": String("published"), .. },
  )
  assert_eq(@platform.read_input(destination + "/binary.dat", 3), b"\x00\xffA")
  assert_eq(@platform.read_input(destination + "/empty.dat", 1), b"")
  let refused = try {
    ignore(transfer_publish(inventory, scratch, output))
    false
  } catch {
    _ => true
  }
  assert_true(refused)
  assert_eq(@platform.read_input(destination + "/binary.dat", 3), b"\x00\xffA")
}

///|
#cfg(any(target="js", target="native"))
test "transfer validates the full portable path set before reading any scratch bytes" {
  let scratch = @platform.temporary()
  defer transfer_cleanup(scratch)
  let output = ".transfer-test-" + scratch.split("/").last().unwrap().to_owned()
  for
    paths in [
      ["../escape"],
      ["One.bin", "one.bin"],
      ["a", "a/b"],
      ["A/a", "a/b"],
    ] {
    let report : Json = {
      "observation": "verified",
      "cleanup": { "kind": "released" },
      "files": paths.map(path => {
        (
          { "path": path, "byteLength": 0, "sha256": @identity.sha256(b"") } :
          Json)
      }),
    }
    let rejected_before_read = try {
      ignore(transfer_publish(report, scratch, output))
      false
    } catch {
      @model_document.InvalidFilename => true
      _ => false
    }
    assert_true(rejected_before_read)
  }
  assert_eq(@platform.kind(output), 0)
}

///|
#cfg(any(target="js", target="native"))
test "transfer charges complete declared bytes before any scratch read" {
  let scratch = @platform.temporary()
  defer transfer_cleanup(scratch)
  let output = ".transfer-test-" + scratch.split("/").last().unwrap().to_owned()
  let report : Json = {
    "observation": "verified",
    "cleanup": { "kind": "released" },
    "files": [0, 1, 2, 3, 4].map(i => {
      (
        {
          "path": i.to_string() + ".bin",
          "byteLength": 16777216,
          "sha256": @identity.sha256(b""),
        } : Json)
    }),
  }
  let refused_before_read = try {
    ignore(transfer_publish(report, scratch, output))
    false
  } catch {
    @config.Invalid("transfer.inventory_limit") => true
    _ => false
  }
  assert_true(refused_before_read)
  assert_eq(@platform.kind(output), 0)
}

///|
#cfg(any(target="js", target="native"))
test "transfer native boundary retains the exact artifact 256 file cap" {
  let scratch = @platform.temporary()
  defer transfer_cleanup(scratch)
  let output = ".transfer-test-" + scratch.split("/").last().unwrap().to_owned()
  let files : Array[Json] = []
  for index in 0..<257 {
    files.push({
      "path": index.to_string() + ".bin",
      "byteLength": 0,
      "sha256": @identity.sha256(b""),
    })
  }
  let report : Json = {
    "observation": "verified",
    "cleanup": { "kind": "released" },
    "files": Json::array(files),
  }
  let refused = try {
    ignore(transfer_publish(report, scratch, output))
    false
  } catch {
    @config.Invalid("transfer.invalid_inventory") => true
    _ => false
  }
  assert_true(refused)
  assert_eq(@platform.kind(output), 0)
}

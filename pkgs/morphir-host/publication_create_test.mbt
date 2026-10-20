///|
#cfg(any(target="js", target="native"))
test "create-only inventory commit preserves a destination created during staging" {
  if @platform.system_type() == "windows" {
    return
  }
  let root = @platform.temporary()
  defer verification_remove(root)
  let publisher = @host.ContentPublisher::filesystem_inventory(
    root,
    "out",
    [],
    destination_policy=@host.DestinationPolicy::Create,
  )
  let transaction = (publisher.begin)(["out/originals"])
  defer (transaction.abort)()
  (transaction.stage)({
    path: "out/originals/new.bin",
    source: "fixture",
    format: "bytes",
    content: @data.Binary(b"new"),
  })
  @platform.mkdir(root + "/out/originals")
  @platform.write(root + "/out/originals/keep.txt", "another writer")
  assert_true(
    try {
      (transaction.commit)("out/originals")
      false
    } catch {
      _ => true
    },
  )
  assert_eq(@platform.read(root + "/out/originals/keep.txt"), "another writer")
  assert_eq(@platform.kind(root + "/out/originals/new.bin"), 0)
}

///|
#cfg(any(target="js", target="native"))
test "create-only inventory commit publishes a complete new destination" {
  if @platform.system_type() == "windows" {
    return
  }
  let root = @platform.temporary()
  defer verification_remove(root)
  let publisher = @host.ContentPublisher::filesystem_inventory(
    root,
    "out",
    ["out/originals/empty"],
    destination_policy=@host.DestinationPolicy::Create,
  )
  let transaction = (publisher.begin)(["out/originals"])
  defer (transaction.abort)()
  (transaction.stage)({
    path: "out/originals/new.bin",
    source: "fixture",
    format: "bytes",
    content: @data.Binary(b"\x00\xff"),
  })
  (transaction.commit)("out/originals")
  assert_eq(@platform.read_bytes(root + "/out/originals/new.bin"), b"\x00\xff")
  assert_eq(@platform.kind(root + "/out/originals/empty"), 2)
}

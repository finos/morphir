///|
#cfg(target="native")
test "a failed compile replacement restores the bytes and leaves a tombstone" {
  if @platform.system_type() == "windows" {
    return
  }
  let root = @platform.temporary()
  defer dispose_build_tree(root)
  let destination = "out/compile.dest"
  let options : CompileRecordOptions = {
    explicit_selection: false,
    tree_product: Some("model"),
  }
  let publisher = ContentPublisher::filesystem(
    root,
    "out",
    compile_record=options,
  )
  let publish = (publisher.begin)([destination])
  let manifest = "{\"formatVersion\":4}"
  (publish.stage)({
    path: destination + "/model/manifest.json",
    content: @data.Text(manifest),
    format: "morphir-json",
    ir_json_version: Some(@version.FormatVersion::baseline(4U)),
    source: "fixture",
  })
  (publish.commit)(destination)
  (publish.abort)()
  let record_path = root + "/out/compile.json"
  let record = @wire.parse_bounded(@platform.read(record_path))
  let fields = @wire.object(record)
  fields["installed"] = { "/previous/install": ["manifest.json"] }
  @platform.write(record_path, record.stringify())

  let fail_publish = filesystem_content_publisher(
    root,
    "out",
    (source, destination) => {
      if source.contains("/.morphir-publish.lock/stage/") {
        raise @platform.IOError("fixture.staged_rename_failed")
      }
      @platform.rename(source, destination)
    },
    compile_record={ explicit_selection: false, tree_product: None, },
  )
  let publication = (fail_publish.begin)([destination])
  (publication.stage)({
    path: destination + "/replacement.json",
    content: @data.Text("replacement"),
    format: "morphir-json",
    ir_json_version: None,
    source: "fixture",
  })
  let failure = try {
    (publication.commit)(destination)
    ""
  } catch {
    error => error_message(error)
  }
  (publication.abort)()
  assert_eq(failure, "fixture.staged_rename_failed")
  assert_eq(
    @platform.read(root + "/" + destination + "/model/manifest.json"),
    manifest,
  )
  assert_eq(@platform.kind(root + "/" + destination + "/replacement.json"), 0)
  assert_eq(@platform.kind(root + "/out/.morphir-publish.lock"), 0)
  let tombstone = @wire.parse_bounded(@platform.read(record_path))
  assert_eq(@wire.field(tombstone, "tombstone"), Json::boolean(true))
  assert_eq(@wire.field(tombstone, "completedAt"), fields["completedAt"])
  assert_eq(@wire.field(tombstone, "installed"), fields["installed"])
  assert_eq(@wire.field(tombstone, "value"), Json::array([]))
  assert_eq(@wire.optional(tombstone, "ir"), None)
  let out = @platform.BoundedDirectory::open(root + "/out")
  defer out.close()
  let lease = out.try_task_lease("compile.lock", exclusive=true).unwrap()
  lease.close()
}

///|
#cfg(target="native")
test "compile result describes the version in the admitted JSON product" {
  if @platform.system_type() == "windows" {
    return
  }
  let root = @platform.temporary()
  defer dispose_build_tree(root)
  for version in [1, 2, 3, 4] {
    let out = "result-\{version}"
    let dest = out + "/compile.dest"
    let publisher = ContentPublisher::filesystem(root, out, compile_record={
      explicit_selection: false,
      tree_product: None,
    })
    let publication = (publisher.begin)([dest])
    defer (publication.abort)()
    let product = dest + "/model.json"
    let content = "{\"formatVersion\":\{version}}"
    (publication.stage)({
      path: product,
      source: "fixture",
      format: if version == 4 {
        "morphir-json"
      } else {
        "ir-json"
      },
      content: @data.Text(content),
      ir_json_version: Some(
        @version.FormatVersion::baseline(version.reinterpret_as_uint()),
      ),
    })
    (publication.commit)(dest)
    let record = @wire.parse_bounded(
      @platform.read(root + "/" + out + "/compile.json"),
    )
    let ir = @wire.field(record, "ir")
    assert_eq(@wire.field(ir, "version"), Json::string("v\{version}"))
    assert_eq(@platform.read(root + "/" + product), content)
  }
}

///|
#cfg(target="native")
test "compile publication preserves version metadata without parsing the artifact body" {
  if @platform.system_type() == "windows" {
    return
  }
  let root = @platform.temporary()
  defer dispose_build_tree(root)
  let publisher = ContentPublisher::filesystem(root, "out", compile_record={
    explicit_selection: false,
    tree_product: None,
  })
  let destination = "out/compile.dest"
  let publication = (publisher.begin)([destination])
  defer (publication.abort)()
  // Valid JSON with a body deliberately beyond the full parser's depth.
  let content = "{\"formatVersion\":3,\"distribution\":" +
    "[".repeat(1024) +
    "null" +
    "]".repeat(1024) +
    "}"
  let full_parse_refused = try {
    ignore(@wire.parse(content))
    false
  } catch {
    @wire.Invalid(_, detail) => detail.contains("Depth")
  }
  assert_true(full_parse_refused)
  let product = destination + "/large.json"
  (publication.stage)({
    path: product,
    source: "writer",
    format: "ir-json",
    content: @data.Text(content),
    ir_json_version: Some(@version.FormatVersion::baseline(3U)),
  })
  (publication.commit)(destination)
  assert_eq(@platform.read(root + "/" + product), content)
  let record = @wire.parse_bounded(@platform.read(root + "/out/compile.json"))
  assert_eq(
    @wire.field(@wire.field(record, "ir"), "version"),
    Json::string("v3"),
  )
}

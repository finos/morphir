///|
fn remove_capture_test_path(path : String) -> Unit raise {
  if @platform.kind(path) == 2 {
    for name in @platform.list(path) {
      remove_capture_test_path(path + "/" + name)
    }
    @platform.remove_dir(path)
  } else {
    @platform.remove_file(path)
  }
}

///|
fn with_capture_test_root(
  run : (String, @platform.BoundedDirectory) -> Unit raise,
) -> Unit raise {
  if @platform.system_type() == "windows" {
    return
  }
  let path = @platform.temporary()
  defer (remove_capture_test_path(path) catch { _ => () })
  let directory = @platform.BoundedDirectory::open(path)
  defer directory.close()
  run(path, directory)
}

///|
let capture_manifest : Bytes = b"{\"formatVersion\":4,\"distribution\":\"Library\",\"package\":\"acme/orders\",\"pathBudget\":512}"

///|
let modified_manifest : Bytes = b"{\"formatVersion\":4,\"distribution\":\"Library\",\"package\":\"acme/prices\",\"pathBudget\":512}"

///|
test "explicit tree retains the admitted bytes after a source edit and detects scratch changes" {
  with_capture_test_root((path, directory) => {
    directory.mkdir("tree")
    directory.mkdir("capture")
    let source = directory.child("tree")
    defer source.close()
    let scratch = directory.child("capture")
    defer scratch.close()
    source.write("manifest.json", capture_manifest, offset=0, create=true)
    let captured = capture_tree(
      () => @platform.BoundedDirectory::open(path + "/tree"),
      source,
      scratch,
      directory.stamp(),
      () => (),
    )
    @platform.write_bytes(path + "/tree/manifest.json", modified_manifest)

    let bounded = @yaml.open_bounded_tree(captured.tree_source(() => ()))
    assert_eq(bounded.package_name().to_canonical(), "acme/orders")
    let (_, text) = bounded.read_original_document(@yaml.ManifestArtifact)
    assert_eq(@utf8.encode(text), capture_manifest)

    @platform.write_bytes(path + "/capture/0", modified_manifest)
    let refused = try {
      ignore(bounded.read_original_document(@yaml.ManifestArtifact))
      false
    } catch {
      @yaml.TreeSourceError::RevisionChanged => true
      error => raise error
    }
    assert_true(refused)
  })
}

///|
test "explicit tree refuses different content at the capture verification barrier" {
  with_capture_test_root((path, directory) => {
    directory.mkdir("tree")
    directory.mkdir("capture")
    let source = directory.child("tree")
    defer source.close()
    let scratch = directory.child("capture")
    defer scratch.close()
    source.write("manifest.json", capture_manifest, offset=0, create=true)
    let checks = Ref(0)
    let refused = try {
      ignore(
        capture_tree(
          () => @platform.BoundedDirectory::open(path + "/tree"),
          source,
          scratch,
          directory.stamp(),
          () => {
            checks.val += 1
            // One directory and one file were visited in the copy pass.
            if checks.val == 3 {
              @platform.write_bytes(
                path + "/tree/manifest.json",
                modified_manifest,
              )
            }
          },
        ),
      )
      false
    } catch {
      TreeSource(message) => message.contains("source changed")
      error => raise error
    }
    assert_true(refused)
  })
}

///|
test "bounded output refuses a stage parent inside the source before creating a directory" {
  with_capture_test_root((path, directory) => {
    directory.mkdir("tree")
    let source = directory.child("tree")
    defer source.close()
    let refused = try {
      let stage = TreeStage::open(path + "/tree/out", "inside", source~)
      stage.dispose()
      false
    } catch {
      @platform.IOError("bounded.output_parent_inside_source") => true
      error => raise error
    }
    assert_true(refused)
    assert_true(source.list(0).is_empty())
  })
}

///|
fn test_tree_chunk(
  path : String,
  bytes : Bytes,
  offset~ : Int32 = 0,
  end~ : Bool = true,
) -> @model_access.ArtifactChunk raise {
  @model_access.ArtifactChunk::from_json({
    "path": path,
    "offset": offset,
    "decodedByteLength": bytes.length(),
    "sha256": @identity.sha256(bytes),
    "content": @base64.encode(bytes[:]),
    "end": end,
  })
}

///|
test "bounded output verifies multiple chunks before an exclusive publish" {
  with_capture_test_root((path, directory) => {
    let budget = TreeBudget::from_limits(tree_support().limits)
    let stage = TreeStage::open(path + "/out", "publish")
    defer stage.dispose()
    stage.write(test_tree_chunk("sub/order.txt", b"7", end=false), budget, 0)
    stage.write(test_tree_chunk("sub/order.txt", b"3\n", offset=1), budget, 0)
    assert_false(directory.list(2).contains("out"))
    assert_eq(stage.publish_checked(() => ()), [
      {
        "path": "sub/order.txt",
        "bytes": 3,
        "sha256": @identity.sha256(b"73\n"),
      },
    ])
    assert_eq(@platform.read(path + "/out/sub/order.txt"), "73\n")
  })
}

///|
test "bounded output rejects an incomplete artifact and a changed staged file" {
  with_capture_test_root((path, _directory) => {
    let budget = TreeBudget::from_limits(tree_support().limits)
    let incomplete = TreeStage::open(path + "/incomplete", "incomplete")
    defer incomplete.dispose()
    incomplete.write(test_tree_chunk("order.txt", b"7", end=false), budget, 0)
    let needs_final = try {
      ignore(incomplete.publish_checked(() => ()))
      false
    } catch {
      TreeOutput(message) => message.contains("no final chunk")
      error => raise error
    }
    assert_true(needs_final)

    let changed = TreeStage::open(path + "/changed", "changed")
    defer changed.dispose()
    changed.write(test_tree_chunk("order.txt", b"73\n"), budget, 0)
    @platform.write(path + "/" + changed.temporary + "/order.txt", "74\n")
    let refused_change = try {
      ignore(changed.publish_checked(() => ()))
      false
    } catch {
      TreeOutput(message) => message.contains("digest changed")
      error => raise error
    }
    assert_true(refused_change)
    assert_eq(@platform.kind(path + "/incomplete"), 0)
    assert_eq(@platform.kind(path + "/changed"), 0)
  })
}

///|
test "bounded output leaves an existing destination alone" {
  with_capture_test_root((path, directory) => {
    let budget = TreeBudget::from_limits(tree_support().limits)
    let stage = TreeStage::open(path + "/out", "collision")
    defer stage.dispose()
    stage.write(test_tree_chunk("order.txt", b"73\n"), budget, 0)
    directory.mkdir("out")
    let output = directory.child("out")
    defer output.close()
    output.write("keep.txt", b"existing", offset=0, create=true)
    let raced = try {
      ignore(stage.publish_checked(() => ()))
      false
    } catch {
      @platform.IOError(message) => message.contains("bounded.publish")
      error => raise error
    }
    assert_true(raced)
    assert_eq(output.list(1), ["keep.txt"])
    assert_eq(@platform.read(path + "/out/keep.txt"), "existing")
  })
}

///|
test "bounded output refuses an unreported file in the stage" {
  with_capture_test_root((path, _directory) => {
    let budget = TreeBudget::from_limits(tree_support().limits)
    let stage = TreeStage::open(path + "/out", "extra")
    defer stage.dispose()
    stage.write(test_tree_chunk("order.txt", b"73\n"), budget, 0)
    stage.directory.write("extra", b"unexpected", offset=0, create=true)
    let refused = try {
      ignore(stage.publish_checked(() => ()))
      false
    } catch {
      @platform.IOError("directory.entry_limit") => true
      error => raise error
    }
    assert_true(refused)
    assert_eq(@platform.kind(path + "/out"), 0)
  })
}

///|
test "bounded rejection reports scratch whose cleanup exceeds the depth limit" {
  with_capture_test_root((path, _directory) => {
    let stage = TreeStage::open(path + "/out", "deep")
    let mut directory = stage.temporary
    for _ in 0..<36 {
      directory += "/deep"
      @platform.mkdir(path + "/" + directory)
    }
    let diagnostics : Array[Diagnostic] = []
    stage.dispose(diagnostics~)
    assert_eq(diagnostics.length(), 1)
    assert_eq(diagnostics[0].code, Some("extension.cleanup_unconfirmed"))
    assert_true(diagnostics[0].message.contains("artifact stage"))
    assert_eq(@platform.kind(path + "/out"), 0)
  })
}

///|
test "canonical base64 preflight counts padded and empty payloads without decoding" {
  for
    (content, expected) in [
      ("", 0),
      ("Zg==", 1),
      ("Zm8=", 2),
      ("Zm9v", 3),
      ("+/8=", 2),
    ] {
    assert_eq(canonical_base64_decoded_size(content), expected)
  }
  for
    content in [
      "Zg", "Zh==", "Zm9=", "=m9v", "Z===", "ZZ=Z", "Zm9 ", "éAAA", "A_A/",
    ] {
    let refused = try {
      ignore(canonical_base64_decoded_size(content))
      false
    } catch {
      TreeGuest(message) => message.contains("canonical base64")
      error => raise error
    }
    assert_true(refused, msg=content)
  }
}

///|
test "tree aggregate limits retain exact Int64 B budgets" {
  guard tree_support().limits.to_json() is Object(fields) else {
    abort("limits")
  }
  fields["maxArtifactBytes"] = Json::number(2181171200.0)
  fields["maxTotalArtifactBytes"] = Json::number(2181171200.0)
  fields["maxSessionDiskBytes"] = Json::number(4354412803.0)
  fields["maxSessionWorkUnits"] = Json::number(2147483648.0)
  let budget = TreeBudget::from_limits(
    @model_access.Limits::from_json(Json::object(fields)),
  )
  assert_eq(budget.file.to_string(), "2181171200")
  assert_eq(budget.total.to_string(), "2181171200")
  assert_eq(budget.disk.to_string(), "4354412803")
  assert_eq(budget.work.to_string(), "2147483648")
  let defaults = TreeBudget::from_limits(tree_support().limits)
  assert_eq(defaults.file.to_string(), "16777216")
  assert_eq(defaults.total.to_string(), "67108864")
  assert_eq(defaults.disk.to_string(), "134217728")
  assert_eq(defaults.work.to_string(), "65536")
}

///|
test "tree aggregate stage counter crosses Int32 with a three byte artifact" {
  with_capture_test_root((path, _directory) => {
    let budget = {
      ..TreeBudget::from_limits(tree_support().limits),
      total: 2181171200L,
      disk: 4354412803L,
    }
    let stage = TreeStage::open(path + "/out", "int64-counter")
    defer stage.dispose()
    stage.bytes = 2147483646L
    stage.write(test_tree_chunk("order.txt", b"73\n"), budget, 2173241603L)
    assert_eq(stage.bytes, 2147483649L)
    assert_eq(stage.files["order.txt"].bytes, 3)
    assert_eq(
      @platform.read(path + "/" + stage.temporary + "/order.txt"),
      "73\n",
    )
  })
}

///|
test "tree aggregate B disk ceiling accepts equality and refuses one extra byte" {
  with_capture_test_root((path, _directory) => {
    let budget = {
      ..TreeBudget::from_limits(tree_support().limits),
      total: 2181171201L,
      disk: 4354412803L,
    }
    let stage = TreeStage::open(path + "/out", "int64-disk")
    defer stage.dispose()
    // Logical counters only. Exactly three bytes are written on disk.
    stage.bytes = 2181171197L
    stage.write(test_tree_chunk("order.txt", b"73\n"), budget, 2173241603L)
    assert_eq(stage.bytes, 2181171200L)
    let refused = try {
      stage.write(test_tree_chunk("extra.txt", b"x"), budget, 2173241603L)
      false
    } catch {
      TreeOutput(message) => message.contains("byte limit")
      error => raise error
    }
    assert_true(refused)
    assert_eq(stage.bytes, 2181171200L)
    assert_false(stage.files.contains("extra.txt"))
    assert_eq(stage.directory.list(1), ["order.txt"])
  })
}

///|
test "tree aggregate disk accounting refuses subtraction overflow before writes" {
  with_capture_test_root((path, _directory) => {
    let budget = {
      ..TreeBudget::from_limits(tree_support().limits),
      total: 9223372036854775807L,
      disk: 4354412803L,
    }
    let stage = TreeStage::open(path + "/out", "int64-overflow")
    defer stage.dispose()
    stage.bytes = 9223372036854775804L
    let refused = try {
      stage.write(
        test_tree_chunk("order.txt", b"73\n"),
        budget,
        9223372036854775807L,
      )
      false
    } catch {
      TreeOutput(message) => message.contains("byte limit")
      error => raise error
    }
    assert_true(refused)
    assert_eq(stage.bytes, 9223372036854775804L)
    assert_true(stage.directory.list(0).is_empty())
  })
}

///|
test "tree aggregate artifact total ceiling is independent of the disk ceiling" {
  with_capture_test_root((path, _directory) => {
    let budget = {
      ..TreeBudget::from_limits(tree_support().limits),
      total: 2181171200L,
      disk: 4354412804L,
    }
    let stage = TreeStage::open(path + "/out", "int64-total")
    defer stage.dispose()
    stage.bytes = 2181171197L
    stage.write(test_tree_chunk("order.txt", b"73\n"), budget, 2173241603L)
    assert_eq(stage.bytes, 2181171200L)
    let refused = try {
      stage.write(test_tree_chunk("extra.txt", b"x"), budget, 2173241603L)
      false
    } catch {
      TreeOutput(message) => message.contains("byte limit")
      error => raise error
    }
    assert_true(refused)
    assert_eq(stage.bytes, 2181171200L)
    assert_eq(stage.directory.list(1), ["order.txt"])
  })
}

///|
test "tree aggregate source counter retains B bytes without changing capture defaults" {
  with_capture_test_root((path, directory) => {
    directory.mkdir("tree")
    directory.mkdir("capture")
    let source = directory.child("tree")
    defer source.close()
    let scratch = directory.child("capture")
    defer scratch.close()
    source.write("manifest.json", capture_manifest, offset=0, create=true)
    let captured = capture_tree(
      () => @platform.BoundedDirectory::open(path + "/tree"),
      source,
      scratch,
      directory.stamp(),
      () => (),
    )
    assert_eq(captured.bytes, capture_manifest.length().to_int64())
    assert_eq(TREE_DOCUMENT_BYTES, 1048576)
    assert_eq(TREE_SNAPSHOT_BYTES, 67108864L)
    // Only the counter is synthetic; the captured manifest stays tiny.
    let logical = { ..captured, bytes: 2173241603L, }
    let budget = {
      ..TreeBudget::from_limits(tree_support().limits),
      disk: 2173241603L,
    }
    let view = TreeView::open(logical, budget, "int64-source", () => ())
    assert_eq(view.capture.bytes, 2173241603L)
    let refused = try {
      ignore(
        TreeView::open(
          logical,
          { ..budget, disk: 2173241602L, },
          "int64-source",
          () => (),
        ),
      )
      false
    } catch {
      TreeSource(message) => message.contains("negotiated disk")
      error => raise error
    }
    assert_true(refused)
  })
}

///|
test "tree aggregate work crosses Int32 and refuses an over-budget update" {
  let work = Ref(2147483647L)
  charge_tree_work(work, 2147483648L, 1L, () => ())
  assert_eq(work.val, 2147483648L)
  let refused = try {
    charge_tree_work(work, 2147483648L, 1L, () => ())
    false
  } catch {
    TreeSource(message) => message.contains("work limit")
    error => raise error
  }
  assert_true(refused)
  assert_eq(work.val, 2147483648L)
}

///|
test "tree aggregate widening preserves Int32 per-file bounds before writes" {
  with_capture_test_root((path, _directory) => {
    let budget = {
      ..TreeBudget::from_limits(tree_support().limits),
      file: 2147483648L,
    }
    let stage = TreeStage::open(path + "/out", "int32-file")
    defer stage.dispose()
    let refused = try {
      stage.write(
        test_tree_chunk("order.txt", b"x", offset=2147483647),
        budget,
        0L,
      )
      false
    } catch {
      TreeOutput(message) => message.contains("byte limit")
      error => raise error
    }
    assert_true(refused)
    assert_eq(stage.bytes, 0L)
    assert_true(stage.directory.list(0).is_empty())
  })
}

///|
test "Orders scale admission selects bounded A and B without raising defaults" {
  let normal = TreeGenerationProfile::Standard.admission()
  assert_eq(normal.document_bytes, 1048576)
  assert_eq(normal.source_bytes, 67108864L)
  assert_eq(normal.entries, 4096)
  assert_eq(normal.output_paths, 1024)
  for
    (profile, documents, entries, source, artifacts, paths, deliveries) in [
      (
        TreeGenerationProfile::OrdersScaleA,
        68611,
        69643,
        1086620931L,
        1090585600L,
        1025,
        78913,
      ),
      (
        TreeGenerationProfile::OrdersScaleB,
        137219,
        139275,
        2173241603L,
        2181171200L,
        2049,
        157825,
      ),
    ] {
    let admission = profile.admission()
    let budget = TreeBudget::from_limits(admission.support.limits)
    assert_eq(admission.document_bytes, 32768)
    assert_eq(admission.documents, documents)
    assert_eq(admission.entries, entries)
    assert_eq(admission.source_bytes, source)
    assert_eq(admission.output_paths, paths)
    assert_eq(admission.deliveries, deliveries)
    assert_eq(budget.total, artifacts)
    assert_eq(budget.disk, source + artifacts)
    assert_eq(budget.frame, 65536)
    assert_eq(budget.document_count, 1)
    assert_eq(budget.decoded, 65536)
    assert_eq(budget.encoded, 65536)
    assert_eq(budget.chunk, 32768)
    assert_eq(admission.support.tuples(), [
      { ir: V4, codec: MorphirJson, encoding: Plain, },
    ])
    let channels = profile.channel_limits(Limits::host())
    assert_eq(channels.request_bytes, 65536)
    assert_eq(channels.response_bytes, 65536)
    assert_true(profile.deadline().ms() > Deadline::default().ms())
  }
}

///|
test "Orders scale admission enforces exact and one-over entries and output paths" {
  with_capture_test_root((path, directory) => {
    for profile in [TreeGenerationProfile::Standard, OrdersScaleA, OrdersScaleB] {
      let admission = profile.admission()
      let walk : TreeCaptureWalk = {
        pass: Copy,
        directory,
        documents: Map([]),
        versions: Map([]),
        check: () => (),
        output_parent: "",
        admission,
        entries: admission.entries - 1,
        bytes: 0L,
        cache: 0,
        work: 0L,
      }
      walk.admit_entries(1)
      assert_eq(walk.entries, admission.entries)
      let refused = try {
        walk.admit_entries(1)
        false
      } catch {
        TreeSource(_) => true
        error => raise error
      }
      assert_true(refused)
      assert_eq(walk.entries, admission.entries)
      let stage = TreeStage::open(
        path + "/out",
        admission.entries.to_string(),
        admission~,
      )
      defer stage.dispose()
      for index in 0..<admission.output_paths {
        assert_true(stage.remember("file-" + index.to_string(), false))
      }
      assert_eq(stage.paths.length(), admission.output_paths)
      let refused = try {
        ignore(stage.remember("one-over", false))
        false
      } catch {
        TreeOutput(_) => true
        error => raise error
      }
      assert_true(refused)
      assert_eq(stage.paths.length(), admission.output_paths)
    }
  })
}

///|
test "Orders scale capture carries admission through real reads beyond default entry allowance" {
  with_capture_test_root((path, directory) => {
    directory.mkdir("tree")
    directory.mkdir("capture")
    let source = directory.child("tree")
    defer source.close()
    let scratch = directory.child("capture")
    defer scratch.close()
    source.write("manifest.json", capture_manifest, offset=0, create=true)
    source.mkdir("pkg")
    let make = admission => TreeCaptureWalk::{
      pass: Copy,
      directory: scratch,
      documents: Map([]),
      versions: Map([]),
      check: () => (),
      output_parent: directory.stamp(),
      admission,
      entries: 4095,
      bytes: 0L,
      cache: 0,
      work: 0L,
    }
    let standard = make(TreeGenerationProfile::Standard.admission())
    let refused = try {
      standard.visit(source, "", 0, source.stamp())
      false
    } catch {
      @platform.IOError("directory.entry_limit") => true
      TreeSource(_) => true
      error => raise error
    }
    assert_true(refused)
    let scale = make(TreeGenerationProfile::OrdersScaleA.admission())
    scale.visit(source, "", 0, source.stamp())
    assert_eq(scale.entries, 4097)
    assert_eq(scale.bytes, capture_manifest.length().to_int64())
    scratch.remove("0", directory=false)
    let captured = capture_tree(
      () => @platform.BoundedDirectory::open(path + "/tree"),
      source,
      scratch,
      directory.stamp(),
      () => (),
      admission=TreeGenerationProfile::OrdersScaleA.admission(),
    )
    assert_eq(captured.admission.profile, OrdersScaleA)
    assert_eq(captured.entries, 2)
  })
}

///|
test "Orders scale retained request IDs share the capture and staging cache budget" {
  with_capture_test_root((path, directory) => {
    directory.mkdir("tree")
    directory.mkdir("capture")
    let source = directory.child("tree")
    defer source.close()
    let scratch = directory.child("capture")
    defer scratch.close()
    source.write("manifest.json", capture_manifest, offset=0, create=true)
    let admission = TreeGenerationProfile::OrdersScaleA.admission()
    let captured = capture_tree(
      () => @platform.BoundedDirectory::open(path + "/tree"),
      source,
      scratch,
      directory.stamp(),
      () => (),
      admission~,
    )
    let budget = TreeBudget::from_limits(admission.support.limits)
    let view = TreeView::open(captured, budget, "requests", () => ())
    let request = @model_access.ReadRequest::from_json({
      "kind": "inventory",
      "requestId": "r1",
      "selection": "root",
      "pageSize": 16,
    })
    let before = view.cache
    view.retain_requests([request])
    assert_eq(view.cache, before + 264)
    assert_eq(view.request_ids, 1)
    view.cache = budget.cache - 263
    let refused = try {
      view.retain_requests([request])
      false
    } catch {
      TreeSource(message) => message.contains("metadata")
      error => raise error
    }
    assert_true(refused)
    assert_eq(view.request_ids, 1)
    view.request_ids = admission.request_limit
    let refused = try {
      view.retain_requests([request])
      false
    } catch {
      TreeGuest(message) => message.contains("request count")
      error => raise error
    }
    assert_true(refused)
    assert_eq(view.request_ids, admission.request_limit)
  })
}

///|
test "Orders scale snapshot cleanup has an explicit independent entry bound" {
  with_capture_test_root((_path, directory) => {
    directory.mkdir("one")
    let one = directory.child("one")
    defer one.close()
    one.write("a", b"x", offset=0, create=true)
    directory.discard(one, "one", entries=1)
    directory.mkdir("two")
    let two = directory.child("two")
    defer two.close()
    two.write("a", b"x", offset=0, create=true)
    two.write("b", b"x", offset=0, create=true)
    let refused = try {
      directory.discard(two, "two", entries=1)
      false
    } catch {
      @platform.IOError(message) => message.contains("cleanup_limit")
      error => raise error
    }
    assert_true(refused)
    directory.discard(two, "two", entries=2)
  })
}

///|
test "Orders scale delivers a production-sized literal under a separate normalization bound" {
  with_capture_test_root((path, directory) => {
    directory.mkdir("tree")
    directory.mkdir("capture")
    let source = directory.child("tree")
    defer source.close()
    let scratch = directory.child("capture")
    defer scratch.close()
    for
      part in ["pkg", "pkg/acme", "pkg/acme/orders", "pkg/acme/orders/m000000"] {
      @platform.mkdir(path + "/tree/" + part)
    }
    let manifest : Json = {
      "formatVersion": 4,
      "distribution": "Library",
      "package": "acme/orders",
      "pathBudget": 4000,
    }
    let module_info : Json = {
      "formatVersion": 4,
      "path": "m000000",
      "types": [],
      "values": ["order000000"],
    }
    let value : Json = {
      "formatVersion": 4,
      "name": "order000000",
      "def": {
        "Public": {
          "ExpressionBody": {
            "inputTypes": {},
            "outputType": "morphir/SDK:string#string",
            "body": { "Literal": { "StringLiteral": "x".repeat(16384) } },
          },
        },
      },
    }
    @platform.write(path + "/tree/manifest.json", manifest.stringify() + "\n")
    @platform.write(
      path + "/tree/pkg/acme/orders/m000000/module.json",
      module_info.stringify() + "\n",
    )
    let bytes = @utf8.encode(value.stringify() + "\n")
    assert_eq(bytes.length(), 16560)
    @platform.write_bytes(
      path + "/tree/pkg/acme/orders/m000000/order000000.value.json",
      bytes,
    )
    let admission = TreeGenerationProfile::OrdersScaleA.admission()
    let captured = capture_tree(
      () => @platform.BoundedDirectory::open(path + "/tree"),
      source,
      scratch,
      directory.stamp(),
      () => (),
      admission~,
    )
    let view = TreeView::open(
      captured,
      TreeBudget::from_limits(admission.support.limits),
      "large",
      () => (),
    )
    let roots = @model_wire.array(
      @model_wire.field(
        view.inventory_delivery("root", "root", 16, None),
        "entries",
      ),
    )
    let selection = @model_wire.string(
      @model_wire.field(
        @model_wire.field(roots[0], "module"),
        "memberSelection",
      ),
    )
    let members = @model_wire.array(
      @model_wire.field(
        view.inventory_delivery("members", selection, 16, None),
        "entries",
      ),
    )
    let document = @model_wire.string(
      @model_wire.field(@model_wire.field(members[0], "value"), "documentId"),
    )
    let delivered = view.deliver(1, [
      @model_access.ReadRequest::from_json({
        "kind": "document",
        "requestId": "large",
        "documentId": document,
      }),
    ])
    assert_eq(
      @model_wire.field(
        @model_wire.array(@model_wire.field(delivered.to_json(), "deliveries"))[0],
        "decodedByteLength",
      ),
      16560,
    )
  }) catch {
    @model_wire.Invalid(code, detail) => fail(code + ": " + detail)
    error => raise error
  }
}

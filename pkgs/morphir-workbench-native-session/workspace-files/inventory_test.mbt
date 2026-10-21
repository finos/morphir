///|
fn inventory_refused(action : () -> Unit raise) -> Unit raise {
  let denied = try {
    action()
    false
  } catch {
    @files.Invalid(_) => true
    error => raise error
  }
  assert_true(denied)
}

///|
test "inventory paths refuse escape recovery and omitted directories while retaining model sidecars" {
  for
    path in [
      "", "/a", "../a", "a/../b", "a//b", "a\\b", "C:/a", "a\tb", ".morphir-workspace-edit.lock/a",
      "one/.git/config", "node_modules/main.scm", "a/",
    ] {
    inventory_refused(fn() raise { ignore(@files.RelativePath::parse(path)) })
  }
  for
    path in [
      "morphir.toml", ".morphir/workbench-models.json", "models/node_modules/value",
      "models/.git/data", "packages/报价/src/main.scm",
    ] {
    assert_eq(@files.RelativePath::parse(path).to_string(), path)
  }
  inventory_refused(fn() raise {
    ignore(@files.RelativePath::parse("a/".repeat(16) + "value"))
  })
}

///|
test "inventory round trips exact original bytes and owns both input and output" {
  let backing : FixedArray[Byte] = [0x00, 0xff, 0x80, 0x0d, 0x0a]
  let bytes = backing.unsafe_reinterpret_as_bytes()
  let files = Map([
    ("models/value.ionb", bytes),
    ("src/main.scm", b"\xef\xbb\xbf11\r\n"),
  ])
  let inventory = @files.Inventory::new(files)
  files.clear()
  backing[0] = 0x22
  let recovered = @files.Inventory::decode(inventory.encode())
  let copy = recovered.files()
  assert_eq(copy["models/value.ionb"], b"\x00\xff\x80\r\n")
  assert_eq(copy["src/main.scm"], b"\xef\xbb\xbf11\r\n")
  copy.clear()
  assert_eq(recovered.files()["models/value.ionb"], b"\x00\xff\x80\r\n")
}

///|
test "inventory edits create replace and delete files and directories without removing prior empty folders" {
  let baseline = @files.Inventory::new(
    Map([
      ("one/src/main.scm", b"11"),
      ("keep/main.scm", b"22"),
      ("preserve/main.scm", b"33"),
    ]),
  )
  let candidate = @files.Inventory::new(
    Map([("two/src/main.scm", b"44"), ("keep/main.scm", b"55")]),
  )
  let edit = baseline.difference(candidate, [
    "", "one", "one/src", "keep", "preserve", "preserve/empty",
  ])
  assert_eq(edit.deletes, ["one/src/main.scm", "preserve/main.scm"])
  assert_true(
    edit.writes == Map([("two/src/main.scm", b"44"), ("keep/main.scm", b"55")]),
  )
  assert_eq(edit.create_directories, ["two", "two/src"])
  assert_eq(edit.remove_directories, ["one"])
}

///|
test "inventory rejects ambiguous content and directory collisions before effects" {
  for
    source in [
      "{\"version\":1,\"files\":{},\"extra\":true}", "{\"version\":1,\"files\":{\"a\":\"1\",\"a/b\":\"2\"}}",
      "{\"version\":1,\"files\":{\"a\":{\"encoding\":\"base64\",\"content\":\"YR==\"}}}",
      "{\"version\":1,\"files\":{\"../outside\":\"a\"}}",
    ] {
    inventory_refused(fn() raise {
      ignore(@files.Inventory::decode(@utf8.encode(source)))
    })
  }
  let old = @files.Inventory::new(Map([("one/main.scm", b"11")]))
  let next = @files.Inventory::new(Map([("one", b"22")]))
  inventory_refused(fn() raise { ignore(old.difference(next, ["", "one"])) })
  inventory_refused(fn() raise { ignore(old.difference(old, [""])) })
}

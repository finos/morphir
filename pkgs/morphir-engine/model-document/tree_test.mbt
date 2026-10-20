///|
test "tree originals retain binary sidecars and explicit empty directories" {
  let files = Map::from_array([
    ("manifest.yaml", b"\xef\xbb\xbf# retained\r\n"),
    ("sidecar.bin", b"\x00\xff\x01"),
  ])
  let directories = ["empty", "empty/nested"]
  let tree = @document.OriginalTree::new(
    files,
    directories,
    @version.FormatVersion::baseline(4U),
  )
  files.clear()
  directories.clear()
  assert_eq(tree.copy_files()["sidecar.bin"], b"\x00\xff\x01")
  assert_eq(tree.copy_files()["manifest.yaml"], b"\xef\xbb\xbf# retained\r\n")
  assert_eq(tree.directory_paths(), ["empty", "empty/nested"])
  let copy = tree.copy_files()
  copy.clear()
  assert_eq(tree.copy_files().length(), 2)
}

///|
test "tree originals reject escaping and conflicting portable inventories" {
  let version = @version.FormatVersion::baseline(4U)
  for
    (paths, directories) in [
      (["../manifest.yaml"], []),
      (["/manifest.yaml"], []),
      (["a/./b"], []),
      (["a//b"], []),
      (["a\\b"], []),
      (["a", "a/b"], []),
      (["A/b", "a/c"], []),
      (["A", "a"], []),
      (["a"], ["a"]),
      (["a"], ["a/b"]),
      (["file"], ["empty", "empty"]),
    ] {
    let refused = try {
      ignore(
        @document.OriginalTree::new(
          Map::from_array(paths.map(path => (path, b""))),
          directories,
          version,
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(refused, msg=paths.to_string())
  }
}

///|
test "connected inventory bounds are separate from local document limits" {
  let files = Array::makei(4097, index => "file-" + index.to_string() + ".bin")
  @document.validate_inventory_paths(
    files,
    [],
    profile=@document.InventoryPathProfile::Connected,
  )
  assert_true(
    try {
      @document.validate_inventory_paths(files, [])
      false
    } catch {
      _ => true
    },
  )
  let path = Array::make(129, "part").join("/")
  @document.validate_inventory_paths(
    [path],
    [],
    profile=@document.InventoryPathProfile::Connected,
  )
  assert_true(
    try {
      @document.validate_inventory_paths([path], [])
      false
    } catch {
      _ => true
    },
  )
}

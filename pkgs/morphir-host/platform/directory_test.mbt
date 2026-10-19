///|
#cfg(not(target="wasm-gc"))
test "bounded directory requests reject invalid limits and NUL before host effects" {
  for (path, limit) in [("ignored", -1), ("ignored", 65537), ("a\u0000b", 1)] {
    let rejected = try {
      ignore(@platform.list_bounded(path, limit))
      false
    } catch {
      @platform.IOError("directory.invalid_request") => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
#cfg(any(target="native", target="js"))
test "bounded enumeration preserves names and releases handles on every exit" {
  let root = @platform.temporary()
  defer @platform.remove_dir(root)
  assert_eq(@platform.list_bounded(root, 0), [])
  let names = ["plain", "astral-😀", "\uFEFFbom", "space and é"]
  for name in names {
    @platform.write_bytes(root + "/" + name, b"")
  }
  defer (for name in names {
    @platform.remove_file(root + "/" + name)
  })
  let expected = names.copy()
  expected.sort()
  let actual = @platform.list_bounded(root, 4)
  actual.sort()
  assert_eq(actual, expected)
  // Thousands of failed and successful calls share one process. Run this test
  // under a small descriptor limit to make a leaked directory handle observable.
  for i = 0; i < 2048; i = i + 1 {
    let refused = try {
      ignore(@platform.list_bounded(root, i % 4))
      false
    } catch {
      @platform.IOError("directory.entry_limit") => true
      _ => false
    }
    assert_true(refused)
    assert_eq(@platform.list_bounded(root, 4).length(), 4)
  }
  for selected in [root + "/missing", root + "/plain"] {
    let refused = try {
      ignore(@platform.list_bounded(selected, 4))
      false
    } catch {
      _ => true
    }
    assert_true(refused)
  }
  // Existing callers retain the original list API.
  assert_eq(@platform.list(root).length(), 4)
}

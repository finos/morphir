///|
test "archive scalar sizes count exact UTF8 emitted names raw bytes and explicit directories" {
  let inventory = @document.OriginalInventory::from_connected(
    Map([("雪.bin", b"\x00\xff\x01"), ("empty", b"")]),
    ["資料", "nested/empty"],
    NotReported,
  )
  let sizes = inventory.archive_sizes()
  assert_eq(sizes.entry_count(), 4UL)
  assert_eq(sizes.file_bytes(), 3UL)
  assert_eq(sizes.archive_name_bytes(), 32UL)
  assert_eq(inventory.entry_count(), 4)
  assert_eq(inventory.copy_files().get("雪.bin"), Some(b"\x00\xff\x01"))
}

///|
test "directory-only archive sizes count slash bytes without inventing implicit entries" {
  let inventory = @document.OriginalInventory::from_connected(
    Map([]),
    ["empty", "deep/leaf"],
    NotReported,
  )
  let sizes = inventory.archive_sizes()
  assert_eq(sizes.entry_count(), 2UL)
  assert_eq(sizes.file_bytes(), 0UL)
  assert_eq(sizes.archive_name_bytes(), 16UL)
}

///|
test "archive scalar size boundary retains all100064 entries without Int32 aggregate conversion" {
  let directories = Array::makei(100063, n => "d" + n.to_string())
  let inventory = @document.OriginalInventory::from_connected(
    Map([("one", b"\x00\xff")]),
    directories,
    NotReported,
  )
  let sizes = inventory.archive_sizes()
  let mut names = 3UL
  for name in directories {
    names += @utf8.encode(name).length().to_uint64() + 1UL
  }
  assert_eq(sizes.entry_count(), 100064UL)
  assert_eq(sizes.file_bytes(), 2UL)
  assert_eq(sizes.archive_name_bytes(), names)
}

///|
test "archive metadata describes individual file lengths without copying file buffers" {
  let inventory = @document.OriginalInventory::from_connected(
    Map([("opaque.bin", b"\x00\xff\x01")]),
    ["empty"],
    NotReported,
  )
  let file = @document.OriginalPath::parse("opaque.bin", profile=Connected)
  let missing = @document.OriginalPath::parse("missing.bin", profile=Connected)
  let directory = @document.OriginalPath::parse("empty", profile=Connected)
  assert_eq(inventory.file_byte_length(file), Some(3UL))
  assert_eq(inventory.file_byte_length(missing), None)
  assert_eq(inventory.file_byte_length(directory), None)
}

///|
test "archive name sizes preserve two-byte scalars and supplementary Unicode pairs" {
  let inventory = @document.OriginalInventory::from_connected(
    Map([("é🐬.bin", b"\x00\xff")]),
    ["資料/𐐀"],
    NotReported,
  )
  let sizes = inventory.archive_sizes()
  assert_eq(sizes.entry_count(), 2UL)
  assert_eq(sizes.file_bytes(), 2UL)
  assert_eq(sizes.archive_name_bytes(), 22UL)
}

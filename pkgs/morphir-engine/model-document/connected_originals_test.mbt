///|
/// Product storage/lifecycle controls. These do not claim a real RPC transfer,
/// accepted release, browser download, or campaign qualification.
fn connected_inventory(
  header~ : @document.OriginalSourceHeader = NotReported,
) -> @document.OriginalInventory raise @document.DocumentError {
  @document.OriginalInventory::from_connected(
    Map::from_array([
      ("morphir-ir.json", b"unreadable as a semantic model\x00\xff"),
      ("notes/opaque.bin", b"\x00\xff\x01\x80"),
      ("notes/empty.bin", b""),
    ]),
    ["notes", "notes/empty"],
    header,
  )
}

///|
test "indexed originals retain the complete 100064 entry boundary" {
  let directories = Array::makei(100063, index => "empty-" + index.to_string())
  let inventory = @document.OriginalInventory::from_connected(
    Map([("model.yaml", b"\xEF\xBB\xBFformatVersion: 4\r\n")]),
    directories,
    NotReported,
  )
  assert_eq(inventory.entry_count(), 100064)
  assert_eq(inventory.entry(-1), None)
  assert_eq(inventory.entry(100064), None)
  match inventory.entry(0) {
    Some(File(path)) => assert_eq(path.to_string(), "model.yaml")
    _ => abort("First indexed entry must be the retained file")
  }
  let names = directories.copy()
  names.sort()
  for index, name in names {
    match inventory.entry(index + 1) {
      Some(Directory(path)) => assert_eq(path.to_string(), name)
      _ => abort("Every retained directory must be reachable")
    }
  }
  assert_eq(
    inventory.copy_files().get("model.yaml"),
    Some(b"\xEF\xBB\xBFformatVersion: 4\r\n"),
  )
}

///|
fn begin_originals(
  state : @document.State,
) -> (@document.State, @document.OpenAttempt) {
  match state.begin(Idle) {
    Started(state, attempt) => (state, attempt)
    _ => abort("expected actual opening decision")
  }
}

///|
test "connected original inventory preserves unknown headers opaque bytes and defensive copies" {
  // A mutable foreign byte view can reach a host boundary. It must not remain
  // an alias of the retained originals, even though ordinary Bytes is readonly.
  let backing : FixedArray[Byte] = [0x00, 0xff, 0x01, 0x80]
  let incoming = backing.unsafe_reinterpret_as_bytes()
  let files = Map::from_array([
    ("model.future", b"not a readable supported semantic model"),
    ("notes/opaque.bin", incoming),
    ("notes/zero.bin", b""),
  ])
  let directories = ["notes", "notes/empty"]
  let future = @version.FormatVersion::parse("99.2.7")
  let reported = @document.OriginalRelease::new(99U, 2U, 7U)
  let inventory = @document.OriginalInventory::from_connected(
    files,
    directories,
    Reported(reported),
  )
  backing[0] = 0x7f
  files.clear()
  directories.clear()
  assert_eq(inventory.source_header, Reported(reported))
  assert_eq(inventory.copy_files()["notes/opaque.bin"], b"\x00\xff\x01\x80")
  assert_eq(inventory.copy_files()["notes/zero.bin"], b"")
  assert_eq(inventory.directory_paths(), ["notes", "notes/empty"])
  let copy = inventory.copy_files()
  copy.clear()
  assert_eq(inventory.copy_files().length(), 3)
  let no_header = connected_inventory()
  assert_eq(no_header.source_header, NotReported)
  assert_eq(
    no_header.copy_files()["morphir-ir.json"],
    b"unreadable as a semantic model\x00\xff",
  )
  // The existing semantic document constructor remains strict.
  assert_true(
    try {
      ignore(
        @document.OriginalTree::new(Map::from_array([("x", b"x")]), [], future),
      )
      false
    } catch {
      @document.DocumentError::InvalidVersion => true
      _ => false
    },
  )
}

///|
test "connected inventory retains the exact 64 MiB aggregate bound and rejects one byte over" {
  let half = Bytes::make(33554432, 0x61)
  let exact = @document.OriginalInventory::from_connected(
    Map::from_array([("primary.opaque", half), ("companion.opaque", half)]),
    [],
    NotReported,
  )
  assert_eq(exact.directory_paths(), [])
  assert_true(
    try {
      ignore(
        @document.OriginalInventory::from_connected(
          Map::from_array([
            ("primary.opaque", half),
            ("companion.opaque", half),
            ("one-more-byte", b"x"),
          ]),
          [],
          NotReported,
        ),
      )
      false
    } catch {
      @document.DocumentError::TooLarge => true
      _ => false
    },
  )
  let deep = Array::make(129, "part").join("/")
  let connected = @document.OriginalInventory::from_connected(
    Map::from_array([(deep, b"opaque")]),
    [],
    NotReported,
  )
  assert_eq(connected.copy_files()[deep], b"opaque")
  for path in ["../outside", "/absolute", "a//b", "a/./b", "a\\b"] {
    assert_true(
      try {
        ignore(
          @document.OriginalInventory::from_connected(
            Map::from_array([(path, b"opaque")]),
            [],
            NotReported,
          ),
        )
        false
      } catch {
        @document.DocumentError::InvalidFilename => true
        _ => false
      },
      msg=path,
    )
  }
}

///|
test "originals-only opening has a download revision without inventing a semantic document" {
  let (opening, attempt) = begin_originals(@document.State::new())
  let retained = opening.finish_originals(attempt, connected_inventory())
  assert_eq(retained.document(), None)
  assert_eq(retained.inspection(), Json::null())
  assert_eq(retained.original(), None)
  assert_eq(retained.opening(), None)
  assert_eq(retained.current_revision(), None)
  let revision = retained.inventory_revision().unwrap()
  let owner = retained.original_inventory_for(revision).unwrap()
  let selected = owner.download_file(
    @document.OriginalPath::parse("notes/opaque.bin", profile=Connected),
  )
  assert_eq(
    selected,
    (
      {
        "path": "notes/opaque.bin",
        "content": "AP8BgA==",
        "binary": true,
        "encoding": "base64",
      } : Json),
  )
  let archive = owner.download()
  guard archive is Object(fields) else {
    abort("existing inventory archive representation")
  }
  assert_eq(fields["directories"], ["notes", "notes/empty"])
  let closed = match retained.close(Idle) {
    Closed(state, None) => state
    _ =>
      abort("originals-only owner must close without semantic or host release")
  }
  assert_eq(closed.document(), None)
  assert_eq(closed.original_inventory(), None)
  assert_eq(closed.current_revision(), None)
  assert_eq(closed.inventory_revision(), None)
  assert_eq(closed.original_inventory_for(revision), None)
  // The retired actual opening token cannot resurrect original ownership.
  let late = closed.finish_originals(attempt, connected_inventory())
  assert_eq(late, closed)
}

///|
test "original inventory obeys the same opening currentness retained host refusal and stale controls" {
  let (first, first_attempt) = begin_originals(@document.State::new())
  let retained = first.finish_originals(first_attempt, connected_inventory())
  let first_revision = retained.inventory_revision().unwrap()
  for
    host in [
      @document.HostRetention::Submitting,
      @document.HostRetention::Running,
      @document.HostRetention::Disconnected,
      @document.HostRetention::UnknownSubmission,
    ] {
    match retained.begin(host) {
      Refused(actual) => assert_eq(actual, host)
      _ => abort("retained host must refuse an originals opening")
    }
    match retained.close(host) {
      Retained(actual) => assert_eq(actual, host)
      _ => abort("retained host must refuse an originals close")
    }
    assert_eq(
      retained.original_inventory_for(first_revision),
      retained.original_inventory(),
    )
  }
  let (opening, pending) = begin_originals(retained)
  assert_eq(opening.original_inventory(), retained.original_inventory())
  let stale = opening.finish_originals(first_attempt, connected_inventory())
  assert_eq(stale, opening)
  assert_eq(stale.opening(), Some(pending))
  let rejected = stale.reject(pending)
  assert_eq(rejected.inventory_revision(), Some(first_revision))
  assert_eq(rejected.original_inventory(), retained.original_inventory())
  let (replacement, next) = begin_originals(rejected)
  let new_owner = @document.OriginalInventory::from_connected(
    Map::from_array([("replacement.opaque", b"replacement")]),
    [],
    NotReported,
  )
  let replaced = replacement.finish_originals(next, new_owner)
  assert_eq(replaced.document(), None)
  assert_eq(replaced.current_revision(), None)
  assert_true(replaced.inventory_revision() != Some(first_revision))
  assert_eq(replaced.original_inventory_for(first_revision), None)
  assert_eq(
    replaced.original_inventory().unwrap().copy_files()["replacement.opaque"],
    b"replacement",
  )
}

///|
test "original reported releases preserve the numeric wire domain without semantic support claims" {
  for
    (major, minor, patch, literal) in [
      (0U, 0U, 0U, "0.0.0"),
      (1U, 2U, 3U, "1.2.3"),
      (2U, 1U, 0U, "2.1.0"),
      (99U, 2U, 7U, "99.2.7"),
      (
        4294967295U, 4294967295U, 4294967295U, "4294967295.4294967295.4294967295",
      ),
    ] {
    let release = @document.OriginalRelease::new(major, minor, patch)
    assert_eq(release.to_release_string(), literal)
    assert_eq(
      connected_inventory(header=Reported(release)).source_header,
      Reported(release),
    )
  }
  // This is the bounded numeric model-originals wire-release domain. It is not
  // a generic SemVer parser, and does not admit prerelease/build wire strings.
  assert_eq(connected_inventory().source_header, NotReported)
}

///|
test "connected inventory preserves directory-only captures and the total entry boundary" {
  let directories = Array::makei(100064, index => "root-" + index.to_string())
  let exact = @document.OriginalInventory::from_connected(
    Map([]),
    directories,
    NotReported,
  )
  assert_eq(exact.copy_files().length(), 0)
  assert_eq(exact.directory_paths().length(), 100064)
  directories.push("one-entry-over")
  assert_eq(exact.directory_paths().length(), 100064)
  assert_true(
    try {
      ignore(
        @document.OriginalInventory::from_connected(
          Map([]),
          directories,
          NotReported,
        ),
      )
      false
    } catch {
      @document.DocumentError::TooLarge => true
      _ => false
    },
  )
  let empty_root = @document.OriginalInventory::from_connected(
    Map([]),
    ["empty-root"],
    NotReported,
  )
  assert_eq(empty_root.copy_files().length(), 0)
  assert_eq(empty_root.directory_paths(), ["empty-root"])
  // A real capture always has its primary root in its inventory, including a
  // root directory with no files. Zero total entries cannot be such an owner.
  assert_true(
    try {
      ignore(
        @document.OriginalInventory::from_connected(Map([]), [], NotReported),
      )
      false
    } catch {
      @document.DocumentError::InvalidReply => true
      _ => false
    },
  )
}

///|
test "new originals preserve the prior semantic document and semantic adoption retires old originals" {
  let (first, semantic_attempt) = begin_originals(@document.State::new())
  let semantic = first.finish(
    semantic_attempt,
    original_reply(name="semantic-A.json", encoded="AQID"),
  )
  let semantic_document = semantic.document().unwrap()
  let semantic_revision = semantic.current_revision().unwrap()
  let semantic_download = semantic
    .original_for(semantic_revision)
    .unwrap()
    .download()
  let (opening, originals_attempt) = begin_originals(semantic)
  let both = opening.finish_originals(originals_attempt, connected_inventory())
  let inventory_revision = both.inventory_revision().unwrap()
  assert_eq(both.document(), Some(semantic_document))
  assert_eq(both.current_revision(), Some(semantic_revision))
  assert_eq(
    both.original_for(semantic_revision).unwrap().download(),
    semantic_download,
  )
  assert_eq(
    both.original_inventory().unwrap().copy_files()["notes/opaque.bin"],
    b"\x00\xff\x01\x80",
  )
  for
    host in [
      @document.HostRetention::Submitting,
      @document.HostRetention::Running,
      @document.HostRetention::Disconnected,
      @document.HostRetention::UnknownSubmission,
    ] {
    match both.begin(host) {
      Refused(actual) => assert_eq(actual, host)
      _ => abort("retained host must refuse a mixed-owner opening")
    }
    match both.close(host) {
      Retained(actual) => assert_eq(actual, host)
      _ => abort("retained host must refuse a mixed-owner close")
    }
  }
  let (pending, pending_attempt) = begin_originals(both)
  let stale = pending.finish_originals(originals_attempt, connected_inventory())
  assert_eq(stale, pending)
  let recovered = stale.reject(pending_attempt)
  assert_eq(recovered.document(), both.document())
  assert_eq(recovered.current_revision(), Some(semantic_revision))
  assert_eq(recovered.original_inventory(), both.original_inventory())
  assert_eq(recovered.inventory_revision(), Some(inventory_revision))
  let closed = match recovered.close(Idle) {
    Closed(state, None) => state
    _ => abort("close must retire both content owners")
  }
  assert_eq(closed.document(), None)
  assert_eq(closed.current_revision(), None)
  assert_eq(closed.original_for(semantic_revision), None)
  assert_eq(closed.original_inventory(), None)
  assert_eq(closed.inventory_revision(), None)
  assert_eq(closed.original_inventory_for(inventory_revision), None)
  let (replacement, replacement_attempt) = begin_originals(recovered)
  let adopted = replacement.finish(
    replacement_attempt,
    original_reply(name="semantic-C.json", encoded="BAUG"),
  )
  assert_true(adopted.current_revision() != Some(semantic_revision))
  assert_eq(adopted.original_for(semantic_revision), None)
  assert_eq(adopted.original_inventory(), None)
  assert_eq(adopted.inventory_revision(), None)
  assert_eq(adopted.original_inventory_for(inventory_revision), None)
}

///|
async fn write_fixture(name : String) -> String {
  let base = @env.current_dir().unwrap() +
    "/.dev/native-write-" +
    name +
    "-" +
    @env.now().to_string()
  @fs.mkdir(base + "/root", recursive=true)
  @fs.mkdir(base + "/outside", recursive=true)
  base
}

///|
fn file_edit(
  writes~ : Array[(String, Bytes)] = [],
  deletes~ : Array[String] = [],
  directories~ : Array[String] = [],
  remove_directories~ : Array[String] = [],
) -> FileEdit {
  { writes: Map::from_array(writes), deletes, directories, remove_directories, }
}

///|
fn write_denied(action : () -> Unit raise) -> Unit raise {
  let rejected = try {
    action()
    false
  } catch {
    Rejected(_) => true
    error => raise error
  }
  assert_true(rejected)
}

///|
async test "native writes create replace and remove files and directories while retaining unrelated bytes" {
  if !supported() {
    return
  }
  let base = write_fixture("operations")
  defer @fs.rmdir(base, recursive=true)
  let root = WriteRoot::open(base + "/root")
  defer root.close()
  let empty = root.snapshot()
  root.apply(
    empty,
    file_edit(writes=[
      ("morphir.toml", b"[workspace]\nmembers=['one']\n"),
      ("one/morphir.toml", b"[project]\nname='One'\n"),
      ("one/src/main.scm", b"11"),
      ("models/raw.ionb", b"\x00\xff\x80\r\n"),
    ]),
  )
  let first = root.snapshot()
  assert_eq(first.files.length(), 4)
  root.apply(
    first,
    file_edit(
      writes=[("one/src/main.scm", b"22"), ("one/src/helper.scm", b"33")],
      directories=["empty"],
    ),
  )
  let second = root.snapshot()
  assert_eq(second.files["one/src/main.scm"], b"22")
  assert_eq(second.files["models/raw.ionb"], b"\x00\xff\x80\r\n")
  assert_true(second.directories.contains("empty"))
  root.apply(
    second,
    file_edit(
      writes=[("morphir.toml", b"[workspace]\nmembers=[]\n")],
      deletes=["one/morphir.toml", "one/src/main.scm", "one/src/helper.scm"],
      remove_directories=["one", "empty"],
    ),
  )
  let removed = root.snapshot()
  assert_eq(removed.files.length(), 2)
  assert_false(removed.directories.contains("one"))
  assert_false(removed.directories.contains("empty"))
  assert_eq(removed.files["models/raw.ionb"], b"\x00\xff\x80\r\n")
}

///|
async test "native writer refuses stale bytes links hardlinks special entries and path escapes" {
  if !supported() {
    return
  }
  let base = write_fixture("boundaries")
  defer @fs.rmdir(base, recursive=true)
  @fs.write_file(base + "/root/main.scm", "11")
  @fs.write_file(base + "/outside/value", "outside")
  let root = WriteRoot::open(base + "/root")
  defer root.close()
  let original = root.snapshot()
  @fs.write_file(base + "/root/main.scm", "external")
  write_denied(fn() raise {
    root.apply(original, file_edit(writes=[("main.scm", b"ours")]))
  })
  assert_eq(disk_bytes(base + "/root/main.scm"), b"external")
  let current = root.snapshot()
  for
    path in [
      "../outside/value", "/absolute", "a/../escape", "a\\escape", ".morphir-workspace-edit.lock/value",
      "node_modules/value", "project/_build/value",
    ] {
    write_denied(fn() raise {
      root.apply(current, file_edit(writes=[(path, b"ours")]))
    })
  }
  @fs.symlink(target=base + "/outside", base + "/root/link")
  write_denied(fn() raise {
    root.apply(current, file_edit(writes=[("link/value", b"ours")]))
  })
  @fs.remove(base + "/root/link")
  assert_eq(
    @process.run("ln", [base + "/outside/value", base + "/root/hardlink"]),
    0,
  )
  let forged = {
    ..current,
    files: Map::from_array([("hardlink", b"outside")]),
  }
  write_denied(fn() raise {
    root.apply(forged, file_edit(writes=[("hardlink", b"ours")]))
  })
  @fs.remove(base + "/root/hardlink")
  assert_eq(@process.run("mkfifo", [base + "/root/pipe"]), 0)
  write_denied(fn() raise {
    root.apply(current, file_edit(writes=[("pipe", b"ours")]))
  })
  @fs.remove(base + "/root/pipe")
  assert_eq(disk_bytes(base + "/outside/value"), b"outside")
  assert_eq(root.snapshot().files["main.scm"], b"external")
}

///|
async test "recursive directory removal refuses new files and links without removing originals" {
  if !supported() {
    return
  }
  let base = write_fixture("delete")
  defer @fs.rmdir(base, recursive=true)
  @fs.mkdir(base + "/root/project")
  @fs.write_file(base + "/root/project/main.scm", "11")
  @fs.write_file(base + "/outside/value", "outside")
  let root = WriteRoot::open(base + "/root")
  defer root.close()
  let original = root.snapshot()
  let remove = file_edit(deletes=["project/main.scm"], remove_directories=[
    "project",
  ])
  @fs.write_file(base + "/root/project/new.scm", "external")
  write_denied(fn() raise { root.apply(original, remove) })
  assert_eq(disk_bytes(base + "/root/project/main.scm"), b"11")
  assert_eq(disk_bytes(base + "/root/project/new.scm"), b"external")
  @fs.remove(base + "/root/project/new.scm")
  @fs.symlink(target=base + "/outside", base + "/root/project/link")
  write_denied(fn() raise { root.apply(original, remove) })
  assert_eq(disk_bytes(base + "/outside/value"), b"outside")
  assert_eq(disk_bytes(base + "/root/project/main.scm"), b"11")
}

///|
async test "an injected install failure restores original files and removes new directories" {
  if !supported() {
    return
  }
  let base = write_fixture("rollback")
  defer @fs.rmdir(base, recursive=true)
  @fs.write_file(base + "/root/main.scm", "11")
  let root = WriteRoot::open(base + "/root")
  defer root.close()
  let original = root.snapshot()
  let edit = file_edit(writes=[("main.scm", b"22"), ("new/src/main.scm", b"33")])
  for fault in [0, 1] {
    write_denied(fn() raise { root.apply_with(original, edit, fault) })
    let restored = root.snapshot()
    assert_true(restored.files == original.files)
    assert_eq(restored.directories, original.directories)
  }
}

///|
async test "a failed rollback preserves the backup and blocks another save" {
  if !supported() {
    return
  }
  let base = write_fixture("recovery")
  defer @fs.rmdir(base, recursive=true)
  @fs.write_file(base + "/root/main.scm", "11")
  let root = WriteRoot::open(base + "/root")
  defer root.close()
  let original = root.snapshot()
  let uncertain = try {
    root.apply_with(original, file_edit(writes=[("main.scm", b"22")]), -2)
    false
  } catch {
    Uncertain(_) => true
    error => raise error
  }
  assert_true(uncertain)
  let backup = base + "/root/.morphir-workspace-edit.lock/old-0"
  assert_eq(disk_bytes(backup), b"11")
  let plan = @fs.read_file(
    base + "/root/.morphir-workspace-edit.lock/manifest.tsv",
  ).text()
  assert_true(plan.contains("BACKUP\told-0\tmain.scm"))
  write_denied(fn() raise { ignore(root.snapshot()) })
  @fs.rename(backup, base + "/root/main.scm")
  @fs.remove(base + "/root/.morphir-workspace-edit.lock/manifest.tsv")
  @fs.rmdir(base + "/root/.morphir-workspace-edit.lock")
  assert_eq(root.snapshot().files["main.scm"], b"11")
}

///|
async test "a moved and replaced writable root is rejected before touching its replacement" {
  if !supported() {
    return
  }
  let base = write_fixture("root")
  defer @fs.rmdir(base, recursive=true)
  @fs.write_file(base + "/root/main.scm", "11")
  let root = WriteRoot::open(base + "/root")
  defer root.close()
  let original = root.snapshot()
  @fs.rename(base + "/root", base + "/saved")
  @fs.mkdir(base + "/root")
  write_denied(fn() raise {
    root.apply(original, file_edit(writes=[("main.scm", b"22")]))
  })
  assert_eq(disk_bytes(base + "/saved/main.scm"), b"11")
}

///|
async fn disk_bytes(path : String) -> Bytes {
  @fs.read_file(path).binary()
}

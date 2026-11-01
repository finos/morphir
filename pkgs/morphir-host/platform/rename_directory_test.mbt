///|
/// The publication code that `rename_directory_new` raises, or "published".
fn rename_directory_outcome(source : String, destination : String) -> String {
  try {
    @platform.rename_directory_new(source, destination)
    "published"
  } catch {
    @platform.IOError(message) =>
      match message.split(": ").next() {
        Some(code) => code.to_owned()
        None => message
      }
    _ => "unexpected"
  }
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
test "directory publication is unavailable without a host filesystem rename" {
  assert_eq(
    rename_directory_outcome("staging", "output"),
    "publication.create_unavailable",
  )
}

///|
/// A fresh root under the working directory: native Windows has no temporary
/// directory capability, and the rename contract must hold there too.
#cfg(any(target="native", target="js"))
fn rename_directory_root() -> String raise {
  let root = @platform.cwd() + "/morphir-rename-" + @platform.observation_id()
  @platform.mkdir(root)
  root
}

///|
#cfg(any(target="native", target="js"))
test "directory publication renames the complete tree to a fresh destination" {
  let root = rename_directory_root()
  let source = root + "/staging"
  let destination = root + "/output"
  @platform.mkdir(source)
  @platform.mkdir(source + "/nested")
  @platform.write_bytes(source + "/nested/artifact.txt", b"artifact")
  assert_eq(rename_directory_outcome(source, destination), "published")
  assert_eq(@platform.kind(source), 0)
  assert_eq(@platform.kind(destination), 2)
  assert_eq(
    @platform.read_bytes(destination + "/nested/artifact.txt"),
    b"artifact",
  )
  @platform.remove_file(destination + "/nested/artifact.txt")
  @platform.remove_dir(destination + "/nested")
  @platform.remove_dir(destination)
  @platform.remove_dir(root)
}

///|
#cfg(any(target="native", target="js"))
test "directory publication refuses an existing destination and keeps both trees" {
  let root = rename_directory_root()
  let source = root + "/staging"
  @platform.mkdir(source)
  @platform.write_bytes(source + "/new.txt", b"new")
  // An empty directory, a populated directory and a file are all refused.
  let empty = root + "/empty"
  @platform.mkdir(empty)
  let populated = root + "/populated"
  @platform.mkdir(populated)
  @platform.write_bytes(populated + "/old.txt", b"old")
  let file = root + "/file"
  @platform.write_bytes(file, b"file")
  for destination in [empty, populated, file] {
    assert_eq(
      rename_directory_outcome(source, destination),
      "publication.destination_unavailable",
      msg=destination,
    )
    assert_eq(@platform.read_bytes(source + "/new.txt"), b"new")
  }
  assert_eq(@platform.list(empty), [])
  assert_eq(@platform.list(populated), ["old.txt"])
  assert_eq(@platform.read_bytes(populated + "/old.txt"), b"old")
  assert_eq(@platform.read_bytes(file), b"file")
  // A missing parent cannot hold the destination either.
  assert_eq(
    rename_directory_outcome(source, root + "/missing/output"),
    "publication.destination_unavailable",
  )
  assert_eq(@platform.kind(root + "/missing"), 0)
  @platform.remove_file(file)
  @platform.remove_file(populated + "/old.txt")
  @platform.remove_dir(populated)
  @platform.remove_dir(empty)
  @platform.remove_file(source + "/new.txt")
  @platform.remove_dir(source)
  @platform.remove_dir(root)
}

///|
#cfg(any(target="native", target="js"))
test "directory publication without a source directory leaves the destination absent" {
  let root = rename_directory_root()
  let destination = root + "/output"
  assert_eq(
    rename_directory_outcome(root + "/missing", destination),
    "publication.create_failed",
  )
  assert_eq(@platform.kind(destination), 0)
  // A file is not a directory tree to publish.
  let file = root + "/file"
  @platform.write_bytes(file, b"file")
  assert_eq(
    rename_directory_outcome(file, destination),
    "publication.create_failed",
  )
  assert_eq(@platform.kind(destination), 0)
  assert_eq(@platform.read_bytes(file), b"file")
  @platform.remove_file(file)
  @platform.remove_dir(root)
}

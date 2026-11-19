///|
fn digest(bytes : Bytes) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(bytes))
}

///|
fn snapshot_digest(files : Array[(String, Bytes)]) -> String {
  let sorted = files.copy()
  sorted.sort_by((a, b) => a.0[:].lexical_compare(b.0[:]))
  let manifest = StringBuilder()
  for (path, bytes) in sorted {
    manifest.write_string(path + "\n" + digest(bytes) + "\n")
  }
  digest(@utf8.encode(manifest.to_string()))
}

///|
async fn read_capped_file(path : String) -> Bytes {
  require(
    @fs.kind(path, follow_symlink=false) is Regular,
    "Expected regular file",
  )
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  require(file.kind() is Regular, "Expected regular file handle")
  require(file.size() <= 8192L, "File exceeds 8192 bytes")
  let scratch = FixedArray::make(8193, b'\x00')
  let out = @buffer.Buffer()
  while true {
    let count = file.read_into(scratch, max_len=8193 - out.length())
    if count == 0 {
      break
    }
    require(count <= 8192 - out.length(), "File grew beyond 8192 bytes")
    out.write_bytes(Bytes::from_array(scratch[:count])[:])
  }
  require(@fs.kind(path, follow_symlink=false) is Regular, "File became a link")
  out.to_bytes()
}

///|
async fn capture(root : String) -> Array[(String, Bytes)] {
  // Check the supplied path's parents as well as every descended entry.
  let mut ancestor = @path.Path(root)
  while true {
    require(
      @fs.kind(ancestor.to_string(), follow_symlink=false) is Directory,
      "treeRoot contains a link or non-directory",
    )
    let parent = ancestor.dirname()
    if parent == ancestor {
      break
    }
    ancestor = parent
  }
  let files : Array[(String, Bytes)] = []
  let entries = Ref(0)
  walk(root, "", files, entries, 0)
  require(files.length() == 9, "Expected exactly nine regular files")
  files.sort_by((a, b) => a.0[:].lexical_compare(b.0[:]))
  files
}

///|
fn captured_source(
  files : Array[(String, Bytes)],
  revision : String,
) -> @yaml.TreeSource {
  let require_revision = fn(actual) raise {
    require(actual == revision, "Stale revision")
  }
  {
    revision: () => revision,
    contains: fn(actual, path) raise {
      require_revision(actual)
      files.any(file => file.0 == path)
    },
    next_module: fn(actual, prefix, after) raise {
      require_revision(actual)
      let mut found : String? = None
      for (path, _) in files {
        for extension in [".json", ".yaml", ".yml"] {
          if path.has_prefix(prefix) && path.has_suffix("/module" + extension) {
            let logical = path[:path.length() - extension.length()].to_owned()
            if after.map_or(true, key => key[:].lexical_compare(logical[:]) < 0) &&
              found.map_or(true, key => logical[:].lexical_compare(key[:]) < 0) {
              found = Some(logical)
            }
          }
        }
      }
      found
    },
    read: fn(actual, path, limit) raise {
      require_revision(actual)
      for (name, bytes) in files {
        if name == path {
          guard bytes.length() <= limit else {
            raise @yaml.TreeSourceError::DocumentTooLarge
          }
          return @utf8.decode(bytes[:], ignore_bom=false)
        }
      }
      fail("Missing selected file")
    },
  }
}

///|
async fn walk(
  directory : String,
  relative : String,
  files : Array[(String, Bytes)],
  entries : Ref[Int32],
  depth : Int32,
) -> Unit {
  require(depth <= 16, "Snapshot directory depth exceeds 16")
  let listing = @fs.opendir(directory)
  defer listing.close()
  while listing.next(include_hidden=true, include_special=false) is Some(entry) {
    entries.val += 1
    require(entries.val <= 64, "More than 64 directory entries")
    let name = entry.name
    require(
      name != "" &&
      !name.contains("/") &&
      !name.contains("\\") &&
      !name.contains("\n") &&
      !name.contains("\r"),
      "Unsafe snapshot path",
    )
    let physical = @path.Path(directory).join(@path.Path(name)).to_string()
    let logical = if relative == "" { name } else { relative + "/" + name }
    match @fs.kind(physical, follow_symlink=false) {
      Directory => walk(physical, logical, files, entries, depth + 1)
      Regular => {
        require(files.length() < 9, "More than nine regular files")
        files.push((logical, read_capped_file(physical)))
      }
      _ => fail("Links and special files are not admitted")
    }
  }
}

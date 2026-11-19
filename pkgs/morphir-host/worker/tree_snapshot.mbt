///|
const TREE_DOCUMENT_BYTES : Int32 = 1048576

///|
const TREE_SNAPSHOT_BYTES : Int64 = 64 * 1024 * 1024

///|
const TREE_ENTRIES : Int32 = 4096

///|
const TREE_CACHE_BYTES : Int32 = 4 * 1024 * 1024

///|
priv struct CapturedDocument {
  slot : String
  size : Int32
  digest : String
}

///|
priv struct TreeCapture {
  directory : @platform.BoundedDirectory
  documents : Map[String, CapturedDocument]
  modules : Array[String]
  revision : String
  context_digest : String
  bytes : Int64
  cache : Int32
  work : Int64
}

///|
priv enum CapturePass {
  Copy
  Verify
}

///|
priv struct TreeCaptureWalk {
  pass : CapturePass
  directory : @platform.BoundedDirectory
  documents : Map[String, CapturedDocument]
  versions : Map[String, String]
  check : () -> Unit raise
  output_parent : String
  mut entries : Int32
  mut bytes : Int64
  mut cache : Int32
  mut work : Int64
}

///|
fn tree_changed(path : String) -> Unit raise TreeGenerationError {
  raise TreeSource("source changed during capture: " + path)
}

///|
fn TreeCaptureWalk::version(
  self : TreeCaptureWalk,
  path : String,
  version : String,
) -> Unit raise {
  match self.pass {
    Copy => self.versions[path] = version
    Verify => {
      guard self.versions.get(path) == Some(version) else { tree_changed(path) }
    }
  }
}

///|
fn tree_suffix(name : String) -> String? {
  if name.has_suffix(".json") {
    Some(".json")
  } else if name.has_suffix(".yaml") {
    Some(".yaml")
  } else if name.has_suffix(".yml") {
    Some(".yml")
  } else {
    None
  }
}

///|
fn TreeCaptureWalk::document(
  self : TreeCaptureWalk,
  parent : @platform.BoundedDirectory,
  name : String,
  path : String,
  version : String,
) -> Unit raise {
  self.version(path, version)
  guard tree_budget_fits(self.bytes, 0L, TREE_SNAPSHOT_BYTES) else {
    raise TreeSource("source exceeds the snapshot byte limit")
  }
  let limit = @cmp.minimum(
    TREE_DOCUMENT_BYTES.to_int64(),
    TREE_SNAPSHOT_BYTES - self.bytes,
  )
  // Narrow only after clamping to the per-document Int32 bound.
  let bytes = parent.read(name, limit.to_int())
  guard parent.stamp(name~) == version else { tree_changed(path) }
  let digest = @identity.sha256(bytes)
  match self.pass {
    Copy => {
      let slot = self.documents.length().to_string()
      self.directory.write(slot, bytes, offset=0, create=true)
      self.documents[path] = { slot, digest, size: bytes.length(), }
    }
    Verify => {
      guard self.documents.get(path) is Some(expected) &&
        expected.size == bytes.length() &&
        expected.digest == digest else {
        tree_changed(path)
      }
    }
  }
  self.bytes += bytes.length().to_int64()
  self.work += 1L + bytes.length().to_int64() / 65536L
}

///|
fn TreeCaptureWalk::visit(
  self : TreeCaptureWalk,
  source : @platform.BoundedDirectory,
  prefix : String,
  depth : Int32,
  expected : String,
) -> Unit raise {
  (self.check)()
  guard depth <= 32 && source.stamp() == expected else {
    raise TreeSource("source changed or directory depth exceeds 32: " + prefix)
  }
  guard expected != self.output_parent else {
    raise TreeSource("the output parent is inside the selected model tree")
  }
  self.version(prefix, expected)
  let names = source.list(TREE_ENTRIES - self.entries)
  self.entries += names.length()
  self.work += 1L + names.length().to_int64()
  for name in names {
    (self.check)()
    let path = if prefix == "" { name } else { prefix + "/" + name }
    let root_directory = name == "pkg" || name == "deps"
    let root_manifest = name == "manifest.json" ||
      name == "manifest.yaml" ||
      name == "manifest.yml"
    if prefix == "" && !root_directory && !root_manifest {
      continue
    }
    self.cache += 512 + 4 * path.length()
    guard path.length() <= 1024 &&
      self.cache <= TREE_CACHE_BYTES &&
      !path.contains("\\") &&
      !path.contains(":") &&
      !path.iter().any(c => c < ' ' || c == '\u007f') else {
      raise TreeSource("invalid or over-budget tree path: " + path)
    }
    let stamp = source.stamp(name~)
    if stamp.has_prefix("d:") && (prefix != "" || root_directory) {
      let child = source.child(name)
      defer child.close()
      self.visit(child, path, depth + 1, stamp)
    } else if stamp.has_prefix("f:") && (prefix != "" || !root_directory) {
      if tree_suffix(name) is Some(_) {
        self.document(source, name, path, stamp)
      }
    } else {
      raise TreeSource("expected a regular file or directory: " + path)
    }
  }
  guard source.stamp() == expected else { tree_changed(prefix) }
}

///|
fn capture_tree(
  reopen : () -> @platform.BoundedDirectory raise,
  source : @platform.BoundedDirectory,
  directory : @platform.BoundedDirectory,
  output_parent : String,
  check : () -> Unit raise,
) -> TreeCapture raise {
  let root = source.stamp()
  let copy : TreeCaptureWalk = {
    pass: Copy,
    directory,
    documents: Map([]),
    versions: Map([]),
    check,
    output_parent,
    entries: 0,
    bytes: 0,
    cache: 0,
    work: 0,
  }
  copy.visit(source, "", 0, root)
  // Each capture and comparison must observe the same directory/file stamp.
  // The second pass also compares content and ends by checking the named root.
  let verify = {
    ..copy,
    pass: Verify,
    entries: 0,
    bytes: 0,
    cache: 0,
    work: 0,
  }
  verify.visit(source, "", 0, root)
  let current = reopen()
  defer current.close()
  guard current.stamp() == root &&
    copy.entries == verify.entries &&
    copy.bytes == verify.bytes else {
    raise TreeSource("the selected source changed during capture")
  }
  let paths = copy.documents.keys().collect()
  paths.sort()
  let revision = @crypto.SHA256::new()
  let context = @crypto.SHA256::new()
  let modules : Array[String] = []
  let module_set : Map[String, Unit] = Map([])
  for path in paths {
    let digest = copy.documents[path].digest
    let line = @utf8.encode("\{path}\u0000\{digest}\n")
    revision.update(line)
    if path.has_prefix("deps/") || path.has_prefix("manifest.") {
      context.update(line)
    }
    let suffix = tree_suffix(path).unwrap()
    let logical = path[:path.length() - suffix.length()].to_owned()
    if logical.has_suffix("/module") && !module_set.contains(logical) {
      module_set[logical] = ()
      modules.push(logical)
    }
  }
  modules.sort_by((a, b) => a[:].lexical_compare(b[:]))
  {
    directory,
    documents: copy.documents,
    modules,
    revision: @crypto.bytes_to_hex_string(revision.finalize()),
    context_digest: @crypto.bytes_to_hex_string(context.finalize()),
    bytes: copy.bytes,
    cache: copy.cache,
    work: copy.work + verify.work,
  }
}

///|
fn TreeCapture::tree_source(
  self : TreeCapture,
  check : () -> Unit raise,
  observe~ : () -> Unit raise = fn() {  },
) -> @yaml.TreeSource {
  let verify = (revision : String) => {
    check()
    guard revision == self.revision else {
      raise @yaml.TreeSourceError::RevisionChanged
    }
  }
  {
    revision: () => {
      check()
      self.revision
    },
    contains: (revision, path) => {
      verify(revision)
      self.documents.contains(path)
    },
    next_module: (revision, prefix, after) => {
      verify(revision)
      let key = after.unwrap_or(prefix)
      let mut low = 0
      let mut high = self.modules.length()
      // Lower bound for a prefix, or upper bound for the last emitted path.
      while low < high {
        observe()
        let middle = low + (high - low) / 2
        let order = self.modules[middle][:].lexical_compare(key[:])
        if order < 0 || (order == 0 && after is Some(_)) {
          low = middle + 1
        } else {
          high = middle
        }
      }
      if low < self.modules.length() && self.modules[low].has_prefix(prefix) {
        Some(self.modules[low])
      } else {
        None
      }
    },
    read: (revision, path, max_bytes) => {
      verify(revision)
      guard self.documents.get(path) is Some(document) else {
        raise @yaml.TreeSourceError::RevisionChanged
      }
      guard document.size <= max_bytes else {
        raise @yaml.TreeSourceError::DocumentTooLarge
      }
      let bytes = self.directory.read(document.slot, document.size)
      guard @identity.sha256(bytes) == document.digest else {
        raise @yaml.TreeSourceError::RevisionChanged
      }
      @utf8.decode(bytes[:])
    },
  }
}

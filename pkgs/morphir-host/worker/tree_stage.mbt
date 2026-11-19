///|
priv struct StagedTreeFile {
  digest : @crypto.SHA256
  mut bytes : Int32
  mut finished : Bool
}

///|
priv struct TreeStage {
  parent : @platform.BoundedDirectory
  parent_path : String
  directory : @platform.BoundedDirectory
  temporary : String
  destination : String
  paths : Map[String, (String, Bool)]
  files : Map[String, StagedTreeFile]
  mut published : Bool
  mut bytes : Int32
  mut metadata : Int32
}

///|
fn TreeStage::open(
  output : String,
  nonce : String,
  source? : @platform.BoundedDirectory,
  diagnostics~ : Array[Diagnostic] = [],
) -> TreeStage raise {
  let (parent_path, destination) = tree_parent_leaf(output)
  let parent = @platform.BoundedDirectory::open(parent_path)
  errdefer parent.close()
  parent.require_owned()
  if source is Some(source) {
    parent.require_outside(source)
  }
  let temporary = ".morphir-bounded-" + nonce
  let directory = open_tree_scratch(
    parent, temporary, "artifact stage", diagnostics,
  )
  {
    parent,
    parent_path,
    directory,
    temporary,
    destination,
    paths: Map([]),
    files: Map([]),
    published: false,
    bytes: 0,
    metadata: 0,
  }
}

///|
fn TreeStage::remember(
  self : TreeStage,
  path : String,
  directory : Bool,
) -> Bool raise TreeGenerationError {
  let key = artifact_path_key(path)
  match self.paths.get(key) {
    Some((previous, kind)) => {
      guard previous == path && kind == directory else {
        raise TreeOutput(
          "artifact path collides with " + previous + ": " + path,
        )
      }
      false
    }
    None => {
      guard self.paths.length() < 1024 else {
        raise TreeOutput("staged file and directory limit exceeds 1024")
      }
      self.metadata += 512 + 4 * path.length() + 2 * key.length()
      self.paths[key] = (path, directory)
      true
    }
  }
}

///|
fn TreeStage::in_parent(
  self : TreeStage,
  parts : Array[String],
  create : Bool,
  f : (@platform.BoundedDirectory, String) -> Unit raise,
) -> Unit raise {
  let opened : Array[@platform.BoundedDirectory] = []
  defer (for directory in opened.rev() {
    directory.close()
  })
  let mut parent = self.directory
  let mut path = ""
  for index in 0..<(parts.length() - 1) {
    let name = parts[index]
    path = if path == "" { name } else { path + "/" + name }
    if create && self.remember(path, true) {
      parent.mkdir(name)
    }
    parent = parent.child(name)
    opened.push(parent)
  }
  f(parent, parts[parts.length() - 1])
}

///|
fn TreeStage::write(
  self : TreeStage,
  chunk : @model_access.ArtifactChunk,
  budget : TreeBudget,
  snapshot_bytes : Int32,
) -> Unit raise {
  let path = chunk.path
  guard path.length() <= 1024 &&
    !path.contains("\\") &&
    !path.contains(":") &&
    !path.iter().any(c => c < ' ' || c == '\u007f') else {
    raise TreeOutput("unsafe artifact path: " + path)
  }
  let parts = path.split("/").map(part => part.to_owned()).to_array()
  guard parts.length() <= 16 &&
    parts
    .iter()
    .all(p => {
      p != "" && p != "." && p != ".." && @utf8.encode(p).length() <= 255
    }) else {
    raise TreeOutput("unsafe artifact path: " + path)
  }
  let size = chunk.decoded_byte_length
  let file_size = chunk.offset + size.to_int64()
  guard size <= budget.chunk &&
    file_size <= budget.file.to_int64() &&
    size <= budget.total - self.bytes &&
    size <= budget.disk - snapshot_bytes - self.bytes &&
    chunk.content.length() == (size + 2) / 3 * 4 else {
    raise TreeOutput("artifact exceeds a byte limit: " + path)
  }
  let bytes = @base64.decode(chunk.content) catch {
    _ => raise TreeOutput("invalid artifact base64: " + path)
  }
  guard bytes.length() == size &&
    @base64.encode(bytes[:]) == chunk.content &&
    @identity.sha256(bytes) == chunk.sha256 else {
    raise TreeOutput("artifact length, encoding, or digest mismatch: " + path)
  }
  self.in_parent(parts, true, (parent, name) => {
    let created = self.remember(path, false)
    let file = if created {
      let file : StagedTreeFile = {
        digest: @crypto.SHA256::new(),
        bytes: 0,
        finished: false,
      }
      self.files[path] = file
      file
    } else {
      self.files[path]
    }
    guard !file.finished && chunk.offset == file.bytes.to_int64() else {
      raise TreeOutput(
        "overlapping, out-of-order, or post-final chunk: " + path,
      )
    }
    parent.write(name, bytes, offset=file.bytes, create=created)
    file.digest.update(bytes)
    file.bytes += size
    file.finished = chunk.final_chunk
    self.bytes += size
  })
}

///|
fn TreeStage::verify_directory(
  self : TreeStage,
  directory : @platform.BoundedDirectory,
  prefix : String,
  expected : Map[String, String],
  count : Ref[Int32],
  check : () -> Unit raise,
) -> Unit raise {
  check()
  let stamp = directory.stamp()
  for name in directory.list(self.paths.length() - count.val) {
    check()
    guard count.val < self.paths.length() else {
      raise TreeOutput("unexpected staged entry: " + name)
    }
    count.val += 1
    let path = if prefix == "" { name } else { prefix + "/" + name }
    guard self.paths.get(artifact_path_key(path)) is Some((original, is_dir)) &&
      original == path else {
      raise TreeOutput("unexpected staged entry: " + path)
    }
    if is_dir {
      let child = directory.child(name)
      defer child.close()
      self.verify_directory(child, path, expected, count, check)
    } else {
      let digest = @crypto.SHA256::new()
      directory.scan(name, self.files[path].bytes, check, bytes => {
        digest.update(bytes)
      })
      guard @crypto.bytes_to_hex_string(digest.finalize()) == expected[path] else {
        raise TreeOutput("staged file digest changed: " + path)
      }
    }
  }
  guard directory.stamp() == stamp else {
    raise TreeOutput("staged directory changed: " + prefix)
  }
}

///|
fn TreeStage::receipts(
  self : TreeStage,
  check : () -> Unit raise,
) -> Array[Json] raise {
  let paths = self.files.keys().collect()
  paths.sort()
  let expected : Map[String, String] = Map([])
  for path in paths {
    check()
    let file = self.files[path]
    guard file.finished else {
      raise TreeOutput("artifact has no final chunk: " + path)
    }
    expected[path] = @crypto.bytes_to_hex_string(file.digest.finalize())
  }
  let count = Ref(0)
  self.verify_directory(self.directory, "", expected, count, check)
  guard count.val == self.paths.length() else {
    raise TreeOutput("the stage is missing an artifact or directory")
  }
  paths.map(path => {
    "path": path,
    "bytes": self.files[path].bytes,
    "sha256": expected[path],
  })
}

///|
fn TreeStage::publish_checked(
  self : TreeStage,
  check : () -> Unit raise,
) -> Array[Json] raise {
  let receipts = self.receipts(check)
  check()
  self.parent.publish(
    self.parent_path,
    self.directory,
    self.temporary,
    self.destination,
  )
  self.published = true
  receipts
}

///|
fn open_tree_scratch(
  parent : @platform.BoundedDirectory,
  name : String,
  purpose : String,
  diagnostics : Array[Diagnostic],
) -> @platform.BoundedDirectory raise {
  parent.mkdir(name)
  errdefer (parent.remove(name, directory=true) catch {
    error => tree_cleanup_unconfirmed(diagnostics, purpose, error)
  })
  parent.child(name)
}

///|
fn tree_cleanup_unconfirmed(
  diagnostics : Array[Diagnostic],
  purpose : String,
  error : Error,
) -> Unit {
  let detail = match error {
    @platform.IOError(message) => message
    _ => error.to_string()
  }
  diagnostics.push({
    severity: Warning,
    code: Some("extension.cleanup_unconfirmed"),
    message: purpose + ": " + detail,
    location: None,
    related: [],
    data: None,
  })
}

///|
fn TreeStage::dispose(
  self : TreeStage,
  diagnostics~ : Array[Diagnostic] = [],
) -> Unit {
  if !self.published {
    self.parent.discard(self.directory, self.temporary) catch {
      error => tree_cleanup_unconfirmed(diagnostics, "artifact stage", error)
    }
  }
  self.directory.close()
  self.parent.close()
}

///|
/// Reject symbolic links at every component before each operation.
fn confined(root : String, path : String) -> String raise {
  let path = @workspace.normalize(path)
  let mut current = root
  for part in path.split("/") {
    if part == "" {
      continue
    }
    current = current + "/" + part.to_owned()
    let kind = @platform.kind(current)
    if kind == 3 || kind == 4 {
      raise @config.Invalid("Unsupported link or special file: " + current)
    }
  }
  current
}

///|
pub fn Mount::filesystem(root : String) -> Mount raise {
  if @platform.kind(root) != 2 {
    raise @config.Invalid("Mount must be a directory: " + root)
  }
  {
    kind: fn(path) raise { @platform.kind(confined(root, path)) },
    read: fn(path) raise {
      let file = confined(root, path)
      if @platform.kind(file) != 1 {
        raise @config.Invalid("Expected a regular file: " + path)
      }
      @platform.read(file)
    },
    list: fn(path) raise { @platform.list(confined(root, path)) },
  }
}

///|
fn ensure_dirs(root : String, path : String) -> Unit raise {
  let path = @workspace.normalize(path)
  let mut current = ""
  for component in path.split("/") {
    if component == "" {
      continue
    }
    current = @workspace.join(current, component.to_owned())
    let full = confined(root, current)
    match @platform.kind(full) {
      0 => @platform.mkdir(full)
      2 => ()
      _ => raise @config.Invalid("Expected output directory: " + full)
    }
  }
}

///|
fn delete_owned(root : String, path : String) -> Unit raise {
  let full = confined(root, path)
  match @platform.kind(full) {
    0 => ()
    1 => @platform.remove_file(full)
    2 => {
      for name in @platform.list(full) {
        delete_owned(root, @workspace.join(path, name))
      }
      @platform.remove_dir(full)
    }
    _ => raise @config.Invalid("Refusing to remove nonregular staging entry")
  }
}

///|
fn relative_to(root : String, path : String) -> String raise {
  if !@workspace.within(root, path) || path == root {
    raise @config.Invalid("Artifact outside output root: " + path)
  }
  if root == "" {
    path
  } else {
    path[root.length() + 1:].to_owned()
  }
}

///|
pub fn ContentPublisher::filesystem(
  root : String,
  output_root : String,
) -> ContentPublisher raise {
  filesystem_content_publisher(root, output_root, @platform.rename)
}

///|
// Keep the default filesystem operations fixed; whitebox fault tests can fail
// the publish and restore operations independently without timing filesystem races.
fn filesystem_content_publisher(
  root : String,
  output_root : String,
  rename : (String, String) -> Unit raise,
) -> ContentPublisher raise {
  let output_root = @workspace.normalize(output_root)
  if output_root == "" {
    raise @config.Invalid("Publication root cannot be empty")
  }
  {
    guarantee: RecoverableTask,
    write_bytes: @platform.bytes_supported(),
    begin: fn(destinations) raise {
      ensure_dirs(root, output_root)
      let lock = @workspace.join(output_root, ".morphir-publish.lock")
      // Exclusive mkdir serializes publishers. Existing locks require explicit recovery.
      @platform.mkdir(confined(root, lock))
      let stage = @workspace.join(lock, "stage")
      let backup = @workspace.join(lock, "backup")
      errdefer delete_owned(root, lock)
      {
        ensure_dirs(root, stage)
        ensure_dirs(root, backup)
        for destination in destinations {
          let target = @workspace.join(
            stage,
            relative_to(output_root, destination),
          )
          ensure_dirs(root, @workspace.parent(target))
          @platform.mkdir(confined(root, target))
        }
      }
      let done = Map([])
      let recovery = Ref(false)
      {
        stage: fn(artifact) raise {
          if !destinations.any(d => @workspace.within(d, artifact.path)) {
            raise @config.Invalid("Artifact outside planned destination")
          }
          let target = @workspace.join(
            stage,
            relative_to(output_root, artifact.path),
          )
          ensure_dirs(root, @workspace.parent(target))
          if @platform.kind(confined(root, target)) != 0 {
            raise @config.Invalid(
              "Output paths collide on this filesystem: " + artifact.path,
            )
          }
          match artifact.content {
            Text(text) => @platform.write(confined(root, target), text)
            Binary(bytes) =>
              @platform.write_bytes(confined(root, target), bytes)
          }
        },
        commit: fn(destination) raise {
          if !destinations.contains(destination) || done.contains(destination) {
            raise @config.Invalid("Invalid publication destination")
          }
          let rel = relative_to(output_root, destination)
          let staged = @workspace.join(stage, rel)
          let saved = @workspace.join(backup, rel)
          ensure_dirs(root, @workspace.parent(destination))
          ensure_dirs(root, @workspace.parent(saved))
          let existing = @platform.kind(confined(root, destination))
          if existing != 0 && existing != 2 {
            raise @config.Invalid("Destination is not a directory")
          }
          if existing == 2 {
            rename(confined(root, destination), confined(root, saved))
          }
          rename(confined(root, staged), confined(root, destination)) catch {
            cause => {
              if existing == 2 {
                rename(confined(root, saved), confined(root, destination)) catch {
                  rollback => {
                    recovery.val = true
                    raise @config.Invalid(
                      "Publication failed: " +
                      error_message(cause) +
                      "; Rollback failed; preserved backup at " +
                      saved +
                      ": " +
                      error_message(rollback),
                    )
                  }
                }
              }
              raise cause
            }
          }
          done[destination] = true
        },
        abort: fn() raise {
          if recovery.val {
            raise @config.Invalid(
              "Manual recovery required; preserving " + lock,
            )
          }
          delete_owned(root, lock)
        },
      }
    },
  }
}

///|
pub fn error_message(error : Error) -> String {
  match error {
    @protocol.Invalid(message) => message
    @linked_metadata.Invalid(code, context, detail) =>
      code + ": " + context + " " + detail
    @moonbit.Invalid(code, context, detail) =>
      code + ": " + context + " " + detail
    @data.Invalid(code, detail) => code + ": " + detail
    @config.Invalid(message) => message
    @platform.IOError(message) => message
    @toolchain.ToolchainError(message) => message
    _ => error.to_string()
  }
}

///|
/// Keep the text publisher API as an adapter over the same transaction.
pub fn Publisher::filesystem(
  root : String,
  output_root : String,
) -> Publisher raise {
  let publisher = ContentPublisher::filesystem(root, output_root)
  {
    guarantee: publisher.guarantee,
    begin: fn(destinations) raise {
      let publication = (publisher.begin)(destinations)
      {
        stage: fn(artifact) raise {
          (publication.stage)({
            path: artifact.path,
            source: artifact.source,
            content: @data.Text(artifact.content),
            format: "text",
          })
        },
        commit: publication.commit,
        abort: publication.abort,
      }
    },
  }
}

///|
pub fn Mount::filesystem_bytes(
  root : String,
) -> ((String) -> Bytes raise) raise {
  if @platform.kind(root) != 2 {
    raise @config.Invalid("Mount must be a directory: " + root)
  }
  if !@platform.bytes_supported() {
    raise @config.Invalid(
      "host.byte_read_required: Embedding host does not advertise byte operations",
    )
  }
  fn(path) raise {
    let file = confined(root, path)
    if @platform.kind(file) != 1 {
      raise @config.Invalid("Expected a regular file: " + path)
    }
    @platform.read_bytes(file)
  }
}

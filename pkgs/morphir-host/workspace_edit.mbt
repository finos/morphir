///|
/// Apply a scaffolding edit under an exclusive workspace lock. Files and removed directories are
/// backed up until every replacement succeeds. A failed rollback preserves the lock for recovery.
pub fn apply_workspace_edit(
  root : String,
  tree : @workspace.Tree,
  edit : @workspace.Edit,
) -> Unit raise {
  apply_workspace_edit_with(root, tree, edit, @platform.link_file_new)
}

///|
fn apply_workspace_edit_with(
  root : String,
  tree : @workspace.Tree,
  edit : @workspace.Edit,
  publish_file : (String, String) -> Unit raise,
) -> Unit raise {
  ignore(Mount::filesystem(root))
  ignore(edit.apply(tree))
  let lock = ".morphir-workspace-edit.lock"
  for path in edit.writes.keys().collect() + edit.deletes + edit.directories {
    if @workspace.within(lock, path) ||
      path == "" ||
      @workspace.normalize(path) != path {
      raise @config.Invalid("Invalid workspace edit path: " + path)
    }
  }
  @platform.mkdir(confined(root, lock))
  let recovery = Ref(false)
  defer (if !recovery.val { delete_owned(root, lock) })
  let writes = edit.writes.keys().collect()
  // Source files first, then member configs, then the workspace config.
  writes.sort_by(fn(a, b) {
    let a_existing = tree.files.contains(a)
    let b_existing = tree.files.contains(b)
    let a_config = a.has_suffix(".toml")
    let b_config = b.has_suffix(".toml")
    if a_existing != b_existing {
      if a_existing {
        1
      } else {
        -1
      }
    } else if a_config != b_config {
      if a_config {
        1
      } else {
        -1
      }
    } else if a_config {
      b.length().compare(a.length())
    } else {
      a.compare(b)
    }
  })
  let mut entries = 0
  fn inspect_delete(path : String, depth : Int32) -> Unit raise {
    entries += 1
    if entries > 10000 || depth > 64 {
      raise @config.Invalid("Workspace deletion entry/depth limit exceeded")
    }
    let full = confined(root, path)
    match @platform.kind(full) {
      1 => ()
      2 =>
        for child in @platform.list(full) {
          inspect_delete(@workspace.join(path, child), depth + 1)
        }
      _ =>
        raise @config.Invalid(
          "Refusing to delete missing, linked or special entry: " + path,
        )
    }
  }
  // Complete preflight before writing any project files.
  for path in writes {
    let full = confined(root, path)
    match tree.files.get(path) {
      Some(expected) =>
        if @platform.kind(full) != 1 || @platform.read(full) != expected {
          raise @config.Invalid("Workspace changed since discovery: " + path)
        }
      None =>
        if @platform.kind(full) != 0 {
          raise @config.Invalid("Workspace edit would overwrite: " + path)
        }
    }
    if edit.deletes.any(d => @workspace.within(d, path)) {
      raise @config.Invalid(
        "Workspace edit writes into a removed directory: " + path,
      )
    }
    let staged = @workspace.join(lock + "/stage", path)
    ensure_dirs(root, @workspace.parent(staged))
    @platform.write(confined(root, staged), edit.writes[path])
  }
  for path in edit.deletes {
    inspect_delete(path, 0)
  }
  let backups : Array[(String, String)] = []
  let installed : Array[String] = []
  let created_directories : Array[String] = []
  fn ensure_edit_dirs(path : String) -> Unit raise {
    let mut current = ""
    for component in path.split("/") {
      guard component != "" else { continue }
      current = @workspace.join(current, component.to_owned())
      let full = confined(root, current)
      match @platform.kind(full) {
        0 => {
          @platform.mkdir(full)
          created_directories.push(current)
        }
        2 => ()
        _ => raise @config.Invalid("Expected output directory: " + full)
      }
    }
  }
  errdefer (try {
    for i = installed.length() - 1; i >= 0; i = i - 1 {
      let path = installed[i]
      let full = confined(root, path)
      if @platform.kind(full) != 1 || @platform.read(full) != edit.writes[path] {
        raise @config.Invalid("Workspace changed during rollback: " + path)
      }
      @platform.remove_file(full)
    }
    for i = backups.length() - 1; i >= 0; i = i - 1 {
      let (path, saved) = backups[i]
      let source = confined(root, saved)
      let destination = confined(root, path)
      if @platform.kind(source) == 1 {
        publish_file(source, destination)
      } else {
        @platform.rename(source, destination)
      }
    }
    for i = created_directories.length() - 1; i >= 0; i = i - 1 {
      // Remove only empty directories created by this edit. Concurrent contents
      // refuse cleanup and keep the recovery lock rather than being deleted.
      @platform.remove_dir(confined(root, created_directories[i]))
    }
  } catch {
    rollback => {
      recovery.val = true
      raise @config.Invalid(
        "Workspace edit rollback failed; preserved " +
        lock +
        ": " +
        error_message(rollback),
      )
    }
  })
  for path in edit.deletes {
    let saved = @workspace.join(lock + "/deleted", path)
    ensure_dirs(root, @workspace.parent(saved))
    @platform.rename(confined(root, path), confined(root, saved))
    backups.push((path, saved))
  }
  for directory in edit.directories {
    ensure_edit_dirs(directory)
  }
  for path in writes {
    ensure_edit_dirs(@workspace.parent(path))
    let full = confined(root, path)
    if tree.files.contains(path) {
      if @platform.kind(full) != 1 || @platform.read(full) != tree.files[path] {
        raise @config.Invalid("Workspace changed while applying edit: " + path)
      }
      let saved = @workspace.join(lock + "/backup", path)
      ensure_dirs(root, @workspace.parent(saved))
      @platform.rename(full, confined(root, saved))
      backups.push((path, saved))
    } else if @platform.kind(full) != 0 {
      raise @config.Invalid("Workspace changed while applying edit: " + path)
    }
    // A hard link publishes the complete staged file only if the destination
    // is absent. Keep its staging link until success or rollback cleanup.
    publish_file(confined(root, @workspace.join(lock + "/stage", path)), full)
    installed.push(path)
  }
}

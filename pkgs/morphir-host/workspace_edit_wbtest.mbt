///|
#cfg(any(target="js", target="native"))
test "workspace edits restore sources config and deleted directories after an install failure" {
  let root = @platform.temporary()
  defer delete_owned(root, "")
  @platform.write(
    root + "/morphir.toml",
    "# original\n[workspace]\nmembers=['old']\n",
  )
  @platform.mkdir(root + "/old")
  @platform.write_bytes(root + "/old/keep.bin", b"\x00\xff\xfe")
  let tree = @workspace.Tree::from_files(
    Map::from_array([
      ("morphir.toml", @platform.read(root + "/morphir.toml")),
      ("old/keep.bin", ""),
    ]),
  )
  let edit : @workspace.Edit = {
    writes: Map::from_array([
      ("morphir.toml", "[workspace]\nmembers=['new']\n"),
      ("new/src/main.scm", "42"),
    ]),
    directories: ["new/src"],
    deletes: ["old"],
    warnings: [],
  }
  let result = try {
    apply_workspace_edit_with(root, tree, edit, fn(a, b) raise {
      if a.has_suffix("/stage/morphir.toml") {
        raise @config.Invalid("injected install failure")
      }
      @platform.link_file_new(a, b)
    })
    "accepted"
  } catch {
    error => error_message(error)
  }
  assert_eq(result, "injected install failure")
  assert_eq(@platform.read(root + "/morphir.toml"), tree.files["morphir.toml"])
  assert_eq(@platform.read_bytes(root + "/old/keep.bin"), b"\x00\xff\xfe")
  assert_eq(@platform.kind(root + "/new/src/main.scm"), 0)
  assert_eq(@platform.kind(root + "/new"), 0)
  assert_eq(@platform.kind(root + "/.morphir-workspace-edit.lock"), 0)
}

///|
#cfg(any(target="js", target="native"))
test "workspace edit preflight refuses stale configs and preserves a lock owned by someone else" {
  let root = @platform.temporary()
  defer delete_owned(root, "")
  @platform.write(root + "/morphir.toml", "# new\n[workspace]\n")
  let tree = @workspace.Tree::from_files(
    Map::from_array([("morphir.toml", "[workspace]\n")]),
  )
  let edit : @workspace.Edit = {
    writes: Map::from_array([
      ("morphir.toml", "[workspace]\nmembers=[]\n"),
      ("new.txt", "new"),
    ]),
    directories: [],
    deletes: [],
    warnings: [],
  }
  let message = try {
    apply_workspace_edit(root, tree, edit)
    "accepted"
  } catch {
    error => error_message(error)
  }
  assert_true(message.contains("Workspace changed"))
  assert_eq(@platform.read(root + "/morphir.toml"), "# new\n[workspace]\n")
  assert_eq(@platform.kind(root + "/new.txt"), 0)
  @platform.mkdir(root + "/.morphir-workspace-edit.lock")
  @platform.write(
    root + "/.morphir-workspace-edit.lock/owner",
    "other transaction",
  )
  assert_true(
    try {
      apply_workspace_edit(root, tree, edit)
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    @platform.read(root + "/.morphir-workspace-edit.lock/owner"),
    "other transaction",
  )
}

///|
#cfg(any(target="js", target="native"))
test "failed workspace edit rollback preserves the backup for recovery" {
  let root = @platform.temporary()
  defer delete_owned(root, "")
  @platform.write(root + "/morphir.toml", "[workspace]\n")
  let tree = @workspace.Tree::from_files(
    Map::from_array([("morphir.toml", "[workspace]\n")]),
  )
  let edit : @workspace.Edit = {
    writes: Map::from_array([("morphir.toml", "[workspace]\nmembers=[]\n")]),
    directories: [],
    deletes: [],
    warnings: [],
  }
  let message = try {
    apply_workspace_edit_with(root, tree, edit, fn(a, b) raise {
      if a.contains("/stage/") || a.contains("/backup/") {
        raise @config.Invalid("injected rename failure")
      }
      @platform.link_file_new(a, b)
    })
    "accepted"
  } catch {
    error => error_message(error)
  }
  assert_true(message.contains("rollback failed; preserved"))
  assert_eq(
    @platform.read(root + "/.morphir-workspace-edit.lock/backup/morphir.toml"),
    "[workspace]\n",
  )
}

///|
#cfg(any(target="js", target="native"))
test "file publication and rollback never replace a concurrent destination" {
  for replacing in [false, true] {
    let root = @platform.temporary()
    defer delete_owned(root, "")
    let original = "[workspace]\n"
    if replacing {
      @platform.write(root + "/morphir.toml", original)
    }
    let tree = @workspace.Tree::from_files(
      if replacing {
        Map([("morphir.toml", original)])
      } else {
        Map([])
      },
    )
    let edit : @workspace.Edit = {
      writes: Map([("morphir.toml", "[workspace]\nmembers=[]\n")]),
      directories: [],
      deletes: [],
      warnings: [],
    }
    let message = try {
      apply_workspace_edit_with(root, tree, edit, fn(a, b) raise {
        if a.contains("/stage/") {
          // This runs after both the absence check and any backup move.
          @platform.write(b, "concurrent contents")
        }
        @platform.link_file_new(a, b)
      })
      "accepted"
    } catch {
      error => error_message(error)
    }
    assert_true(message != "accepted")
    assert_eq(@platform.read(root + "/morphir.toml"), "concurrent contents")
    if replacing {
      assert_true(message.contains("rollback failed; preserved"))
      assert_eq(
        @platform.read(
          root + "/.morphir-workspace-edit.lock/backup/morphir.toml",
        ),
        original,
      )
    } else {
      assert_eq(@platform.kind(root + "/.morphir-workspace-edit.lock"), 0)
    }
  }
}

///|
#cfg(any(target="js", target="native"))
test "rollback removes new directories but keeps preexisting empty parents" {
  let root = @platform.temporary()
  defer delete_owned(root, "")
  @platform.mkdir(root + "/existing")
  let tree = @workspace.Tree::from_files(Map([]))
  let edit : @workspace.Edit = {
    writes: Map([("existing/new/src/main.scm", "42")]),
    directories: ["existing/new/src"],
    deletes: [],
    warnings: [],
  }
  let failed = try {
    apply_workspace_edit_with(root, tree, edit, fn(_, _) raise {
      raise @config.Invalid("injected install failure")
    })
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(@platform.kind(root + "/existing/new"), 0)
  assert_eq(@platform.kind(root + "/existing"), 2)
  assert_eq(@platform.kind(root + "/.morphir-workspace-edit.lock"), 0)
}

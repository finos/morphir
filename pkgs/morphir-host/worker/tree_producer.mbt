///|
/// Input provenance is selected before capture. An explicit directory is the
/// unqualified capture path. A producer result selects the task's read lease.
pub(all) enum TreeGenerationInput {
  ExplicitDirectory(String)
  CompileResult(String)
}

///|
priv struct OpenTreeInput {
  directory : @platform.BoundedDirectory
  protected_directory : @platform.BoundedDirectory
  reopen : () -> @platform.BoundedDirectory raise
  release : () -> Unit
}

///|
fn TreeGenerationInput::opened(
  directory : @platform.BoundedDirectory,
  protected_directory : @platform.BoundedDirectory,
  reopen : () -> @platform.BoundedDirectory raise,
  release_lease : () -> Unit,
) -> OpenTreeInput {
  let open = Ref(true)
  {
    directory,
    protected_directory,
    reopen,
    release: () => {
      if open.val {
        open.val = false
        directory.close()
        release_lease()
      }
    },
  }
}

///|
fn tree_parent_leaf(path : String) -> (String, String) {
  match path.rev_find("/") {
    Some(0) => ("/", path[1:].to_owned())
    Some(index) => (path[:index].to_owned(), path[index + 1:].to_owned())
    None => (".", path)
  }
}

///|
fn producer_components(path : String) -> Array[String] raise {
  let parts = path.split("/").map(part => part.to_owned()).to_array()
  guard path.length() <= 1024 &&
    parts.length() <= 32 &&
    !path.contains("\\") &&
    !path.contains(":") &&
    !path.iter().any(c => c < ' ' || c == '\u007f') &&
    parts.iter().all(part => part != "" && part != "." && part != "..") else {
    raise TreeSource("invalid relative path in the producer result: " + path)
  }
  parts
}

///|
fn producer_ir_path(record : Json) -> Array[String] raise {
  guard @model_wire.integer_text(@model_wire.field(record, "schema")) == "1" &&
    @model_wire.field(record, "task") == Json::string("compile") else {
    raise TreeSource("expected a schema-1 compile result")
  }
  let member_path = @model_wire.string(@model_wire.field(record, "module"))
  if member_path != "" {
    ignore(producer_components(member_path))
  }
  match @model_wire.optional(record, "tombstone") {
    Some(True) => raise TreeSource("the producer result is a tombstone")
    Some(False) | None => ()
    _ => raise TreeSource("invalid tombstone flag in the producer result")
  }
  guard !@model_wire.string(@model_wire.field(record, "completedAt")).is_empty() else {
    raise TreeSource("the producer result has no completion time")
  }
  if @model_wire.optional(record, "compileScope") is Some(Object(scope)) &&
    scope.get("kind") == Some(Json::string("explicit-selection")) {
    raise TreeSource(
      "the producer result was compiled from an explicit source selection",
    )
  }
  guard @model_wire.optional(record, "ir") is Some(descriptor) else {
    raise TreeSource("the producer result has no IR descriptor")
  }
  guard @model_wire.field(descriptor, "layout") == Json::string("document-tree") &&
    @model_wire.field(descriptor, "format") == Json::string("json") &&
    [Json::string("v4"), Json::string("v4.0.0")].contains(
      @model_wire.field(descriptor, "version"),
    ) else {
    raise TreeSource(
      "the producer result must describe a JSON IR 4.0.0 document tree",
    )
  }
  let path = @model_wire.string(@model_wire.field(descriptor, "path"))
  guard @model_wire.array(@model_wire.field(record, "value")).contains(
    Json::string(path),
  ) else {
    raise TreeSource("the IR descriptor does not name a declared task product")
  }
  producer_components(path)
}

///|
fn open_producer_product(
  parent : @platform.BoundedDirectory,
  parts : Array[String],
  index : Int32,
) -> @platform.BoundedDirectory raise {
  let child = parent.child(parts[index])
  if index + 1 == parts.length() {
    child
  } else {
    defer child.close()
    open_producer_product(child, parts, index + 1)
  }
}

///|
async fn open_compile_result(
  path : String,
  check : () -> Unit raise,
) -> OpenTreeInput {
  let (directory, name) = tree_parent_leaf(path)
  guard name == "compile.json" else {
    raise TreeSource("--task-result must name the producer's compile.json")
  }
  let parent = @platform.BoundedDirectory::open(directory)
  let retained = Ref(false)
  defer (if !retained.val { parent.close() })
  parent.require_owned()
  let lease = for ;; {
    check()
    match parent.try_task_lease("compile.lock") {
      Some(lease) => break lease
      None => @async.sleep(20)
    }
  }
  defer (if !retained.val { lease.close() })
  guard lease.matches(parent, "compile.lock") else {
    raise TreeSource("the producer task lock changed before reading its result")
  }
  let version = parent.stamp(name~)
  let bytes = parent.read(name, 262144)
  let record = @model_wire.parse_bounded(
    @utf8.decode(bytes[:]),
    max_depth=32,
    max_nodes=10000,
  )
  let parts = producer_ir_path(record)
  let product = parent.child("compile.dest")
  defer (if !retained.val { product.close() })
  let reopen = () => {
    check()
    guard parent.stamp(name~) == version &&
      lease.matches(parent, "compile.lock") else {
      raise TreeSource(
        "the producer record or task lock changed during capture",
      )
    }
    let named = parent.child("compile.dest")
    defer named.close()
    guard product.same_directory(named) else {
      raise TreeSource("the producer destination changed during capture")
    }
    open_producer_product(product, parts, 0)
  }
  let source = reopen()
  retained.val = true
  TreeGenerationInput::opened(source, product, reopen, () => {
    product.close()
    lease.close()
    parent.close()
  })
}

///|
async fn TreeGenerationInput::open(
  self : TreeGenerationInput,
  check : () -> Unit raise,
) -> OpenTreeInput {
  check()
  match self {
    ExplicitDirectory(path) => {
      let reopen = () => @platform.BoundedDirectory::open(path)
      let directory = reopen()
      TreeGenerationInput::opened(directory, directory, reopen, () => ())
    }
    CompileResult(path) => open_compile_result(path, check)
  }
}

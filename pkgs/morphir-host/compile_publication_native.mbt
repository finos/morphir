///|
priv struct CompileTask {
  parent : @platform.BoundedDirectory
  lease : @platform.TaskLease
  parent_path : String
  module_path : String
  mut record : Json?
}

///|
fn CompileTask::close(self : CompileTask) -> Unit {
  self.lease.close()
  self.parent.close()
}

///|
fn CompileTask::check(self : CompileTask) -> Unit raise {
  let directory = @platform.BoundedDirectory::open(self.parent_path)
  defer directory.close()
  guard self.parent.same_directory(directory) &&
    self.lease.matches(directory, "compile.lock") else {
    raise @config.Invalid("task_record.lock_changed")
  }
}

///|
fn CompileTask::write(self : CompileTask, record : Json) -> Unit raise {
  let name = ".compile-" + @platform.observation_id() + ".json"
  let bytes = @utf8.encode(record.stringify() + "\n")
  guard bytes.length() <= 262144 else {
    raise @config.Invalid("task_record.byte_limit")
  }
  self.parent.write(name, bytes, offset=0, create=true)
  errdefer (self.parent.remove(name, directory=false) catch { _ => () })
  self.parent.replace_file(name, "compile.json")
}

///|
fn CompileTask::previous(self : CompileTask) -> Json? raise {
  let path = confined(self.parent_path, "compile.json")
  match @platform.kind(path) {
    0 => return None
    1 => ()
    _ => raise @config.Invalid("task_record.expected_regular_file")
  }
  let bytes = self.parent.read("compile.json", 262144)
  let previous = @wire.parse_bounded(
    @utf8.decode(bytes[:]),
    max_depth=32,
    max_nodes=10000,
  ) catch {
    _ => Json::null()
  }
  guard previous
    is Object(
      {
        "schema": Number(1.0, ..),
        "task": String("compile"),
        "module": String(module_path),
        "completedAt": String(_),
        ..
      }
    ) &&
    module_path == self.module_path else {
    self.parent.remove("compile.json", directory=false)
    return None
  }
  Some(previous)
}

///|
fn compile_record_fields(
  module_path : String,
  completed_at : Json,
  installed : Json?,
) -> Map[String, Json] {
  let fields : Map[String, Json] = {
    "schema": Json::number(1),
    "task": Json::string("compile"),
    "module": Json::string(module_path),
    "completedAt": completed_at,
    "inputs": Json::array([]),
    "value": Json::array([]),
  }
  if installed is Some(ledger) {
    fields["installed"] = ledger
  }
  fields
}

///|
fn CompileTask::prepare(
  self : CompileTask,
  artifacts : Array[(String, String?)],
  options : CompileRecordOptions?,
) -> Unit raise {
  self.check()
  let prior = self.previous()
  let installed = prior.bind(record => @wire.optional(record, "installed"))
  if options is Some(options) {
    let fields = compile_record_fields(
      self.module_path,
      Json::string(@platform.task_timestamp()),
      installed,
    )
    let mut products = artifacts.map(pair => pair.0)
    if options.tree_product is Some(tree) {
      guard tree != "" &&
        @workspace.normalize(tree) == tree &&
        artifacts.contains((tree + "/manifest.json", Some("v4"))) &&
        products.all(path => @workspace.within(tree, path) && path != tree) else {
        raise @config.Invalid("task_record.invalid_document_tree_product")
      }
      products = [tree]
      fields["ir"] = {
        "path": Json::string(tree),
        "layout": "document-tree",
        "format": "json",
        "version": "v4",
      }
    } else if artifacts is [(path, Some(version))] {
      fields["ir"] = {
        "path": Json::string(path),
        "layout": "single-file",
        "format": "json",
        "version": Json::string(version),
      }
    }
    if options.explicit_selection {
      fields["compileScope"] = { "kind": "explicit-selection" }
    }
    products.sort()
    fields["value"] = Json::array(products.map(Json::string))
    self.record = Some(Json::object(fields))
  }
  if prior is Some(prior) {
    let tombstone = compile_record_fields(
      self.module_path,
      @wire.field(prior, "completedAt"),
      installed,
    )
    tombstone["tombstone"] = Json::boolean(true)
    self.write(Json::object(tombstone))
  }
}

///|
fn open_compile_task(
  root : String,
  parent : String,
  module_path : String,
  acquired : Map[String, CompileTask],
  cancelled : () -> Bool,
) -> CompileTask raise {
  ensure_dirs(root, parent)
  let parent_path = confined(root, parent)
  let directory = @platform.BoundedDirectory::open(parent_path)
  errdefer directory.close()
  for task in acquired.values() {
    guard !directory.same_directory(task.parent) else {
      raise @config.Invalid("task_record.aliased_task_directory")
    }
  }
  let mut announced = false
  let lease = for ;; {
    if cancelled() || @platform.interruption_requested() {
      raise @platform.Interrupted
    }
    match directory.try_task_lease("compile.lock", exclusive=true) {
      Some(lease) => break lease
      None => {
        if !announced {
          @platform.stderr(
            "waiting for another Morphir run to finish compile (" +
            parent_path +
            "/compile.lock)\n",
          )
          announced = true
        }
        @platform.task_lock_pause()
      }
    }
  }
  { parent: directory, lease, parent_path, module_path, record: None, }
}

///|
fn begin_compile_publication(
  root : String,
  output_root : String,
  destinations : Array[String],
  options : CompileRecordOptions?,
  cancelled : () -> Bool,
) -> CompilePublication raise {
  if @platform.system_type() == "windows" {
    return CompilePublication::inactive()
  }
  let tasks : Map[String, CompileTask] = Map([])
  let close = () => {
    for task in tasks.values() {
      task.close()
    }
    tasks.clear()
  }
  errdefer close()
  let sorted = destinations.copy()
  sorted.sort()
  // Task locks precede the output-root mkdir guard. Multi-member operations
  // take task locks in the same order and never wait for one under that guard.
  for destination in sorted {
    let relative = relative_to(output_root, destination)
    if !tasks.contains(destination) &&
      relative.split("/").last() == Some("compile.dest") {
      let task = open_compile_task(
        root,
        @workspace.parent(destination),
        @workspace.parent(relative),
        tasks,
        cancelled,
      )
      tasks[destination] = task
    }
  }
  {
    record_options: destination => {
      if tasks.contains(destination) {
        options
      } else {
        None
      }
    },
    before: (destination, artifacts) => {
      if tasks.get(destination) is Some(task) {
        task.prepare(artifacts, options)
      }
    },
    complete: destination => {
      if tasks.get(destination) is Some(task) && task.record is Some(record) {
        task.check()
        task.write(record)
      }
    },
    close,
  }
}

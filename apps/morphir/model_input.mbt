///|
/// Capture explicit filesystem inputs before decoding. Shared codecs own model
/// semantics; the host mount owns path confinement and refuses links/specials.
fn load_local_model(cli : Cli, limits : @data.Limits) -> @data.IRUnit raise {
  let path = value(cli, "path")
  let unit_id = value(cli, "unit-id", fallback="workbench")
  if path != "-" && @platform.kind(path) == 2 {
    let explicit = value(cli, "model-format")
    if explicit != "" && !(@data.ModelFormat::from_control(explicit) is YAML) {
      raise @config.Invalid("Model directory requires the YAML tree codec")
    }
    @data.decode_model_tree(capture_model_tree(path, limits), unit_id~, limits~)
  } else {
    let format = model_input_format(path, value(cli, "model-format"))
    @data.decode_model(
      format,
      @platform.read_input(path, limits.max_bytes),
      unit_id~,
      limits~,
    )
  }
}

///|
/// Every visited directory/file and total captured bytes have finite budgets,
/// including ignored sidecars. No file is read through an unbounded text API.
fn capture_model_tree(
  root : String,
  limits : @data.Limits,
  directories~ : Array[String] = [],
) -> Map[String, Bytes] raise {
  let mount = @host.Mount::filesystem(root)
  let files : Map[String, Bytes] = Map([])
  let entries = Ref(0)
  let total = Ref(0)
  let path_units = Ref(0)
  fn visit(path : String, depth : Int32) -> Unit raise {
    if depth > limits.max_depth {
      raise @config.Invalid("data.tree_limit: Model input directory depth")
    }
    // kind executes Mount's full-component confinement before enumeration.
    if (mount.kind)(path) != 2 {
      raise @config.Invalid("data.invalid_path: Expected model input directory")
    }
    let remaining_entries = limits.max_values.min(8192) - entries.val
    let names = @platform.list_bounded(
      if path == "" {
        root
      } else {
        root + "/" + path
      },
      remaining_entries,
    ) catch {
      @platform.IOError("directory.entry_limit" | "directory.name_limit") =>
        raise @config.Invalid("data.tree_limit: Model input directory entries")
      cause => raise cause
    }
    // Reserve the entire listing before descending. Otherwise pending names in
    // ancestor listings would escape the aggregate entry/path budgets.
    entries.val += names.length()
    for i = 0; i < names.length(); i = i + 1 {
      let name = names[i]
      let child_length = path.length() +
        name.length() +
        (if path == "" { 0 } else { 1 })
      if child_length > 4096 || child_length > 1048576 - path_units.val {
        raise @config.Invalid("data.tree_limit: Model input path text")
      }
      let child = @workspace.join(path, name)
      if child != @workspace.normalize(child) ||
        name == "" ||
        name == "." ||
        name == ".." ||
        name.contains("/") ||
        name.contains("\\") {
        raise @config.Invalid("data.invalid_path: Model input directory entry")
      }
      ignore(@model_document.OriginalPath::parse(child))
      path_units.val += child_length
      names[i] = child
    }
    names.sort()
    for child in names {
      match (mount.kind)(child) {
        1 => {
          if files.length() >= @data.model_tree_file_limit {
            raise @config.Invalid("data.tree_limit: Model input file count")
          }
          let remaining = limits.max_bytes - total.val
          let bytes = @platform.read_input(root + "/" + child, remaining.max(1))
          if bytes.length() > remaining {
            raise @config.Invalid(
              "data.byte_limit: Model input directory bytes",
            )
          }
          total.val += bytes.length()
          files[child] = bytes
        }
        2 => {
          if directories.length() >= 4096 {
            raise @config.Invalid(
              "data.tree_limit: Model input directory count",
            )
          }
          directories.push(child)
          visit(child, depth + 1)
        }
        _ =>
          raise @config.Invalid(
            "data.invalid_path: Expected regular model input",
          )
      }
    }
  }
  visit("", 0)
  files
}

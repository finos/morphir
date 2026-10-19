///|
fn model_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  model_command_run(cli, mode) catch {
    error => {
      let message = @host.error_message(error)
      let code = match error {
        @platform.IOError("Cancelled") => "execution.cancelled"
        @model_document.InvalidFilename =>
          @model_document.DocumentError::InvalidFilename.code()
        @model_document.InvalidCodec =>
          @model_document.DocumentError::InvalidCodec.code()
        @model_document.InvalidVersion =>
          @model_document.DocumentError::InvalidVersion.code()
        @model_document.InvalidBytes =>
          @model_document.DocumentError::InvalidBytes.code()
        @model_document.TooLarge =>
          @model_document.DocumentError::TooLarge.code()
        @model_document.InvalidReply =>
          @model_document.DocumentError::InvalidReply.code()
        @model_document.RevisionLimit =>
          @model_document.DocumentError::RevisionLimit.code()
        _ => @host.error_code(error)
      }
      @platform.stderr(message + "\n")
      let report : Json = {
        "successful": false,
        "error": message,
        "code": code,
      }
      match mode {
        JSON => println(report.stringify())
        JSONLines => emit_record("error", report)
        Human => ()
      }
      if message == "Cancelled" {
        130
      } else {
        2
      }
    }
  }
}

///|
fn model_command_run(cli : Cli, mode : OutputMode) -> Int32 raise {
  let path = value(cli, "path")
  if path == "" {
    raise @config.Invalid("model.input_required")
  }
  @platform.interruption_start()
  defer @platform.interruption_stop()
  let limits = { ..@data.Limits::default(), max_bytes: 16777216, }
  let (inspection, original) = capture_local_original(cli, limits)
  let unit = inspection.unit
  let report = model_inspection(unit)
  guard report is Object(fields) else { abort("model inspection") }
  fields["sourceFormatVersion"] = Json::string(
    inspection.original_format_version.to_release_string(),
  )
  fields["representation"] = Json::string("normalized-ir")
  fields["originalKind"] = Json::string(
    match original {
      Original(_) => "captured-file"
      Tree(_) => "captured-inventory"
      Projection(_) => abort("captured input must own originals")
    },
  )
  fields["successful"] = Json::boolean(true)
  if cli.command == "model inspect" {
    match mode {
      JSON => println(report.stringify())
      JSONLines => emit_record("model", report)
      Human => println(report.stringify())
    }
    return 0
  }
  let output = @workspace.normalize(value(cli, "output"))
  if output == "" {
    raise @config.Invalid("model.output_required")
  }
  let destination = @workspace.join(output, "originals")
  let root = @platform.cwd()
  let mount = @host.Mount::filesystem(root)
  if (mount.kind)(destination) != 0 && !flag(cli, "overwrite") {
    raise @config.Invalid(
      "model.output_exists: Use --overwrite for the selected originals directory",
    )
  }
  let (files, directories) = match original {
    Original(file) =>
      (Map::from_array([(file.filename.to_string(), file.copy_bytes())]), [])
    Tree(tree) => (tree.copy_files(), tree.directory_paths())
    Projection(_) => raise @config.Invalid("model.originals_not_provided")
  }
  let saved = try {
    let publisher = @host.ContentPublisher::filesystem_inventory(
      root,
      output,
      directories.map(path => @workspace.join(destination, path)),
    )
    let transaction = (publisher.begin)([destination])
    defer (transaction.abort)()
    // Recheck under the publication lock: a competing writer may have created
    // the destination after the initial collision check.
    if (mount.kind)(destination) != 0 && !flag(cli, "overwrite") {
      raise @config.Invalid("model.output_exists")
    }
    let names = files.keys().collect()
    names.sort()
    for name in names {
      if @platform.interruption_requested() {
        raise @platform.IOError("Cancelled")
      }
      (transaction.stage)({
        path: @workspace.join(destination, name),
        source: path,
        format: "original-bytes",
        content: @data.Binary(files[name]),
      })
    }
    if @platform.interruption_requested() {
      raise @platform.IOError("Cancelled")
    }
    (transaction.commit)(destination)
    names.map(name => {
      (
        {
          "path": @workspace.join(destination, name),
          "byteLength": files[name].length(),
          "sha256": @identity.sha256(files[name]),
        } : Json)
    })
  } catch {
    error => {
      let message = @host.error_message(error)
      @platform.stderr(message + "\n")
      print_error(message, mode)
      return if message == "Cancelled" { 130 } else { 1 }
    }
  }
  let exported : Json = {
    "successful": true,
    "kind": "original",
    "published": [destination],
    "files": saved,
    "directories": directories,
  }
  match mode {
    JSON => println(exported.stringify())
    JSONLines => emit_record("published", exported)
    Human => println("Saved captured originals to " + destination)
  }
  0
}

///|
fn capture_local_original(
  cli : Cli,
  limits : @data.Limits,
) -> (@data.CheckpointInspection, @model_document.Source) raise {
  let path = value(cli, "path")
  let unit_id = value(cli, "unit-id", fallback="workbench")
  if path != "-" && @platform.kind(path) == 2 {
    let explicit = value(cli, "model-format")
    if explicit != "" && !(@data.ModelFormat::from_control(explicit) is YAML) {
      raise @config.Invalid("Model directory requires the YAML tree codec")
    }
    let directories = []
    let files = capture_model_tree(path, limits, directories~)
    let inspection = @data.inspect_model_tree(files, unit_id~, limits~)
    let tree = @model_document.OriginalTree::new(
      files,
      directories,
      inspection.original_format_version,
    )
    (inspection, @model_document.Source::Tree(tree))
  } else {
    let format = model_input_format(path, value(cli, "model-format"))
    let filename = if path == "-" {
      let name = value(cli, "filename")
      if name == "" {
        raise @config.Invalid("model.stdin_filename_required")
      }
      name
    } else {
      if value(cli, "filename") != "" {
        raise @config.Invalid("--filename is for stdin only")
      }
      path
      .replace_all(old="\\", new="/")
      .split("/")
      .last()
      .unwrap_or("")
      .to_owned()
    }
    let name = @model_document.OriginalFilename::parse(filename)
    let bytes = @platform.read_input(path, limits.max_bytes)
    let inspection = @data.inspect_model_source(
      format,
      bytes,
      unit_id~,
      limits~,
    )
    let original = @model_document.OriginalFile::new(
      name,
      @model_document.SourceCodec::parse(format.codec_id()),
      inspection.original_format_version,
      bytes,
    )
    (inspection, @model_document.Source::Original(original))
  }
}

///|
fn model_inspection(unit : @data.IRUnit) -> Json raise {
  let (kind, package_name, modules) = match unit.distribution.distribution {
    Library(name, _, definition) =>
      ("Library", name, definition.modules.keys().collect())
    Specs(name, _, specification) =>
      ("Specs", name, specification.modules.keys().collect())
    Application(name, _, definition, _) =>
      ("Application", name, definition.modules.keys().collect())
  }
  let modules = modules.map(path => path.to_canonical())
  modules.sort()
  {
    "unitId": unit.id,
    "irVersion": unit.distribution.format_version.to_release_string(),
    "distribution": kind,
    "packageName": package_name.to_canonical(),
    "modules": modules,
    "normalizedIr": @data.semantic_json(unit),
  }
}

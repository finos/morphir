///|
fn scaffolding_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  let location = if cli.command == "workspace init" {
    @host.Location::{ root: @platform.cwd(), invocation: "", file: None, }
  } else {
    @host.locate(".")
  }
  let snapshot = @host.Host::new(@host.Mount::filesystem(location.root)).snapshot()
  // Scaffolding needs every occupied file path, but never reads arbitrary binary files.
  let files = snapshot.tree.files.copy()
  for path in snapshot.paths {
    if !files.contains(path) {
      files[path] = ""
    }
  }
  let tree : @workspace.Tree = {
    files,
    directories: snapshot.tree.directories,
  }
  let language = match values(cli, "language").get(0) {
    Some(value) => Some(@ids.LanguageId::parse(value))
    None => None
  }
  let profile = match values(cli, "profile").get(0) {
    Some(value) => Some(@ids.ProfileId::parse(value))
    None => None
  }
  let edit = if cli.command == "workspace init" {
    let project = match values(cli, "project").get(0) {
      Some(name) =>
        Some(@workspace.NewProject::{
          name: @ids.SourcePackageName::parse(name),
          language,
          profile,
          source_directory: "src",
        })
      None => {
        if language is Some(_) || profile is Some(_) {
          raise @config.Invalid("--language and --profile require --project")
        }
        None
      }
    }
    @workspace.init_workspace(tree, project~)
  } else {
    let workspace = @workspace.discover(tree)
    let raw_path = match values(cli, "path").get(0) {
      Some(path) => path
      None => raise @config.Invalid("A project path is required")
    }
    let relative = @workspace.join(location.invocation, raw_path)
    if !@workspace.within(workspace.root, relative) {
      raise @config.Invalid("Project path is outside the workspace root")
    }
    let path = @workspace.ProjectPath::parse(
      if workspace.root == "" {
        relative
      } else if relative == workspace.root {
        ""
      } else {
        relative[workspace.root.length() + 1:].to_owned()
      },
    )
    if cli.command == "project add" {
      let name = match values(cli, "name").get(0) {
        Some(name) => @ids.SourcePackageName::parse(name)
        None => raise @config.Invalid("--name is required")
      }
      @workspace.add_project(workspace, tree, path, {
        name,
        language,
        profile,
        source_directory: "src",
      })
    } else {
      @workspace.remove_project(
        workspace,
        tree,
        path,
        delete_files=flag(cli, "delete"),
      )
    }
  }
  @host.apply_workspace_edit(location.root, tree, edit)
  for warning in edit.warnings {
    @platform.stderr("warning: " + warning + "\n")
  }
  let paths = edit.writes.keys().collect()
  paths.sort()
  let result : Json = {
    "successful": true,
    "writes": Json::array(paths.map(Json::string)),
    "directories": Json::array(edit.directories.map(Json::string)),
    "deletes": Json::array(edit.deletes.map(Json::string)),
    "warnings": Json::array(edit.warnings.map(Json::string)),
  }
  match mode {
    JSON => println(result.stringify())
    JSONLines => emit_record("workspace-edit", result)
    Human => {
      for path in paths {
        println("Wrote " + path)
      }
      for path in edit.deletes {
        println("Deleted " + path)
      }
    }
  }
  0
}

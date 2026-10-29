///|
/// Resolve run-wide services without traversing project source trees. Commands
/// still use workspace discovery when they need the Morphir all-member walk.
pub fn run_configuration(
  location : Location,
  environment : Map[String, String],
  options : @workspace.ConfigurationOptions,
  overlay? : @config.Document,
) -> @config.Document raise {
  let conventions = machine_conventions(
      @workspace.configuration_conventions(
        boundary=location.directory.to_string(),
      ),
    )
    |> @conventions.profiles(@profiles.Policy::new())
  let selection = match options.selected {
    Some(path) => @lander_config.SourceSelection::Explicit(path)
    None => Discover
  }
  let builder = @workspace.configuration_formats().fold(
      init=@lander_config.builder()
        |> @lander_config.working_dir(location.directory.to_string())
        |> @lander_config.platform(options.platform)
        |> @lander_config.env_vars(environment),
      (builder, format) => builder |> @lander_config.format(format),
    )
    |> @conventions.add(
      conventions,
      options=@conventions.DiscoveryOptions::new(
        config=selection,
        profiles=options.profiles,
        isolated=options.isolated,
      ),
    )
    |> @lander_config.env(
      prefix="MORPHIR",
      reserved=["MORPHIR_HOME", "MORPHIR_PROFILES"],
      selection=Explicit(environment),
    )
  let builder = match overlay {
    Some(document) =>
      builder
      |> @lander_config.add(
        @lander_config.in_memory(document.value(), name="CLI", priority=700),
      )
    None => builder
  }
  let mut tree = @lander_config.FileTree::new()
  for path, text in options.external_files {
    tree = tree.with_file(@lander_config.FileTreePath::parse(path), text)
  }
  let files = options.external_files.copy()
  while true {
    let step = @lander_config.load(builder, tree) catch {
      @lander_config.Ambiguous(candidates~, ..) =>
        raise @config.Invalid(
          "Ambiguous configuration: " + candidates.join(", "),
        )
      error => raise @config.Invalid(error.message())
    }
    match step {
      Need(requests) =>
        tree = read_configuration_requests(tree, requests, files, machine=true)
      Done(configuration) => return @config.from_framework(configuration)
    }
  } nobreak {
    abort("configuration load ended without a result")
  }
}

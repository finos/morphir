///|
test "run diagnostic settings use root format profile and environment precedence" {
  let parent = @platform.cwd() + "/.dev"
  if @platform.kind(parent) == 0 {
    @platform.mkdir(parent)
  }
  let path = parent + "/diagnostic-configuration-qualification-" + target_name()
  @platform.mkdir(path)
  defer {
    for name in @platform.list(path) {
      @platform.remove_file(path + "/" + name)
    }
    @platform.remove_dir(path)
  }
  @platform.write(path + "/morphir.json5", "{logging:{level:'info'}}")
  @platform.write(
    path + "/morphir.toml",
    "logging.level='debug'\nprofiles.default=['metrics']",
  )
  @platform.write(
    path + "/morphir.profile.metrics.toml",
    "logging.level='trace'",
  )
  let location = @host.Location::at_root(path)
  for
    (environment, expected) in [
      (Map([]), "trace"),
      (Map::from_array([("MORPHIR_LOGGING__LEVEL", "warn")]), "warn"),
    ] {
    let options = @host.configuration_options(
      location,
      environment,
      isolated=true,
    )
    let configuration = @host.run_configuration(location, environment, options)
    assert_eq(
      @diagnostics.Settings::from_config(configuration.framework()).level.name(),
      expected,
    )
    assert_eq(
      @diagnostics.Settings::from_config(
        configuration.framework(),
        selected_level=Off,
      ).level.name(),
      "off",
    )
  }
}

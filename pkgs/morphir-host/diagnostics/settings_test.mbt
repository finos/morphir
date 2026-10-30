///|
test "diagnostic settings bind defaults and typed file options" {
  let defaults = @diagnostics.Settings::from_config(@lander_config.build([]))
  assert_eq(defaults.level, @diagnostics.Warn)
  assert_eq(defaults.files, @diagnostics.Disabled)
  let configuration = @lander_config.build([
    @lander_config.ConfigSource::defaults({
      "logging": {
        "level": "debug",
        "file": { "enabled": true, "format": "json-lines" },
      },
    }),
  ])
  let configured = @diagnostics.Settings::from_config(configuration)
  assert_eq(configured.level, @diagnostics.Debug)
  assert_eq(configured.files, @diagnostics.Enabled(@rolling.JsonLines))
  assert_eq(
    @diagnostics.Settings::from_config(configuration, selected_level=Off).level,
    @diagnostics.Off,
  )
  let invalid = @lander_config.build([
    @lander_config.ConfigSource::defaults({
      "logging": { "file": { "enabled": true, "format": "ion-binary" } },
    }),
  ])
  let message = try {
    ignore(@diagnostics.Settings::from_config(invalid))
    "accepted"
  } catch {
    @diagnostics.InvalidFileFormat(_) as error => error.message()
    error => error.to_string()
  }
  assert_true(message.contains("expected text or json-lines"), msg=message)
}

///|
test "diagnostic sessions use stderr and a separate bounded rolling file set" {
  let directory = @sinks.LogDirectory::from_absolute(
    @lander_core.AbsolutePath::parse("/repo/.morphir/logs"),
  )
  let settings : @diagnostics.Settings = {
    level: Debug,
    files: Enabled(JsonLines),
  }
  let session = settings.session(directory)
  assert_eq(session.console().unwrap().stream(), @sinks.StandardError)
  let file = session.files()[0]
  assert_eq(file.files().stem().to_string(), "morphir-diagnostics")
  assert_eq(file.files().format(), @rolling.JsonLines)
  assert_eq(file.json_properties(), @formatting.NamedObject)
  guard file.files().policy() is DailyAndSize(limit) else {
    fail("daily and size rolling")
  }
  assert_eq(limit.to_int64(), 10485760L)
  guard file.retention() is KeepNewest(count) else { fail("bounded retention") }
  assert_eq(count.to_int(), 31)
  let off : @diagnostics.Settings = { level: Off, files: Enabled(JsonLines), }
  assert_eq(off.session(directory).console(), None)
  assert_true(off.session(directory).files().is_empty())
}

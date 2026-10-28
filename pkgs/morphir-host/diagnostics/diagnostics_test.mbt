///|
test "diagnostic levels map the public names to framework levels and off" {
  for
    (name, minimum) in [
      ("trace", Some(@logging.Trace)),
      ("debug", Some(@logging.Debug)),
      ("info", Some(@logging.Information)),
      ("warn", Some(@logging.Warning)),
      ("error", Some(@logging.Error)),
      ("fatal", Some(@logging.Critical)),
      ("off", None),
    ] {
    let level = @diagnostics.DiagnosticLevel::parse(name)
    assert_eq(level.name(), name)
    assert_eq(level.minimum(), minimum)
  }
  for invalid in ["loud", "", "Warning", "warn "] {
    let message = try {
      ignore(@diagnostics.DiagnosticLevel::parse(invalid))
      "accepted"
    } catch {
      error => error.message()
    }
    assert_true(message.contains(invalid))
    assert_true(
      message.contains("trace, debug, info, warn, error, fatal or off"),
    )
  }
}

///|
test "level selection uses the resolved configuration and a validated override" {
  let empty = @lander_config.build([])
  assert_eq(@diagnostics.level_from_config(empty).name(), "warn")
  let configured = @lander_config.build([
    @lander_config.ConfigSource::defaults({ "logging": { "level": "info" } }),
    @lander_config.ConfigSource::overrides([
      ("logging.level", @lander_config.string("debug")),
    ]),
  ])
  assert_eq(@diagnostics.level_from_config(configured).name(), "debug")
  let invalid = @lander_config.build([
    @lander_config.ConfigSource::defaults({ "logging": { "level": "loud" } }),
  ])
  assert_eq(
    @diagnostics.level_from_config(invalid, selected_level=Off).name(),
    "off",
  )
  assert_true(
    try {
      ignore(@diagnostics.level_from_config(invalid))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "text logging uses UTC category properties and framework filtering" {
  let lines : Array[String] = []
  let ticks = Ref(0)
  let now = @formatting.LogTimestamp::from_epoch_millis(0L)
  let logger = @logging.with_category(
    @diagnostics.text_logger(Warn, line => lines.push(line), fn() {
      ticks.val += 1
      now
    }),
    "morphir.configuration",
  )
  logger.info("Hidden {Path}", [Json::string("private")])
  logger.warn("Loaded {Path}", [Json::string("/workspace/morphir.toml")])
  logger.error("Failure {Count}", [Json::number(2.0)])
  logger.critical("Fatal", [])
  assert_eq(lines.length(), 3)
  assert_eq(ticks.val, 3)
  assert_true(lines[0].has_prefix("1970-01-01T00:00:00.000Z"))
  assert_true(lines[0].contains("morphir.configuration"))
  assert_true(lines[0].contains("/workspace/morphir.toml"))
  assert_true(
    lines.all(line => line.has_suffix("\n") && !line.contains("private")),
  )
  let disabled = @diagnostics.text_logger(Off, line => lines.push(line), fn() {
    ticks.val += 1
    now
  })
  disabled.critical("Never accepted", [])
  assert_eq(lines.length(), 3)
  assert_eq(ticks.val, 3)
}

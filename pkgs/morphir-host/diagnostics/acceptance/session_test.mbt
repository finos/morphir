///|
#cfg(target="native")
fn target_name() -> String {
  "native"
}

///|
#cfg(target="js")
fn target_name() -> String {
  "js"
}

///|
async test "public diagnostic sink preserves structured properties and telemetry during retention" {
  let parent = @platform.cwd() + "/.dev"
  if @platform.kind(parent) == 0 {
    @platform.mkdir(parent)
  }
  let path = parent + "/diagnostic-sink-qualification-" + target_name()
  // Exclusive creation refuses stale evidence rather than deleting it.
  @platform.mkdir(path)
  defer {
    for name in @platform.list(path) {
      @platform.remove_file(path + "/" + name)
    }
    @platform.remove_dir(path)
  }
  for index in 1..<=40 {
    let sequence = index.to_string().pad_start(3, '0')
    @platform.write(
      path + "/morphir-diagnostics-19700101_" + sequence + ".jsonl",
      "old\n",
    )
  }
  @platform.write(path + "/frontend.ionb", "telemetry bytes")
  @platform.write(
    path + "/morphir-diagnostics-19700101.jsonl.bak",
    "unowned bytes",
  )
  let directory = @sinks.LogDirectory::from_absolute(
    @lander_core.AbsolutePath::parse(path),
  )
  let settings : @diagnostics.Settings = {
    level: Debug,
    files: Enabled(JsonLines),
  }
  let clock = @formatting.LogTimestamp::from_epoch_millis(86400000L)
  let report = @runtime.with_session(
    settings.session(directory),
    session => {
      let logger : &@logging.Logger = session.logger()
      logger.warn(
        "Loaded {path}, then {path}; {level}; {value} {value} {value}",
        [
          Json::string("/repo/morphir.toml"),
          Json::string("/repo/app/morphir.toml"),
          Json::string("project"),
          Json::null(),
          Json::array([Json::number(1.0), Json::number(2.0)]),
          Json::object(Map::from_array([("enabled", Json::boolean(true))])),
        ],
      )
      logger.debug("Sources {paths}", [
        Json::array([Json::string("a"), Json::string("b")]),
      ])
      session.close()
    },
    clock=() => clock,
  )
  assert_true(report.closed())
  assert_true(
    !report.delivery_failed(),
    msg=report.failure_messages().join("\n"),
  )
  assert_eq(report.accepted(), 2L)
  assert_eq(report.dropped().total(), 0L)
  let records = @platform.read(path + "/morphir-diagnostics-19700102.jsonl")
    .trim()
    .split("\n")
    .map(StringView::to_owned)
    .collect()
    .map(text => @json.parse(text))
  assert_eq(records.length(), 2)
  guard records[0] is Object(first) else { fail("JSON record") }
  assert_eq(
    first.get("timestamp"),
    Some(Json::string("1970-01-02T00:00:00.000Z")),
  )
  guard first.get("properties") is Some(Object(properties)) else {
    fail("named properties")
  }
  assert_eq(
    properties.get("path"),
    Some(Json::string("/repo/app/morphir.toml")),
  )
  assert_eq(properties.get("level"), Some(Json::string("project")))
  assert_eq(
    properties.get("value"),
    Some(Json::object(Map::from_array([("enabled", Json::boolean(true))]))),
  )
  guard first.get("duplicateProperties") is Some(Object(duplicates)) else {
    fail("duplicate history")
  }
  assert_eq(
    duplicates.get("path"),
    Some(
      Json::array([
        Json::string("/repo/morphir.toml"),
        Json::string("/repo/app/morphir.toml"),
      ]),
    ),
  )
  assert_eq(
    duplicates.get("value"),
    Some(
      Json::array([
        Json::null(),
        Json::array([Json::number(1.0), Json::number(2.0)]),
        Json::object(Map::from_array([("enabled", Json::boolean(true))])),
      ]),
    ),
  )
  assert_true(!duplicates.contains("level"))
  assert_true(first.get("level") != properties.get("level"))
  guard records[1] is Object(second) else { fail("second JSON record") }
  assert_true(!second.contains("duplicateProperties"))
  guard second.get("properties") is Some(Object(single)) else {
    fail("single properties")
  }
  assert_eq(
    single.get("paths"),
    Some(Json::array([Json::string("a"), Json::string("b")])),
  )
  let names = @platform.list(path)
  assert_eq(
    names
    .filter(name => {
      name.has_prefix("morphir-diagnostics-") && name.has_suffix(".jsonl")
    })
    .length(),
    31,
  )
  assert_true(!names.any(name => name.has_suffix(".lock")))
  assert_eq(@platform.read(path + "/frontend.ionb"), "telemetry bytes")
  assert_eq(
    @platform.read(path + "/morphir-diagnostics-19700101.jsonl.bak"),
    "unowned bytes",
  )
}

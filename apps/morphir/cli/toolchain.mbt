///|
fn toolchain_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  let operation = cli.command[10:].to_owned()
  let fields : Map[String, Json] = Map::from_array([
    ("operation", Json::string(operation)),
  ])
  if flag(cli, "yes") {
    fields["consent"] = Json::boolean(true)
  }
  for key in ["home", "target", "package", "timeout"] {
    if !values(cli, key).is_empty() {
      fields[key] = if key == "timeout" {
        @json.parse(value(cli, key))
      } else {
        Json::string(value(cli, key))
      }
    }
  }
  if !values(cli, "path").is_empty() {
    fields[if operation == "exec" { "script" } else { "directory" }] = Json::string(
      value(cli, "path"),
    )
  }
  if cli.forwarded is Some(args) {
    fields["args"] = Json::array(args.map(Json::string))
  }
  let result = @toolchain.Host::platform().request(Json::object(fields))
  if mode is JSONLines {
    emit_record("toolchain", result)
  } else if mode is JSON {
    println(result.stringify())
  } else if result is Object(fields) {
    if fields.get("process") is Some(Object(process)) {
      if process.get("stdout") is Some(String(text)) {
        if text != "" {
          println(text)
        }
      }
      if process.get("stderr") is Some(String(text)) {
        @platform.stderr(text)
      }
    } else if fields.get("home") is Some(String(home)) {
      println("MoonBit " + @toolchain.compiler_version + "\nHome: " + home)
    } else if fields.get("supported") is Some(False) {
      println("Process tooling is unavailable on this host.")
    } else {
      println("No toolchain found. Run morphir toolchain setup --yes.")
    }
  }
  if result is Object(fields) {
    if fields.get("process") is Some(Object(process)) {
      if process.get("exitCode") is Some(Number(code, ..)) {
        return if code < 0.0 { 1 } else { code.to_int() }
      }
    }
  }
  0
}

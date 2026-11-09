///|
/// The generated identity is committed because dependency builds skip build
/// rules. Release inventory checks validate it against the module manifest.
fn embedded_version(identity : Json) -> Json raise {
  guard identity is Object(fields) &&
    fields.get("name") is Some(String(name)) &&
    name == "finos/morphir" &&
    fields.get("version") is Some(String(version)) &&
    !version.is_empty() else {
    raise @config.Invalid("Embedded CLI release identity is incomplete")
  }
  { "name": name, "version": version }
}

///|
fn version_report(result : Json) -> Json {
  {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "version",
    "state": "succeeded",
    "exitCode": 0,
    "diagnostics": [],
    "result": result,
  }
}

///|
fn version_command(mode : OutputMode) -> Int32 {
  let result = embedded_version(release_identity) catch {
    _ =>
      return version_failure(
        mode,
        "Embedded CLI release metadata is invalid",
        1,
        InvalidMetadata,
      )
  }
  match mode {
    Human => {
      guard result is Object(fields) &&
        fields.get("version") is Some(String(version)) else {
        return 1
      }
      println("Morphir " + version)
    }
    JSON => println(version_report(result).stringify())
    JSONLines => emit_record("result", version_report(result))
  }
  0
}

///|
priv enum VersionFailureKind {
  InvalidMetadata
  OperationFailed
  Cancelled
}

///|
fn version_failure(
  mode : OutputMode,
  message : String,
  status : Int32,
  kind : VersionFailureKind,
) -> Int32 {
  @platform.stderr(message + "\n")
  let code = match kind {
    InvalidMetadata => "version.invalid_metadata"
    OperationFailed => "version.failed"
    Cancelled => "version.cancelled"
  }
  let report : Json = {
    "profile": "morphir/command-result",
    "contractVersion": "0.1.0",
    "command": "version",
    "state": "failed",
    "exitCode": status,
    "diagnostics": [],
    "error": { "code": code, "message": message },
  }
  match mode {
    JSON => println(report.stringify())
    JSONLines => emit_record("result", report)
    Human => ()
  }
  status
}

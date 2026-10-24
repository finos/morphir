///|
fn fault_command() -> @argparse.Command {
  @argparse.Command(
    // Keep dash-leading filenames and historically ignored trailing operands.
    "protocol-fault",
    disable_help_flag=true,
    positionals=[
      @argparse.PositionArg(
        "checkpoint",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
      ),
      @argparse.PositionArg(
        "fault",
        num_args=@argparse.ValueRange::single(),
        allow_hyphen_values=true,
      ),
      @argparse.PositionArg(
        "ignored",
        num_args=@argparse.ValueRange(lower=0),
        allow_hyphen_values=true,
      ),
    ],
  )
}

///|
fn parse_fault_operands(argv : ArrayView[String]) -> @argparse.Matches raise {
  // All user tokens are literal data. Only this synthetic delimiter is syntax.
  let literal = ["--"] + argv.to_owned()
  fault_command().parse(argv=literal)
}

///|
#cfg(target="js")
fn fault_operands() -> ArrayView[String] {
  // Match pinned core argparse's private default_argv runtime-prefix ownership.
  match @env.args() {
    [_, _, .. rest] => rest
    _ => []
  }
}

///|
#cfg(not(target="js"))
fn fault_operands() -> ArrayView[String] {
  match @env.args() {
    [_, .. rest] => rest
    [] => []
  }
}

///|
/// Acceptance-only mutator uses the pipeline's Ion codec, including symbol tables.
fn mutate(arguments : ArrayView[String], structured : Bool) -> Json raise {
  let args = parse_fault_operands(arguments) catch {
    // Missing operands historically panic without writing to either channel.
    error => if structured { raise error } else { panic() }
  }
  let path = args.values["checkpoint"][0]
  let fault = args.values["fault"][0]
  if structured &&
    ![
      "truncated", "malformed", "oversize", "missing", "extra", "duplicate", "reordered",
      "wrong-id", "duration", "value", "wrong-suite", "wrong-profile", "wrong-trace",
      "extensions", "duplicate-field",
    ].contains(fault) {
    raise PresentationError("unknown fault: " + fault)
  }
  let bytes = @fs.read_file_to_bytes(path)
  if fault == "truncated" {
    if structured && bytes.is_empty() {
      raise PresentationError("cannot truncate empty checkpoint")
    }
    let output = bytes[:bytes.length() - 1].to_owned()
    @fs.write_bytes_to_file(path, output)
    return { "fault": fault, "path": path, "bytesWritten": output.length() }
  }
  if fault == "malformed" {
    @fs.write_bytes_to_file(path, b"not Ion")
    return { "fault": fault, "path": path, "bytesWritten": 7 }
  }
  if fault == "oversize" {
    @fs.write_bytes_to_file(path, Bytes::make(1048577, 0))
    return { "fault": fault, "path": path, "bytesWritten": 1048577 }
  }
  let fields = @protocol.fields(@binary.read_binary_value(bytes[:]), [
    "profile", "suite_identity", "calls", "traceparent", "extensions",
  ])
  guard @protocol.required(fields, "calls").kind() is List(calls) else {
    if structured {
      raise PresentationError("calls must be a list")
    } else {
      abort("calls")
    }
  }
  if structured {
    let required = match fault {
      "duplicate" | "reordered" => 2
      "missing" | "extra" | "wrong-id" | "duration" | "value" => 1
      _ => 0
    }
    if calls.length() < required {
      raise PresentationError("insufficient calls for fault: " + fault)
    }
  }
  if structured {
    for name in ["profile", "suite_identity", "traceparent", "extensions"] {
      ignore(@protocol.required(fields, name))
    }
    if ["wrong-id", "duration", "value"].contains(fault) {
      let first = @protocol.fields(calls[0], ["id", "value", "duration_seconds"])
      for name in ["id", "value", "duration_seconds"] {
        ignore(@protocol.required(first, name))
      }
    }
  }
  let calls = calls.copy()
  match fault {
    "missing" => {
      ignore(calls.pop())
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "extra" => {
      calls.push(calls[0])
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "duplicate" => {
      calls[1] = calls[0]
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "reordered" => {
      let first = calls[0]
      calls[0] = calls[1]
      calls[1] = first
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "wrong-id" | "duration" | "value" => {
      let call = @protocol.fields(calls[0], ["id", "value", "duration_seconds"])
      match fault {
        "wrong-id" => call["id"] = @ion.IonValue::string("unknown")
        "duration" => call["duration_seconds"] = @ion.IonValue::float(-1.0)
        _ => call["value"] = @ion.IonValue::string("wrong type")
      }
      calls[0] = @protocol.record([
        ("id", call["id"]),
        ("value", call["value"]),
        ("duration_seconds", call["duration_seconds"]),
      ])
      fields["calls"] = @ion.IonValue::list(calls)
    }
    "wrong-suite" =>
      fields["suite_identity"] = @ion.IonValue::string("0".repeat(64))
    "wrong-profile" =>
      fields["profile"] = @ion.IonValue::string("morphir-outcomes-v0")
    "wrong-trace" => fields["traceparent"] = @ion.IonValue::string("unrelated")
    "extensions" => fields["extensions"] = @ion.IonValue::string("changed")
    "duplicate-field" => ()
    _ => abort("unknown fault")
  }
  let output = [
    "profile", "suite_identity", "calls", "traceparent", "extensions",
  ].map(name => (name, fields[name]))
  if fault == "duplicate-field" {
    output.push(("calls", fields["calls"]))
  }
  let encoded = @binary.write_binary_value(@protocol.record(output))
  @fs.write_bytes_to_file(path, encoded)
  { "fault": fault, "path": path, "bytesWritten": encoded.length() }
}

///|
fn main raise {
  match presentation(fault_operands()) {
    JsonHelp => json_help()
    Legacy(raw) => ignore(mutate(raw, false))
    Structured(raw) => {
      let result = mutate(raw, true) catch {
        error => {
          json_output(failed(error).stringify())
          failure_exit()
          return
        }
      }
      json_output(completed(result).stringify())
    }
  }
}
